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
import org.videolan.libvlc.interfaces.IVLCVout
import java.io.File

class VlcPlayerHandler(
    private val context: Context,
    private val textureEntry: TextureRegistry.SurfaceTextureEntry,
    private val eventSink: (String, Map<String, Any?>?) -> Unit
) : PlayerHandler {
    companion object {
        private const val TAG = "PriviVlcPlayer"

        @Volatile
        private var sharedLibVlc: LibVLC? = null

        @Synchronized
        fun getLibVlc(context: Context): LibVLC {
            return sharedLibVlc ?: LibVLC(context, arrayListOf(
                "--no-audio-time-stretch",
                "--verbose=0",
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
    private var textureBufferWidth = 0
    private var textureBufferHeight = 0

    private var durationMs = 0L
    private var videoWidth = 0
    private var videoHeight = 0
    private var isReady = false
    private var isEnded = false
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
            mp.media = media
            mediaRef = media

            surface = Surface(textureEntry.surfaceTexture())
            val vout: IVLCVout = mp.vlcVout
            vout.setVideoSurface(surface, null)
            vout.attachViews()
            logI("video surface attached to textureId=$textureId")

            mp.setEventListener { event ->
                mainHandler.post { onMediaPlayerEvent(event.type, mp) }
            }

            mp.play()
            logI("play() called for textureId=$textureId")
        } catch (e: Exception) {
            logE("initialize failed, cleaning up: ${e.message}", e)
            resetPlayer()
            throw e
        }
    }

    private fun onMediaPlayerEvent(eventType: Int, mp: MediaPlayer) {
        when (eventType) {
            MediaPlayer.Event.Playing -> {
                if (!isReady) {
                    isReady = true
                    durationMs = mp.length.coerceAtLeast(0L)
                    videoWidth = 0
                    videoHeight = 0
                    try {
                        val tracks = mp.videoTracks
                        if (tracks != null && tracks.isNotEmpty()) {
                            val vt = tracks[0] as? MediaPlayer.VideoTrack
                            if (vt != null) {
                                videoWidth = vt.width
                                videoHeight = vt.height
                            }
                        }
                    } catch (_: Exception) {
                        logW("Could not read video track dimensions")
                    }
                    if (videoWidth > 0 && videoHeight > 0) {
                        applyTextureBufferSize(videoWidth, videoHeight)
                    }
                    logI("STATE_READY: textureId=$textureId, " +
                        "duration=${durationMs}ms, size=${videoWidth}x${videoHeight}")
                    eventSink("initialized", mapOf(
                        "textureId" to textureId,
                        "duration" to durationMs,
                        "width" to videoWidth,
                        "height" to videoHeight
                    ))
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
                val newPos = mp.time.coerceIn(0L, durationMs)
                if (newPos != lastPositionMs) {
                    lastPositionMs = newPos
                }
            }
            MediaPlayer.Event.Vout -> {
                val count = mp.vlcVout.areViewsAttached()
                logD("Vout event: viewsAttached=$count, textureId=$textureId")
            }
        }
    }

    private fun logSourceFile(filePath: String) {
        try {
            val file = File(filePath)
            logI("source file: exists=${file.exists()}, size=${file.length()}B, " +
                "readable=${file.canRead()}, modified=${file.lastModified()}")
        } catch (e: Exception) {
            logW("source file probe failed for $filePath: ${e.message}")
        }
    }

    private fun applyTextureBufferSize(width: Int, height: Int) {
        if (width <= 0 || height <= 0) return
        if (width == textureBufferWidth && height == textureBufferHeight) return
        textureBufferWidth = width
        textureBufferHeight = height
        try {
            textureEntry.surfaceTexture().setDefaultBufferSize(width, height)
            logI("texture buffer size set to ${width}x$height, textureId=$textureId")
        } catch (e: Exception) {
            logW("setDefaultBufferSize(${width}x$height) failed for " +
                "textureId=$textureId: ${e.message}")
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
        mp.time = positionMs.coerceIn(0L, durationMs)
        lastPositionMs = mp.time
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
        return mp.time.coerceIn(0L, durationMs)
    }

    override fun getDuration(): Long = durationMs

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
        logI("getStatus: textureId=$textureId, isReady=$isReady, " +
            "isPlaying=${mp.isPlaying}, duration=${durationMs}ms, " +
            "position=${mp.time}")
        return mapOf(
            "isReady" to isReady,
            "isEnded" to isEnded,
            "isPlaying" to mp.isPlaying,
            "duration" to durationMs,
            "width" to videoWidth,
            "height" to videoHeight,
            "position" to mp.time.coerceIn(0L, durationMs),
            "renderedFirstFrame" to isReady,
            "videoDecoder" to "vlc-ffmpeg",
            "diag" to "vlc:${videoWidth}x${videoHeight},duration=${durationMs}ms"
        )
    }

    private fun resetPlayer() {
        isReady = false
        isEnded = false
        lastPositionMs = 0L
        durationMs = 0L
        videoWidth = 0
        videoHeight = 0
        textureBufferWidth = 0
        textureBufferHeight = 0

        val mp = mediaPlayer
        val media = mediaRef
        val currentSurface = surface
        mediaPlayer = null
        mediaRef = null
        surface = null

        if (mp != null) {
            logD("resetPlayer: textureId=$textureId")
        }
        try {
            mp?.vlcVout?.detachViews()
        } catch (_: Exception) {
        }
        mp?.stop()
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