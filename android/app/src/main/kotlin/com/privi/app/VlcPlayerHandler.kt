package com.privi.app

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.view.Surface
import io.flutter.view.TextureRegistry
import org.videolan.libvlc.LibVLC
import org.videolan.libvlc.Media
import org.videolan.libvlc.MediaPlayer
import org.videolan.libvlc.interfaces.IMedia
import org.videolan.libvlc.interfaces.IVLCVout
import java.io.File
import java.util.concurrent.Executor

class VlcPlayerHandler(
    private val context: Context,
    private val textureEntry: TextureRegistry.SurfaceTextureEntry,
    /**
     * 只用来把 `media.parse()` 挪出主线程（见 [probeVideoSizeAsync]）。
     * 复用 MainActivity 的 IO 线程池，`onDestroy` 关池子时自动收尾。
     */
    private val ioExecutor: Executor,
    private val eventSink: (String, Map<String, Any?>?) -> Unit
) : PlayerHandler {
    companion object {
        private const val TAG = "PriviVlcPlayer"

        /**
         * 只有探测不到真实视频尺寸时才会用到的兜底值。
         *
         * 注意这**不是**一个"越大越安全"的值：Android 的两条 vout 路径都
         * 直接使用 ANativeWindow 的当前几何尺寸，BufferQueue 并不会自动放大。
         * 兜底值小于视频尺寸时必然会黑屏（见 [applyVideoSize] 的注释）。
         */
        private const val FALLBACK_BUFFER_WIDTH = 1920
        private const val FALLBACK_BUFFER_HEIGHT = 1080

        /**
         * 探测值必须向上对齐到这个倍数，理由是同一条约束的两半：
         *
         *  * VLC 侧 `AndroidWindow_Setup()`（display.c）在非 opaque 路径里
         *    会把缓冲区宽度**向上**取整：
         *      `align_pixels = (16 / p_pic->p[0].i_pixel_pitch) - 1;`
         *      `fmt.i_width  = (p_pic->format.i_width + align_pixels) & ~align_pixels;`
         *    RGB32 的 pixel_pitch 是 4 ⇒ 对齐到 4 的倍数。
         *    （VLC 自己的源码注释写得很直白：
         *     `// For RGB (32 or 16) we need to align on 8 or 4 pixels, 16 pixels for YUV`
         *     ⇒ 若哪天把 `--android-display-chroma=RV32` 去掉，Java 层会自动
         *     注入 RV16，这里就必须改成 8。）
         *  * 锁图时每帧都校验 `sw.buf.width >= fmt.i_width`，不满足直接
         *    `return -1`（`AndroidWindow_LockPicture()`），一帧都画不出来。
         *
         * 所以 854x480 这种宽度不是 4 的倍数的片子，探测值 854 会让第一帧
         * 的锁图失败。**只对齐探测/兜底值**：布局回调给的值是 VLC 自己算好的
         * `fmt.i_width`/`i_visible_width`，再对齐反而会让缓冲区比 vout 实际
         * 使用的矩形宽，右边会多出一条未初始化像素（纯色细条）。
         */
        private const val BUFFER_WIDTH_ALIGN = 4

        @Volatile
        private var sharedLibVlc: LibVLC? = null

        @Synchronized
        fun getLibVlc(context: Context): LibVLC {
            return sharedLibVlc ?: LibVLC(context, arrayListOf(
                "--no-audio-time-stretch",
                // **这一行必须保持 0。** 排障时临时改成 2，定位完立刻改回来。
                //
                // 不只是"日志啰嗦"：本类的 log() 把**每一条** libvlc 日志都经
                // eventSink → videoChannel.invokeMethod 转发给 Dart，而 verbose=2
                // 是逐帧/逐事件输出 ⇒ 每一行都是一次跨平台通道调用，会刷爆
                // MethodChannel 并拖慢解码线程。
                //
                // 需要在真机上盯的视频渲染日志（display.c 里的原文，**不要**按
                // "using android-opaque" 去搜，那个字符串不存在）：
                //   * `using opaque` / `using ANWP` / `using ANW`
                //     ⇒ android vout 打开了（opaque = MediaCodec 直写；
                //        ANWP = 私有 ANativeWindow；ANW = 标准 ANativeWindow）。
                //   * 这三行一条都没有，只有 gles2 相关的行
                //     ⇒ canSetVideoLayout 仍为 false，监听器没生效，
                //       黑屏根因还在。
                //   * `PoolAlloc: request N frames` / `got N frames`
                //     ⇒ 走到建图池了（SetupANWP/SetupANW 至少有一条成功）。
                "--verbose=0",
                // **不要删这一行。** 它看上去是"写了默认值等于没写"，其实不是：
                //
                // LibVLC 的 Java 构造函数（javap -c 反编译 libvlc-all 3.6.4 已确认）
                // 会扫描传进来的选项列表，只要**没有**以
                // "--android-display-chroma" 开头的项，就往列表里自动追加
                //     "--android-display-chroma" 和 "RV16"
                // 两个 argv 项；同一段逻辑还会在没有 "--aout=" 时追加
                // --aout=opensles / --aout=android_audiotrack。
                //   int r = 1; ... if (...startsWith("--android-display-chroma")...)
                // ⇒ 删掉这行并不会"回到默认值 RGB32"，而是把软件解码路径
                //   切到 **RV16（RGB565）**：
                //     * display.c 的 ChromaToAndroidHal() 把 RGB16 映射成
                //       WINDOW_FORMAT_RGB_565，再经 setBuffersGeometry/
                //       setBuffersGeometryANWP 落到 SurfaceTexture 的缓冲区格式上；
                //       而我们的消费端是 Flutter 的 external OES 纹理（默认按
                //       RGBA/RGBX 采样）⇒ 可能直接是错色/纯色/黑屏。
                //     * RGB16 的 i_pixel_pitch 是 2，`AndroidWindow_Setup()` 里的
                //       `align_pixels = (16 / i_pixel_pitch) - 1` 会变成 7，
                //       宽度对齐从 4 变 8（见 [BUFFER_WIDTH_ALIGN]）。
                // RV32 == VLC_CODEC_RGB32，映射到 WINDOW_FORMAT_RGBX_8888，
                // 和硬件路径（MediaCodec 直写 Surface）用的格式族一致。
                //
                // 它只对软件路径（android-display，capability 260）有意义：
                // OpenCommon() 在 i_chroma == ANDROID_OPAQUE 时会整段跳过
                // chroma 设置。也**不能**用它去选 vout 模块（优先级 280 > 265 > 260）。
                "--android-display-chroma=RV32",
            )).also { sharedLibVlc = it }
        }

        fun releaseLibVlc() {
            synchronized(this) {
                sharedLibVlc?.release()
                sharedLibVlc = null
            }
        }
    }

    private var mediaPlayer: MediaPlayer? = null
    private var mediaRef: Media? = null
    private var surface: Surface? = null
    private var libVlc: LibVLC? = null

    private val mainHandler = Handler(Looper.getMainLooper())

    private var durationMs = 0L

    /**
     * [videoWidth]/[videoHeight] 由 VLC 的 vout 线程（布局回调里同步调用
     * [applyVideoSize]）和主线程（探测兜底、status）两边写，所以必须是
     * volatile：主线程在 `initialized` 之后立刻读它来算宽高比。
     */
    @Volatile
    private var videoWidth = 0
    @Volatile
    private var videoHeight = 0

    /**
     * 上报给 Dart 的“可视”尺寸，只用于推导宽高比（Dart 端
     * `NativeVideoValue.aspectRatio == size.width / size.height`）。
     *
     * **不能拿 [videoWidth]/[videoHeight] 上报**：那是缓冲区几何，宽度是
     * `fmt.i_width` 对齐后的值，比可视宽最多多出 [BUFFER_WIDTH_ALIGN] - 1 像素
     * （`AndroidWindow_Setup()` 里的 `align_pixels`）。缓冲区必须用对齐后的值
     * （锁图时每帧比的就是它），而宽高比要用可视值，否则画面会被轻微拉伸。
     *
     * 布局回调同时给出 4 个数：`w/h`（VLC 要用的缓冲区矩形）和
     * `visibleW/visibleH`（可视矩形）。ANWP 路径 `w` 就是 `i_visible_width`，
     * 两者相等；非 ANWP 路径 `w` 是 `fmt.i_width`，可能差几个像素。
     * 这里的值由 [applyVideoSize] 的 `visibleWidth/visibleHeight` 传入；
     * 探测/兜底路径没有可视信息，就退化成缓冲区尺寸。
     */
    @Volatile
    private var displayWidth = 0
    @Volatile
    private var displayHeight = 0

    /**
     * 布局回调是否已经送回过真实几何。
     *
     * 回调在 vout 线程上写、主线程上的探测兜底读 ⇒ volatile。
     * 为 true 时探测结果只记日志、不再覆盖（回调给的才是 VLC 真正使用的几何）。
     */
    @Volatile
    private var layoutSizeKnown = false

    private var isReady = false
    private var isEnded = false
    /** 是否收到过 voutCount > 0 的 Vout 事件（即 VLC 真的建起了视频输出）。 */
    private var hasVout = false
    private var lastPositionMs = 0L
    private var lastVolume = 1f
    private var lastSpeed = 1f

    override val textureId: Long get() = textureEntry.id()

    private fun log(level: String, message: String, error: Throwable? = null) {
        when (level) {
            "e" -> Log.e(TAG, message, error)
            "w" -> Log.w(TAG, message)
            "d" -> Log.d(TAG, message)
            else -> Log.i(TAG, message)
        }
        try {
            eventSink("log", mapOf(
                "textureId" to textureId,
                "level" to level,
                "text" to message
            ))
        } catch (e: Exception) {
            Log.w(TAG, "forwarding log line failed: ${e.message}")
        }
    }

    private fun logI(message: String) = log("i", message)
    private fun logD(message: String) = log("d", message)
    private fun logW(message: String) = log("w", message)
    private fun logE(message: String, error: Throwable? = null) =
        log("e", message, error)

    override fun initialize(filePath: String) {
        logI("initialize: textureId=$textureId, path=$filePath")
        logSourceFile(filePath)
        resetPlayer()

        try {
            val vlc = getLibVlc(context)
            libVlc = vlc

            val mp = MediaPlayer(vlc)
            mediaPlayer = mp

            val media = Media(vlc, filePath)
            mediaRef = media

            // 先给缓冲区一个**不会小于视频**的初始几何，然后立刻挂 vout。
            //
            // 这里**同步等不到**真实尺寸，也不该等：唯一能拿到真实尺寸的
            // 同步手段是 `media.parse()`，而它会真的把容器打开解析一遍
            // （本地小文件几毫秒，大/异常容器可以是几百毫秒到数秒），
            // 而 initialize() 是 MainActivity 在**主线程**上从 MethodChannel
            // 回调里调进来的 ⇒ 就是 ANR 风险。所以探测挪到后台线程
            // （[probeVideoSizeAsync]），这里先用兜底值。
            //
            // 真正的权威几何由布局回调同步送回来（见 attachViews 处），
            // 它发生在 PoolAlloc() 里 `AndroidWindow_Setup()`（几何定型）之后、
            // 第一帧 `AndroidWindow_LockPicture()` 之前 ⇒ 兜底值只在一小段
            // 窗口里有效。
            //
            // 唯一的硬要求是**不能比视频小**，依据是 C 侧
            // （vlc 3.6.x modules/video_output/android/display.c）：
            //   * 软件路径每帧都在 AndroidWindow_LockPicture() 里校验
            //       `sw.buf.width < fmt.i_width || sw.buf.height < fmt.i_height`
            //     ⇒ 缓冲区比视频小就 return -1，一帧都画不出来（全黑）。
            //   * `AndroidWindow_SetupANW()` 是 VLC 自己给缓冲区设几何的地方，
            //     但它是
            //       `if (sys->anw->setBuffersGeometry) return sys->anw->setBuffersGeometry(...);
            //        else return 0;`
            //     —— `sys->anw` 来自 `AWindowHandler_getANativeWindowAPI()`，是
            //     **native** 的函数指针表（不是 Java 方法；AWindow 里根本没有
            //     setBuffersGeometry）。指针缺失时它返回 0 = "成功"，于是 VLC
            //     什么都没设。**不能指望 VLC 自己把尺寸推下去** ⇒ 必须由
            //     SurfaceTexture.setDefaultBufferSize() 兜住。
            //   * 硬件路径（MediaCodec 直写 Surface）尺寸由解码器设置，
            //     这里的值不影响画面，但同样不能小于视频。
            videoWidth = alignBufferWidth(FALLBACK_BUFFER_WIDTH)
            videoHeight = FALLBACK_BUFFER_HEIGHT
            // 宽高比依据：回调来之前只能用它，回调一到就会被覆盖。
            displayWidth = videoWidth
            displayHeight = videoHeight

            mp.media = media

            val surfaceTexture = textureEntry.surfaceTexture()
            surfaceTexture.setDefaultBufferSize(videoWidth, videoHeight)

            surface = Surface(surfaceTexture)
            val vout: IVLCVout = mp.vlcVout
            vout.setVideoSurface(surface, null)
            vout.setWindowSize(videoWidth, videoHeight)

            // 关键：布局监听器必须作为 attachViews() 的参数传入。
            //
            // IVLCVout 在 libvlc-all 3.6.4 里**没有**
            // setOnNewVideoLayoutListener() 这个方法（javap -p 已确认），
            // 只有 attachViews(OnNewVideoLayoutListener)。
            // AWindow.attachViews(listener) 先把 mOnNewVideoLayoutListener
            // 赋值、再 registerNative()；javap 反编译确认
            //   `int r = 1; if (mOnNewVideoLayoutListener != null) r |= 2;`
            // AWindowHandler_canSetVideoLayout() 读的就是这个 bit 2。
            // display.c 的 OpenCommon() 里：
            //   if (!AWindowHandler_canSetVideoLayout(p_awh)) {
            //       vout_display_DeleteWindow(...); return VLC_EGENERIC;
            //   }
            // 也就是说 **不传监听器时 android-opaque(280) 和
            // android-display(260) 两条路径都会直接放弃打开**，VLC 退化到
            // gles2（或什么都渲染不出来）⇒ 全黑/纯色。
            // 这正是本次黑屏的根因，也是这次提交想修的东西。
            vout.attachViews(IVLCVout.OnNewVideoLayoutListener {
                    _, w, h, visibleW, visibleH, sarNum, sarDen ->
                if (w <= 0 || h <= 0) return@OnNewVideoLayoutListener
                // 回调跑在 vout 线程上，可能比 release() 慢一步：这一轮播放已经被
                // 拆掉（mediaPlayer 置空或被换成新的 MediaPlayer）时直接丢弃，
                // 否则会往已 release 的 textureEntry/SurfaceTexture 上写几何。
                if (mediaPlayer !== mp) return@OnNewVideoLayoutListener
                // **同步**设置缓冲区大小，不要 post 到主线程。
                //
                // 这个回调是 PoolAlloc() 里 AndroidWindow_Setup()（几何定型）
                // 之后、第一帧 AndroidWindow_LockPicture() 之前**同步**调进来的
                // （JNI AWindowHandler_setVideoLayout → Java 监听器，跑在 vout
                // 线程），而 SurfaceTexture.setDefaultBufferSize() 不受线程限制。
                // post 到主线程就会和第一帧抢时序：主线程慢一步，前若干帧仍然
                // 按旧尺寸校验 `sw.buf.width >= fmt.i_width`，直接 return -1 丢帧
                // —— 表现出来就是开头一段黑屏，甚至长时间黑屏。
                // 这里给的 w/h 就是 VLC 自己的 fmt（非 ANWP 路径 = fmt.i_width，
                // ANWP 路径 = i_visible_width，两条都 >= 锁图时的要求），
                // 所以**不要**再对它做对齐/取整，照抄即可。
                //
                // 先立标志再生效：后台的探测兜底看到 true 就不再覆盖
                // （它读的是 volatile，两边可能交错）。
                layoutSizeKnown = true
                val changed = applyVideoSize(
                    w,
                    h,
                    "layout",
                    emit = false,
                    visibleWidth = visibleW,
                    visibleHeight = visibleH
                )
                // eventSink/日志必须回主线程（平台通道调用约定）。
                mainHandler.post {
                    // 入队时间早于 release() 的回调要丢掉，否则会给 Dart 补发一个
                    // 已经 dispose 掉的 texture 的 initialized 事件。
                    if (mediaPlayer !== mp) return@post
                    logI("video layout: ${w}x$h, visible=${visibleW}x$visibleH, " +
                        "sar=${sarNum}:$sarDen, bufferChanged=$changed, " +
                        "textureId=$textureId")
                    if (changed) emitInitialized()
                }
            })
            logI("video surface attached to textureId=$textureId " +
                "at ${videoWidth}x$videoHeight")

            // 只是兜底与日志，见方法注释；不要改回同步调用。
            probeVideoSizeAsync(vlc, filePath, mp)

            mp.setEventListener { event ->
                // 这段跑在 libvlc 的事件线程上（不是主线程）：异常一旦逃出去
                // 就是进程级崩溃，所以整段包起来。
                try {
                    val type = event.type
                    // 事件对象是复用的，必须在回调里立刻取出需要的字段。
                    val voutCount =
                        if (type == MediaPlayer.Event.Vout) event.voutCount else 0
                    val length =
                        if (type == MediaPlayer.Event.LengthChanged) {
                            event.lengthChanged
                        } else {
                            -1L
                        }
                    // **不能在这里直接调 onMediaPlayerEvent**：它会读 mp.length /
                    // mp.time / mp.isPlaying，而这些是 native 方法，release() 之后
                    // 再调就是在已释放的 native 句柄上做 JNI 调用（进程崩溃且不留
                    // Dart 日志，见 ISSUE-015）。所以回到主线程并按"还是当前这一轮
                    // 播放"校验一次——切片够快时，事件刚好落在 release() 之后。
                    mainHandler.post {
                        if (mediaPlayer !== mp) return@post
                        onMediaPlayerEvent(type, voutCount, length, mp)
                    }
                } catch (e: Exception) {
                    Log.w(TAG, "event listener failed: ${e.message}")
                }
            }

            mp.play()
            logI("play() called for textureId=$textureId")
        } catch (e: Exception) {
            logE("initialize failed, cleaning up: ${e.message}", e)
            resetPlayer()
            throw e
        }
    }

    /**
     * 用 libvlc 的媒体解析（只解析容器，不解码）拿到第一路视频轨的编码尺寸。
     *
     * 这**不是**主路径：真实的几何由 [IVLCVout.OnNewVideoLayoutListener] 在
     * C 侧 PoolAlloc() → AndroidWindow_Setup()（几何已定型）之后、第一帧之前
     * 同步送回来，那个值才是 VLC 真正用的。这里只是兜底和日志
     * （用于诊断"回调没来"这一类问题）。
     *
     * 因此它**绝对不能**在主线程上调用，见 [probeVideoSizeAsync]。
     *
     * @return `[width, height, sarNum, sarDen]`，失败返回 `null`。
     */
    private fun probeVideoSize(media: Media): IntArray? {
        return try {
            if (!media.parse(IMedia.Parse.ParseLocal)) {
                logD("media.parse returned false")
                return null
            }
            for (i in 0 until media.trackCount) {
                val track = media.getTrack(i)
                if (track is IMedia.VideoTrack && track.width > 0 && track.height > 0) {
                    return intArrayOf(
                        track.width,
                        track.height,
                        track.sarNum,
                        track.sarDen
                    )
                }
            }
            logW("no video track reported by media.parse")
            null
        } catch (e: Exception) {
            logW("probeVideoSize failed: ${e.message}")
            null
        }
    }

    /**
     * 在后台线程跑 [probeVideoSize]，结果只用来兜底/记日志。
     *
     * 为什么必须异步：`Media.parse()` 会真的把容器打开解析一遍，本地小文件
     * 几毫秒，但大容器、损坏容器、慢存储（SD 卡/加密目录）上可以是几百毫秒
     * 到数秒。而 [initialize] 是 MainActivity 在**主线程**上从 MethodChannel
     * 回调里调进来的 —— 同步做就是直接把这个耗时算进主线程 ⇒ ANR 风险。
     *
     * 用**独立的 Media 对象**、不复用 [mediaRef]：播放中的 Media 正被
     * MediaPlayer 持有，再让后台线程对同一个 handle 做 parse 是没必要的
     * 跨线程共享，出问题很难查。
     *
     * 结果只在布局回调**还没**送到时才被采用（[layoutSizeKnown]）——
     * 回调给的才是 VLC 真正使用的几何。
     */
    private fun probeVideoSizeAsync(vlc: LibVLC, filePath: String, mp: MediaPlayer) {
        ioExecutor.execute {
            val probed: IntArray? = try {
                val probeMedia = Media(vlc, filePath)
                try {
                    probeVideoSize(probeMedia)
                } finally {
                    probeMedia.release()
                }
            } catch (e: Exception) {
                logW("video size probe failed: ${e.message}, textureId=$textureId")
                null
            }
            mainHandler.post {
                // initialize() 已经被另一次调用/release() 取代了，别再插手。
                if (mediaPlayer !== mp) return@post
                if (probed == null) {
                    logW("video size probe gave nothing, keeping " +
                        "${videoWidth}x$videoHeight until the layout callback " +
                        "arrives, textureId=$textureId")
                    return@post
                }
                logI("probed video size: ${probed[0]}x${probed[1]}, " +
                    "sar=${probed[2]}:${probed[3]}, textureId=$textureId")
                if (layoutSizeKnown) {
                    logI("layout callback already fixed ${videoWidth}x$videoHeight, " +
                        "ignoring probe result, textureId=$textureId")
                    return@post
                }
                // 回调没来才用它兜底。宽度必须对齐：VLC 的
                // AndroidWindow_Setup() 会把 fmt.i_width 向上取整到同一倍数，
                // 锁图时比的是取整后的值。
                applyVideoSize(
                    alignBufferWidth(probed[0]),
                    probed[1],
                    "probe"
                )
            }
        }
    }

    /**
     * 更新视频尺寸，并把同一份尺寸用于两处**必须一致**的地方：
     *  1. SurfaceTexture 的默认缓冲区大小（决定了 vout 能画到多大的缓冲上）；
     *  2. 上报给 Dart 的 `initialized.width/height`
     *     （Dart 端 `NativeVideoValue.aspectRatio` 用 width/height 推导
     *     `AspectRatio`，而 `Texture` 采样的是整块缓冲区）。
     *
     * 两者只要不一致，画面就会被拉伸；之前上报的是 `0x0`，
     * `aspectRatio` 的兜底值是 `1.0`，视频会被压成正方形。
     *
     * [visibleWidth]/[visibleHeight] 是**可视**尺寸（回调里的 visibleW/H）：
     * 有值时用它当上报值（宽高比），缓冲区仍然用 [width]x[height]。
     */
    private fun applyVideoSize(
        width: Int,
        height: Int,
        reason: String,
        emit: Boolean = true,
        visibleWidth: Int = 0,
        visibleHeight: Int = 0
    ): Boolean {
        if (width <= 0 || height <= 0) return false
        // 可视尺寸不可信时退回缓冲区尺寸（宁可有一点点拉伸，也不要 0/负数）。
        val dw = if (visibleWidth > 0) visibleWidth else width
        val dh = if (visibleHeight > 0) visibleHeight else height
        val changed = width != videoWidth || height != videoHeight ||
            dw != displayWidth || dh != displayHeight
        videoWidth = width
        videoHeight = height
        displayWidth = dw
        displayHeight = dh
        try {
            textureEntry.surfaceTexture().setDefaultBufferSize(width, height)
        } catch (e: Exception) {
            logW("setDefaultBufferSize(${width}x$height) failed: ${e.message}")
        }
        // 尺寸是 initialized 之后才变准的（layout 回调晚于 Playing 时序也可能发生）
        // ⇒ 重发 initialized 让 Dart 端修正宽高比；_applyInitialized() 可重入。
        //
        // emit=false 只用在布局回调里：那里跑在 vout 线程上，eventSink 必须由
        // 调用方 post 回主线程。返回值告诉调用方要不要发。
        if (changed && isReady && emit) {
            logI("re-emitting initialized after size fix ($reason)")
            emitInitialized()
        }
        return changed
    }

    /**
     * 把宽度向上对齐到 [BUFFER_WIDTH_ALIGN]。
     *
     * 只用于**探测/兜底**值：VLC 的 `AndroidWindow_Setup()` 会把 `fmt.i_width`
     * 向上取整到同一个倍数，而锁图时比的是取整后的值。布局回调给的值已经是对齐
     * 后的结果，不能再动（会多出一条未初始化像素）。
     */
    private fun alignBufferWidth(width: Int): Int =
        (width + BUFFER_WIDTH_ALIGN - 1) and (BUFFER_WIDTH_ALIGN - 1).inv()

    private fun emitInitialized() {
        // 上报的是**可视**尺寸（宽高比依据），不是缓冲区尺寸。
        val w = if (displayWidth > 0) displayWidth else videoWidth
        val h = if (displayHeight > 0) displayHeight else videoHeight
        logI("STATE_READY: textureId=$textureId, duration=${durationMs}ms, " +
            "size=${w}x$h (buffer ${videoWidth}x$videoHeight)")
        eventSink("initialized", mapOf(
            "textureId" to textureId,
            "duration" to durationMs,
            "width" to w,
            "height" to h
        ))
    }

    private fun onMediaPlayerEvent(
        eventType: Int,
        voutCount: Int,
        reportedLength: Long,
        mp: MediaPlayer
    ) {
        // 兜底校验：调用点已经过滤过一次，这里再确认一次——保证将来任何新增调用点
        // 都不会在一个已经 release() 的 MediaPlayer 上读 native 字段。
        if (mp !== mediaPlayer) {
            Log.d(TAG, "dropping stale event for textureId=$textureId")
            return
        }
        when (eventType) {
            MediaPlayer.Event.Playing -> {
                if (!isReady) {
                    isReady = true
                    durationMs = mp.length.coerceAtLeast(0L)
                    emitInitialized()
                }
                eventSink("playingChanged", mapOf(
                    "textureId" to textureId,
                    "isPlaying" to true
                ))
                logI("onPlaying: textureId=$textureId")
            }
            MediaPlayer.Event.Paused -> {
                eventSink("playingChanged", mapOf(
                    "textureId" to textureId,
                    "isPlaying" to false
                ))
                logI("onPaused: textureId=$textureId")
            }
            MediaPlayer.Event.Stopped -> {
                logI("onStopped: textureId=$textureId")
            }
            MediaPlayer.Event.EndReached -> {
                isEnded = true
                lastPositionMs = durationMs
                logI("STATE_ENDED: textureId=$textureId, position=$durationMs")
                eventSink("completed", mapOf("textureId" to textureId))
            }
            MediaPlayer.Event.EncounteredError -> {
                logE("onEncounteredError: textureId=$textureId")
                eventSink("error", mapOf(
                    "textureId" to textureId,
                    "message" to "VLC playback error",
                    "code" to -1,
                    "diag" to "vlc:error"
                ))
            }
            MediaPlayer.Event.TimeChanged -> {
                val newPos = clampPosition(mp.time)
                if (newPos != lastPositionMs) {
                    lastPositionMs = newPos
                }
            }
            // mp.length 在 Playing 那一刻可能还是 0/-1（容器还没解析完），
            // 只靠 Playing 里读一次会把时长永久钉死在 0，进度条/拖动全废。
            MediaPlayer.Event.LengthChanged -> {
                val length = reportedLength.coerceAtLeast(0L)
                if (length > 0 && length != durationMs) {
                    durationMs = length
                    logI("length changed: ${durationMs}ms, textureId=$textureId")
                    if (isReady) emitInitialized()
                }
            }
            // 之前这里读的是 areViewsAttached()，那是"我们的 Surface 挂上了
            // 没有"，和"VLC 建起视频输出没有"是两件事。真正有意义的是
            // ev.voutCount：为 0 就说明 vout 根本没打开（黑屏的首要嫌疑）。
            MediaPlayer.Event.Vout -> {
                // voutCount 是"当前有几个视频输出"，不是"曾经有过几个"：
                // 中途 vout 挂掉（解码器/渲染失败）时必须跟着变回 false，
                // 否则诊断会一直报"画面已经出来了"，把黑屏说成正常。
                hasVout = voutCount > 0
                logI("Vout event: voutCount=$voutCount, " +
                    "viewsAttached=${mp.vlcVout.areViewsAttached()}, " +
                    "videoTracks=${mp.videoTracksCount}, textureId=$textureId")
            }
        }
    }

    /**
     * durationMs 未知时（仍是 0）不要按它裁剪，否则 position 会被永久压成 0。
     */
    private fun clampPosition(positionMs: Long): Long =
        if (durationMs > 0) positionMs.coerceIn(0L, durationMs)
        else positionMs.coerceAtLeast(0L)

    private fun logSourceFile(filePath: String) {
        try {
            val file = File(filePath)
            logI("source file: exists=${file.exists()}, size=${file.length()}B, " +
                "readable=${file.canRead()}, modified=${file.lastModified()}")
        } catch (e: Exception) {
            logW("source file probe failed for $filePath: ${e.message}")
        }
    }

    override fun play() {
        val mp = mediaPlayer
        if (mp == null) {
            logW("play ignored: no player for textureId=$textureId")
            return
        }
        mp.play()
        logI("play: textureId=$textureId")
    }

    override fun pause() {
        val mp = mediaPlayer
        if (mp == null) {
            logW("pause ignored: no player for textureId=$textureId")
            return
        }
        mp.pause()
        logI("pause: textureId=$textureId")
    }

    override fun seekTo(positionMs: Long) {
        val mp = mediaPlayer
        if (mp == null) {
            logW("seekTo ignored: no player for textureId=$textureId")
            return
        }
        // durationMs 未知时不能拿它去裁剪，否则 seek 会被压回 0。
        mp.time = clampPosition(positionMs)
        lastPositionMs = clampPosition(mp.time)
        logD("seekTo: textureId=$textureId, positionMs=$positionMs")
    }

    override fun setVolume(volume: Double) {
        val mp = mediaPlayer
        if (mp == null) {
            logW("setVolume ignored: no player for textureId=$textureId")
            return
        }
        val vol = volume.toFloat().coerceIn(0f, 1f)
        lastVolume = vol
        mp.setVolume((vol * 100).toInt())
        logD("setVolume: textureId=$textureId, volume=$vol")
    }

    override fun setPlaybackSpeed(speed: Double) {
        val mp = mediaPlayer
        if (mp == null) {
            logW("setPlaybackSpeed ignored: no player for textureId=$textureId")
            return
        }
        lastSpeed = speed.toFloat()
        mp.rate = lastSpeed
        logD("setPlaybackSpeed: textureId=$textureId, speed=$speed")
    }

    override fun getPosition(): Long {
        if (isEnded) return durationMs
        val mp = mediaPlayer ?: return 0L
        return clampPosition(mp.time)
    }

    override fun getDuration(): Long {
        val mp = mediaPlayer ?: return durationMs
        // 兜底再读一次：LengthChanged 之后 libvlc 才知道真实时长。
        if (durationMs <= 0L) {
            durationMs = mp.length.coerceAtLeast(0L)
        }
        return durationMs
    }

    override fun isPlaying(): Boolean {
        val mp = mediaPlayer ?: return false
        return try {
            mp.isPlaying
        } catch (_: Exception) {
            false
        }
    }

    override fun status(): Map<String, Any?> {
        val mp = mediaPlayer
        if (mp == null) {
            logW("getStatus: no player for textureId=$textureId")
            return mapOf("isReady" to false)
        }

        // 第三层兜底：万一 probe 和 layout 回调都拿不到尺寸，从当前视频轨补一次。
        // 不补的话 Dart 端 aspectRatio 会一直停在兜底值 1.0（画面被压成正方形）。
        if (videoWidth <= 0 || videoHeight <= 0) {
            try {
                val track = mp.currentVideoTrack
                if (track != null && track.width > 0 && track.height > 0) {
                    // 这里的 track.width 是**编码尺寸**，VLC 用它算 fmt 时会
                    // 向上对齐（见 [BUFFER_WIDTH_ALIGN]）；直接把未对齐的值写到
                    // setDefaultBufferSize 会让缓冲区比 fmt.i_width 窄几像素，
                    // 软件路径锁图恒失败 ⇒ 正是"黑屏"的手感。所以要对齐。
                    applyVideoSize(
                        alignBufferWidth(track.width),
                        track.height,
                        "status"
                    )
                }
            } catch (e: Exception) {
                logW("currentVideoTrack probe failed: ${e.message}")
            }
        }
        if (durationMs <= 0L) {
            durationMs = mp.length.coerceAtLeast(0L)
        }

        val position = clampPosition(mp.time)
        logI("getStatus: textureId=$textureId, isReady=$isReady, " +
            "isPlaying=${mp.isPlaying}, duration=${durationMs}ms, " +
            "position=$position, size=${videoWidth}x$videoHeight, " +
            "display=${displayWidth}x$displayHeight, " +
            "hasVout=$hasVout")
        // width/height 与 initialized 事件保持一致：都是**可视**尺寸。
        val rw = if (displayWidth > 0) displayWidth else videoWidth
        val rh = if (displayHeight > 0) displayHeight else videoHeight
        return mapOf(
            "isReady" to isReady,
            "isEnded" to isEnded,
            "isPlaying" to mp.isPlaying,
            "duration" to durationMs,
            "width" to rw,
            "height" to rh,
            // 缓冲区几何，仅用于诊断（Dart 侧不看）。
            "bufferWidth" to videoWidth,
            "bufferHeight" to videoHeight,
            "position" to position,
            // 之前这里是 `isReady`，等于把"VLC 报 Playing"当成"画面已经出来"，
            // 黑屏时诊断日志会给出完全相反的结论。这里改成"vout 是否真的建起来了"。
            "renderedFirstFrame" to hasVout,
            "hasVout" to hasVout,
            "videoDecoder" to "vlc-ffmpeg",
            "diag" to "vlc:${videoWidth}x$videoHeight," +
                "display=${displayWidth}x$displayHeight," +
                "duration=${durationMs}ms,vout=$hasVout"
        )
    }

    private fun resetPlayer() {
        isReady = false
        isEnded = false
        hasVout = false
        lastPositionMs = 0L
        durationMs = 0L
        videoWidth = 0
        videoHeight = 0
        displayWidth = 0
        displayHeight = 0
        // 新的一轮播放要从"几何未知"重新开始，否则后台探测的结果会被上一轮
        // 留下的 true 挡掉。
        layoutSizeKnown = false

        val mp = mediaPlayer
        val media = mediaRef
        val currentSurface = surface
        mediaPlayer = null
        mediaRef = null
        surface = null

        if (mp != null) {
            logD("resetPlayer: textureId=$textureId")
        }
        // 顺序按 libvlc 官方样例：stop() 先停 vout，再拆视图，最后 release()。
        // 反过来（先 detachViews 再 stop）会让 vout 在"视图已经拆掉、Surface
        // 已 release"的状态下继续跑，PoolAlloc/LockPicture 可能拿到已释放的
        // Surface，属于未定义行为。
        mp?.stop()
        // 显式摘掉事件监听：stop() 之后 libvlc 仍会补发 Stopped/TimeChanged，
        // 摘掉就少一批"入队即过期"的回调（已经入队的由 mediaPlayer !== mp 丢弃）。
        // 传 null 是 libvlc 的既定用法——VLCObject.setEventListener(null) 会走
        // nativeDetachEvents()（javap 反编译确认），不是"塞一个空实现"。
        try {
            mp?.setEventListener(null)
        } catch (_: Exception) {
        }
        try {
            mp?.vlcVout?.detachViews()
        } catch (_: Exception) {
        }
        mp?.release()
        try {
            media?.release()
        } catch (_: Exception) {
        }
        currentSurface?.release()
    }

    override fun release() {
        logI("release: textureId=$textureId")
        resetPlayer()
        try {
            textureEntry.release()
        } catch (e: Exception) {
            logW("textureEntry.release failed: ${e.message}")
        }
    }
}