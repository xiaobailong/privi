package com.privi.app

import android.content.Intent
import android.net.Uri
import android.media.AudioManager
import android.os.Build
import android.os.Environment
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.util.Log
import android.view.WindowManager
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.view.TextureRegistry
import java.util.concurrent.Executors

/**
 * Registers Flutter channels and owns their executor lifecycle.
 *
 * File, MediaStore, metadata, and thumbnail behavior lives in focused handlers.
 */
class MainActivity : FlutterFragmentActivity() {
    private val ioExecutor = Executors.newFixedThreadPool(3)
    private val mainHandler = Handler(Looper.getMainLooper())
    private var externalPlayer: ExternalPlayerHandler? = null
    private val videoPlayers = mutableMapOf<Long, PlayerHandler>()
    private var videoChannel: MethodChannel? = null

    private fun <T> runIo(result: MethodChannel.Result, block: () -> T) {
        ioExecutor.execute {
            try {
                val value = block()
                mainHandler.post { result.success(value) }
            } catch (e: Exception) {
                mainHandler.post { result.error("io_error", e.message, null) }
            }
        }
    }

    /**
     * Forwards one MainActivity line to logcat and to the Dart log file.
     *
     * The video channel's own bookkeeping (create/dispose/errors) used to be
     * visible only in logcat, which made a phone-only playback failure hard to
     * read from the app log. `invokeMethod` must run on the main thread, which
     * is where the channel handlers and lifecycle callbacks already run.
     */
    private fun logToDart(
        channel: MethodChannel?,
        message: String,
        level: String = "i",
    ) {
        when (level) {
            "e" -> Log.e("PriviMain", message)
            "w" -> Log.w("PriviMain", message)
            "d" -> Log.d("PriviMain", message)
            else -> Log.i("PriviMain", message)
        }
        val target = channel ?: return
        try {
            target.invokeMethod("log", mapOf("level" to level, "text" to message))
        } catch (e: Exception) {
            Log.w("PriviMain", "log forward failed: ${e.message}")
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        val mediaStore = MediaStoreIndexHandler(this, contentResolver)
        val vaultFiles = VaultFileHandler(this, contentResolver, mediaStore)
        val metadata = MediaMetadataHandler(contentResolver, mediaStore)
        val thumbnails = ThumbnailHandler()
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        externalPlayer = ExternalPlayerHandler(this, messenger, vaultFiles)

        MethodChannel(messenger, "com.privi.app/mediastore")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "removeOriginal" -> {
                        val uri = call.argument<String>("uri")
                        result.success(!uri.isNullOrEmpty() && mediaStore.removeOriginal(uri))
                    }
                    "purgeMediaStorePath" -> {
                        val path = call.argument<String>("path")
                        result.success(
                            !path.isNullOrEmpty() && mediaStore.purgeMediaStoreByPath(path) > 0,
                        )
                    }
                    "scanMediaPath" -> {
                        val path = call.argument<String>("path")
                        if (path.isNullOrEmpty()) {
                            result.success(false)
                        } else {
                            result.success(
                                mediaStore.scanMediaPath(
                                    path,
                                    call.argument("mimeType"),
                                    call.argument<Number>("dateTakenSec")?.toLong(),
                                    call.argument<Number>("dateAddedSec")?.toLong(),
                                ),
                            )
                        }
                    }
                    "resolveMediaPath" -> {
                        val id = call.argument<String>("id")?.toLongOrNull()
                        val isVideo = call.argument<Boolean>("isVideo") ?: false
                        result.success(
                            if (id == null) null else mediaStore.resolveMediaPathById(id, isVideo),
                        )
                    }
                    "resolveCaptureDate" -> runIo(result) {
                        metadata.resolveCaptureDateSec(
                            call.argument("path"),
                            call.argument<String>("mediaId")?.toLongOrNull(),
                            call.argument<Boolean>("isVideo") ?: false,
                        )
                    }
                    "isExternalStorageManager" -> result.success(isAllFilesAccess())
                    "openManageAllFilesSettings" -> {
                        openAllFilesSettings()
                        result.success(null)
                    }
                    "renameMedia" -> {
                        val path = call.argument<String>("path")
                        val newPath = call.argument<String>("newPath")
                        if (path.isNullOrEmpty() || newPath.isNullOrEmpty()) {
                            result.success(mapOf("ok" to false, "error" to "bad_args"))
                        } else {
                            result.success(
                                vaultFiles.renameMedia(
                                    path,
                                    newPath,
                                    call.argument<Boolean>("isVideo") ?: false,
                                ),
                            )
                        }
                    }
                    "hideToVault" -> {
                        val newPath = call.argument<String>("newPath")
                        if (newPath.isNullOrEmpty()) {
                            result.success(mapOf("ok" to false, "error" to "bad_args"))
                        } else {
                            runIo(result) {
                                vaultFiles.hideToVault(
                                    call.argument("path"),
                                    call.argument<String>("mediaId")?.toLongOrNull(),
                                    newPath,
                                    call.argument<Boolean>("isVideo") ?: false,
                                )
                            }
                        }
                    }
                    "hideToVaultBatch" -> {
                        val items = call.argument<List<*>>("items")
                        if (items.isNullOrEmpty()) {
                            result.success(emptyList<Map<String, Any?>>())
                        } else {
                            runIo(result) { vaultFiles.hideToVaultBatch(items) }
                        }
                    }
                    "unhideFromVault" -> {
                        val path = call.argument<String>("path")
                        val newPath = call.argument<String>("newPath")
                        if (path.isNullOrEmpty() || newPath.isNullOrEmpty()) {
                            result.success(mapOf("ok" to false, "error" to "bad_args"))
                        } else {
                            runIo(result) {
                                vaultFiles.unhideFromVault(
                                    path,
                                    newPath,
                                    call.argument("mimeType"),
                                    call.argument<Number>("dateTakenSec")?.toLong(),
                                    call.argument<Number>("dateAddedSec")?.toLong(),
                                )
                            }
                        }
                    }
                    "unhideFromVaultBatch" -> {
                        val items = call.argument<List<*>>("items")
                        if (items.isNullOrEmpty()) {
                            result.success(emptyList<Map<String, Any?>>())
                        } else {
                            runIo(result) { vaultFiles.unhideFromVaultBatch(items) }
                        }
                    }
                    "videoThumbnail" -> {
                        val path = call.argument<String>("path")
                        val destPath = call.argument<String>("destPath")
                        if (path.isNullOrEmpty() || destPath.isNullOrEmpty()) {
                            result.success(false)
                        } else {
                            runIo(result) {
                                thumbnails.extractVideoThumbnail(
                                    path,
                                    destPath,
                                    call.argument<Int>("maxSize") ?: 256,
                                )
                            }
                        }
                    }
                    "videoFrameAtTime" -> {
                        val path = call.argument<String>("path")
                        val timeUs = call.argument<Number>("timeUs")?.toLong()
                        if (path.isNullOrEmpty() || timeUs == null) {
                            result.success(null)
                        } else {
                            runIo(result) {
                                thumbnails.extractVideoFrame(
                                    path,
                                    timeUs,
                                    call.argument<Int>("maxSize") ?: 220,
                                )
                            }
                        }
                    }
                    else -> result.notImplemented()
                }
            }

        MethodChannel(messenger, "com.privi.app/window")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "setFlagSecure" -> {
                        val enabled = call.argument<Boolean>("enabled") ?: false
                        runOnUiThread {
                            if (enabled) {
                                window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
                            } else {
                                window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
                            }
                        }
                        result.success(null)
                    }
                    "setKeepScreenOn" -> {
                        val enabled = call.argument<Boolean>("enabled") ?: false
                        runOnUiThread {
                            if (enabled) {
                                window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                            } else {
                                window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                            }
                        }
                        result.success(null)
                    }
                    "getBrightness" -> {
                        val current = window.attributes.screenBrightness
                        result.success(
                            if (current < 0f) systemBrightness() else current.coerceIn(0f, 1f),
                        )
                    }
                    "setBrightness" -> {
                        val value = (call.argument<Number>("value")?.toFloat() ?: 0.5f)
                            .coerceIn(0f, 1f)
                        runOnUiThread { setWindowBrightness(value) }
                        result.success(null)
                    }
                    "resetBrightness" -> {
                        runOnUiThread {
                            setWindowBrightness(WindowManager.LayoutParams.BRIGHTNESS_OVERRIDE_NONE)
                        }
                        result.success(null)
                    }
                    "getVolume" -> result.success(mediaVolume())
                    "setVolume" -> {
                        val value = (call.argument<Number>("value")?.toFloat() ?: 0.5f)
                            .coerceIn(0f, 1f)
                        setMediaVolume(value)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }

        val textures = flutterEngine.renderer ?: return
        val videoChannel = MethodChannel(messenger, "com.privi.app/video_player")
        this.videoChannel = videoChannel
        logToDart(videoChannel, "Registering video player channel")
        videoChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "create" -> {
                    val filePath = call.argument<String>("filePath")
                    if (filePath.isNullOrEmpty()) {
                        logToDart(
                            videoChannel,
                            "video create: filePath is null or empty",
                            "e",
                        )
                        result.error("bad_args", "filePath is required", null)
                        return@setMethodCallHandler
                    }
                    val engine = call.argument<String>("playerEngine") ?: "exoPlayer"
                    var textureEntry: TextureRegistry.SurfaceTextureEntry? = null
                    var handler: PlayerHandler? = null
                    try {
                        logToDart(videoChannel, "Creating video player: $filePath, engine=$engine")
                        textureEntry = textures.createSurfaceTexture()
                        handler = if (engine == "vlc") {
                            VlcPlayerHandler(
                                this,
                                textureEntry,
                                // 只给 VlcPlayerHandler 用来把 media.parse() 挪出
                                // 主线程；onDestroy 里 ioExecutor.shutdown() 收尾。
                                ioExecutor,
                            ) { event, data ->
                                mainHandler.post {
                                    try {
                                        videoChannel.invokeMethod(event, data)
                                    } catch (e: Exception) {
                                        Log.w("PriviMain", "event $event dropped: ${e.message}")
                                    }
                                }
                            }
                        } else {
                            VideoPlayerHandler(
                                this,
                                textureEntry,
                            ) { event, data ->
                                mainHandler.post {
                                    try {
                                        videoChannel.invokeMethod(event, data)
                                    } catch (e: Exception) {
                                        Log.w("PriviMain", "event $event dropped: ${e.message}")
                                    }
                                }
                            }
                        }
                        handler.initialize(filePath)
                        videoPlayers[textureEntry.id()] = handler
                        logToDart(
                            videoChannel,
                            "Video player created: textureId=${textureEntry.id()}, " +
                                "engine=$engine",
                        )
                        result.success(textureEntry.id())
                    } catch (e: Exception) {
                        if (handler != null) {
                            try {
                                handler.release()
                            } catch (re: Exception) {
                                Log.w("PriviMain", "handler.release failed: ${re.message}")
                            }
                        } else {
                            try {
                                textureEntry?.release()
                            } catch (re: Exception) {
                                Log.w("PriviMain", "textureEntry.release failed: ${re.message}")
                            }
                        }
                        logToDart(
                            videoChannel,
                            "Video player create error: ${e.message}",
                            "e",
                        )
                        result.error("create_error", e.message, null)
                    }
                }
                "dispose" -> {
                    val textureId = call.argument<Number>("textureId")?.toLong()
                    if (textureId == null) {
                        result.error("bad_args", "textureId is required", null)
                        return@setMethodCallHandler
                    }
                    logToDart(videoChannel, "Disposing video player: textureId=$textureId")
                    videoPlayers.remove(textureId)?.release()
                    result.success(null)
                }
                "play" -> {
                    val textureId = call.argument<Number>("textureId")?.toLong()
                    videoPlayers[textureId]?.play()
                    result.success(null)
                }
                "pause" -> {
                    val textureId = call.argument<Number>("textureId")?.toLong()
                    videoPlayers[textureId]?.pause()
                    result.success(null)
                }
                "seekTo" -> {
                    val textureId = call.argument<Number>("textureId")?.toLong()
                    val positionMs = call.argument<Number>("positionMs")?.toLong()
                    if (positionMs != null) {
                        videoPlayers[textureId]?.seekTo(positionMs)
                    }
                    result.success(null)
                }
                "setVolume" -> {
                    val textureId = call.argument<Number>("textureId")?.toLong()
                    val volume = call.argument<Double>("volume") ?: 1.0
                    videoPlayers[textureId]?.setVolume(volume)
                    result.success(null)
                }
                "setPlaybackSpeed" -> {
                    val textureId = call.argument<Number>("textureId")?.toLong()
                    val speed = call.argument<Double>("speed") ?: 1.0
                    videoPlayers[textureId]?.setPlaybackSpeed(speed)
                    result.success(null)
                }
                "getPosition" -> {
                    val textureId = call.argument<Number>("textureId")?.toLong()
                    val pos = videoPlayers[textureId]?.getPosition() ?: 0L
                    result.success(pos)
                }
                "getDuration" -> {
                    val textureId = call.argument<Number>("textureId")?.toLong()
                    val dur = videoPlayers[textureId]?.getDuration() ?: 0L
                    result.success(dur)
                }
                "isPlaying" -> {
                    val textureId = call.argument<Number>("textureId")?.toLong()
                    result.success(videoPlayers[textureId]?.isPlaying() ?: false)
                }
                "getStatus" -> {
                    val textureId = call.argument<Number>("textureId")?.toLong()
                    result.success(videoPlayers[textureId]?.status())
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onDestroy() {
        logToDart(
            videoChannel,
            "onDestroy: releasing ${videoPlayers.size} video players",
        )
        externalPlayer?.dispose()
        externalPlayer = null
        videoPlayers.values.forEach { it.release() }
        videoPlayers.clear()
        VlcPlayerHandler.releaseLibVlc()
        videoChannel = null
        ioExecutor.shutdown()
        super.onDestroy()
    }

    private fun setWindowBrightness(value: Float) {
        val params = window.attributes
        params.screenBrightness = value
        window.attributes = params
    }

    private fun systemBrightness(): Float {
        return try {
            Settings.System.getInt(contentResolver, Settings.System.SCREEN_BRIGHTNESS) / 255f
        } catch (_: Exception) {
            0.5f
        }
    }

    private fun audioManager(): AudioManager? {
        return getSystemService(AUDIO_SERVICE) as? AudioManager
    }

    private fun mediaVolume(): Float {
        val audio = audioManager() ?: return 0.5f
        val max = audio.getStreamMaxVolume(AudioManager.STREAM_MUSIC).coerceAtLeast(1)
        return audio.getStreamVolume(AudioManager.STREAM_MUSIC).toFloat() / max
    }

    private fun setMediaVolume(value: Float) {
        val audio = audioManager() ?: return
        val max = audio.getStreamMaxVolume(AudioManager.STREAM_MUSIC).coerceAtLeast(1)
        val index = (value * max).toInt().coerceIn(0, max)
        audio.setStreamVolume(AudioManager.STREAM_MUSIC, index, 0)
    }

    private fun isAllFilesAccess(): Boolean {
        return Build.VERSION.SDK_INT < Build.VERSION_CODES.R ||
            Environment.isExternalStorageManager()
    }

    private fun openAllFilesSettings() {
        try {
            val action = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION
            } else {
                Settings.ACTION_APPLICATION_DETAILS_SETTINGS
            }
            startActivity(Intent(action, Uri.parse("package:$packageName")))
        } catch (_: Exception) {
            startActivity(Intent(Settings.ACTION_MANAGE_ALL_FILES_ACCESS_PERMISSION))
        }
    }
}