package com.privi.app

import android.content.Context
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.view.Surface
import androidx.media3.common.MediaItem
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.common.VideoSize
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.source.ProgressiveMediaSource
import androidx.media3.datasource.DefaultDataSource
import io.flutter.view.TextureRegistry
import java.io.File

class VideoPlayerHandler(
    private val context: Context,
    private val textureEntry: TextureRegistry.SurfaceTextureEntry,
    private val eventSink: (String, Map<String, Any?>?) -> Unit
) {
    companion object {
        private const val TAG = "PriviVideoPlayer"

        /** Watchdog cadence; one second is fine enough to be useful in a log. */
        private const val WATCHDOG_PERIOD_MS = 1000L

        /** Upper bound on watchdog ticks (90s), so a paused player cannot keep it alive. */
        private const val WATCHDOG_MAX_TICKS = 90

        /** Seconds of "playing but nothing rendered" before each recovery step. */
        private const val STALL_SURFACE_TICKS = 4
        private const val STALL_SEEK_TICKS = 8
        private const val STALL_FINAL_TICKS = 12
    }

    private var player: ExoPlayer? = null
    private var surface: Surface? = null

    /** Per-playback decoder facts; a fresh instance is built for every player. */
    private var diagnostics: VideoPlaybackDiagnostics? = null

    /** Watchdog and player calls share the thread that created the player. */
    private val mainHandler = Handler(Looper.getMainLooper())
    private var stallTicks = 0
    private var watchdogTicks = 0

    /** Last size pushed into the SurfaceTexture, to avoid redundant resizes. */
    private var textureBufferWidth = 0
    private var textureBufferHeight = 0

    /**
     * Watches the one failure the previous logs could not see: the player
     * reports "playing" and advances the position, but no frame ever reaches
     * the surface. Users describe it as "the picture never moves, but dragging
     * the seek bar shows single frames".
     *
     * Ticks once per second while the player is ready and playing:
     * 4s -> re-attach the video surface (a wedged renderer often recovers),
     * 8s -> force one decode with a micro seek,
     * 12s -> stop and leave the evidence in the log.
     */
    private val frameWatchdog = object : Runnable {
        override fun run() {
            val current = player ?: return
            val diag = diagnostics ?: return
            if (diag.renderedFirstFrame) {
                stallTicks = 0
                return
            }
            watchdogTicks++
            if (current.playbackState == Player.STATE_READY && current.playWhenReady) {
                stallTicks++
            } else {
                // Buffering or paused: not the failure this watchdog looks for.
                stallTicks = 0
            }
            when (stallTicks) {
                STALL_SURFACE_TICKS -> {
                    logW("VDIAG[stall] no video frame after ${stallTicks}s while " +
                        "playing, textureId=$textureId")
                    diag.logSummary("stall-${stallTicks}s")
                    reattachSurface(current)
                }
                STALL_SEEK_TICKS -> {
                    logW("VDIAG[stall] still no video frame after ${stallTicks}s, " +
                        "textureId=$textureId")
                    diag.logSummary("stall-${stallTicks}s")
                    forceFrame(current)
                }
                STALL_FINAL_TICKS -> {
                    logE("VDIAG[stall] no rendered frame after ${stallTicks}s, " +
                        "giving up on recovery, textureId=$textureId")
                    diag.logSummary("stall-${stallTicks}s")
                    return
                }
            }
            if (watchdogTicks >= WATCHDOG_MAX_TICKS) return
            mainHandler.postDelayed(this, WATCHDOG_PERIOD_MS)
        }
    }

    val textureId: Long get() = textureEntry.id()

    /**
     * Mirrors one line to logcat and to the app's log file.
     *
     * The events the autoplay chain depends on (STATE_READY, STATE_ENDED,
     * player errors) are produced here and used to exist only in logcat.
     * Forwarding them over the video channel puts both sides of the playback
     * chain into the same file, so a phone-only failure can be read in one
     * place. `textureId` travels in the payload; the text already names it.
     */
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

    fun initialize(filePath: String) {
        logI("initialize: textureId=$textureId, path=$filePath")
        logSourceFile(filePath)
        resetPlayer()

        val exoPlayer = ExoPlayer.Builder(context).build()
        this.player = exoPlayer

        val diag = VideoPlaybackDiagnostics(::logI, ::logW)
        diagnostics = diag
        stallTicks = 0
        watchdogTicks = 0
        textureBufferWidth = 0
        textureBufferHeight = 0
        // Registered before the first frame can arrive: the analytics listener
        // carries the facts Player.Listener never sees - container brand,
        // codec string, which decoder was picked, colour format, dropped
        // frames - so a clip that decodes but never shows anything is still
        // readable from the log afterwards.
        exoPlayer.addAnalyticsListener(diag)
        exoPlayer.addListener(diag)
        exoPlayer.addListener(object : Player.Listener {
            override fun onVideoSizeChanged(videoSize: VideoSize) {
                applyTextureBufferSize(videoSize.width, videoSize.height)
            }
        })

        surface = Surface(textureEntry.surfaceTexture())
        exoPlayer.setVideoSurface(surface)
        logI("video surface attached to textureId=$textureId")

        val dataSourceFactory = DefaultDataSource.Factory(context)
        val mediaUri = Uri.parse("file://$filePath")
        val mediaSource = ProgressiveMediaSource.Factory(dataSourceFactory)
            .createMediaSource(MediaItem.fromUri(mediaUri))

        exoPlayer.setMediaSource(mediaSource)
        logI("media source set for textureId=$textureId")

        // Listener first: a fast/cached local file can reach STATE_READY almost
        // immediately, and a missed `initialized` event would leave the Dart
        // side parked on its loading spinner.
        exoPlayer.addListener(object : Player.Listener {
            override fun onPlaybackStateChanged(state: Int) {
                when (state) {
                    Player.STATE_READY -> {
                        val dur = exoPlayer.duration
                        val duration = if (dur < 0) 0L else dur
                        val vs = exoPlayer.videoSize
                        logI("STATE_READY: textureId=$textureId, " +
                            "duration=${duration}ms, size=${vs.width}x${vs.height}, " +
                            "isPlaying=${exoPlayer.isPlaying}")
                        // The one-line summary of the whole decode chain; a
                        // black-but-playing clip can be read off this line.
                        diag.logSummary("ready")
                        eventSink("initialized", mapOf(
                            "textureId" to textureId,
                            "duration" to duration,
                            "width" to vs.width,
                            "height" to vs.height
                        ))
                    }
                    Player.STATE_ENDED -> {
                        logI("STATE_ENDED: textureId=$textureId, " +
                            "position=${exoPlayer.currentPosition}")
                        eventSink("completed", mapOf("textureId" to textureId))
                    }
                    Player.STATE_BUFFERING -> {
                        logD("STATE_BUFFERING: textureId=$textureId, " +
                            "position=${exoPlayer.currentPosition}")
                    }
                    Player.STATE_IDLE -> {
                        logD("STATE_IDLE: textureId=$textureId")
                    }
                    else -> {
                        logD("state changed: textureId=$textureId, state=$state")
                    }
                }
            }

            override fun onPlayerError(error: PlaybackException) {
                val diag = diagnostics
                logE(
                    "onPlayerError: textureId=$textureId, " +
                        (diag?.describeError(error)
                            ?: "code=${error.errorCode}, " +
                            "msg=${error.localizedMessage}"),
                    error
                )
                // The full picture, so one line explains an unsupported codec,
                // an HDR clip or a decoder that was never created.
                diag?.logSummary("error")
                eventSink("error", mapOf(
                    "textureId" to textureId,
                    "message" to (error.localizedMessage ?: "Playback error"),
                    "code" to error.errorCode,
                    "diag" to diag?.summary()
                ))
            }

            override fun onIsPlayingChanged(isPlaying: Boolean) {
                logI("onIsPlayingChanged: textureId=$textureId, " +
                    "isPlaying=$isPlaying, position=${exoPlayer.currentPosition}")
                eventSink("playingChanged", mapOf(
                    "textureId" to textureId,
                    "isPlaying" to isPlaying))
            }
        })

        exoPlayer.prepare()
        logI("prepare() called for textureId=$textureId")
        // Started here, not on play(): the interesting case is a player that
        // becomes ready and playing but never renders, and that can happen
        // before Dart gets around to calling play().
        mainHandler.removeCallbacks(frameWatchdog)
        mainHandler.postDelayed(frameWatchdog, WATCHDOG_PERIOD_MS)
    }

    /**
     * Logs the source file straight from the process that opens it.
     *
     * The Dart side reports the same file, but a path that resolves differently
     * (vault re-mount, renamed temp file) or a file that shrank between the two
     * reads is exactly the kind of thing that makes a clip "not play".
     */
    private fun logSourceFile(filePath: String) {
        try {
            val file = File(filePath)
            logI("source file: exists=${file.exists()}, size=${file.length()}B, " +
                "readable=${file.canRead()}, modified=${file.lastModified()}")
        } catch (e: Exception) {
            logW("source file probe failed for $filePath: ${e.message}")
        }
    }

    /**
     * Keeps the SurfaceTexture's default buffer size in step with the video.
     *
     * MediaCodec normally sets the buffer geometry itself when it connects to
     * the surface, but that is not guaranteed for every decoder on every ROM.
     * When it does not happen the producer keeps the SurfaceTexture default
     * (1x1) and there is nothing usable to display even though the decoder is
     * running. The call only runs when the size actually changed.
     */
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

    /**
     * Recovery step 1 for "playing but nothing on screen": detach and re-attach
     * the surface, which makes the video renderer build a fresh output surface.
     * Cheap, and it cannot lose the position.
     */
    private fun reattachSurface(current: ExoPlayer) {
        val currentSurface = surface ?: return
        try {
            logW("recovery: re-attaching the video surface, textureId=$textureId")
            current.setVideoSurface(null)
            current.setVideoSurface(currentSurface)
        } catch (e: Exception) {
            logW("recovery: surface re-attach failed for " +
                "textureId=$textureId: ${e.message}")
        }
    }

    /**
     * Recovery step 2: nudge the pipeline with a tiny seek. A clip whose
     * timestamps confuse the renderer (or a decoder that stalls after the first
     * buffer) renders a frame after a flush, which is why users report that
     * "dragging the bar shows pictures".
     */
    private fun forceFrame(current: ExoPlayer) {
        try {
            val duration = current.duration
            val position = current.currentPosition
            if (duration > 0 && position + 1500 >= duration) {
                logW("recovery: skipping the micro seek, stream is almost over " +
                    "(position=${position}ms, duration=${duration}ms)")
                return
            }
            val target = position + 100
            logW("recovery: forcing a decode with a micro seek to " +
                "${target}ms, textureId=$textureId")
            current.seekTo(target)
        } catch (e: Exception) {
            logW("recovery: micro seek failed for textureId=$textureId: ${e.message}")
        }
    }

    fun play() {
        val current = player
        if (current == null) {
            // A released/half-built player silently ignoring play() is one way
            // an autoplay chain dies, so it must not pass unnoticed.
            logW("play ignored: no player for textureId=$textureId")
            return
        }
        current.play()
        logI("play: textureId=$textureId, state=${current.playbackState}, " +
            "position=${current.currentPosition}")
    }

    fun pause() {
        val current = player
        if (current == null) {
            logW("pause ignored: no player for textureId=$textureId")
            return
        }
        current.pause()
        logI("pause: textureId=$textureId, state=${current.playbackState}, " +
            "position=${current.currentPosition}")
    }

    fun seekTo(positionMs: Long) {
        val current = player
        if (current == null) {
            logW("seekTo ignored: no player for textureId=$textureId")
            return
        }
        current.seekTo(positionMs)
        logD("seekTo: textureId=$textureId, positionMs=$positionMs")
    }

    fun setVolume(volume: Double) {
        val current = player
        if (current == null) {
            logW("setVolume ignored: no player for textureId=$textureId")
            return
        }
        current.volume = volume.toFloat().coerceIn(0f, 1f)
        logD("setVolume: textureId=$textureId, volume=${current.volume}")
    }

    fun setPlaybackSpeed(speed: Double) {
        val current = player
        if (current == null) {
            logW("setPlaybackSpeed ignored: no player for textureId=$textureId")
            return
        }
        current.setPlaybackSpeed(speed.toFloat())
        logD("setPlaybackSpeed: textureId=$textureId, speed=$speed")
    }

    fun getPosition(): Long {
        return player?.currentPosition ?: 0L
    }

    fun getDuration(): Long {
        return player?.duration?.let { if (it < 0) 0L else it } ?: 0L
    }

    fun isPlaying(): Boolean {
        return player?.isPlaying == true
    }

    /**
     * Authoritative state snapshot. Dart pulls this as a safety net when the
     * one-shot `initialized` event was missed, so the UI cannot stay on a
     * spinner while the player is actually ready.
     */
    fun status(): Map<String, Any?> {
        val current = player
        if (current == null) {
            logW("getStatus: no player for textureId=$textureId")
            return mapOf("isReady" to false)
        }
        val state = current.playbackState
        val duration = current.duration.let { if (it < 0) 0L else it }
        val videoSize = current.videoSize
        logI("getStatus: textureId=$textureId, state=$state, " +
            "isPlaying=${current.isPlaying}, duration=${duration}ms, " +
            "position=${current.currentPosition}")
        val diag = diagnostics
        // The Dart side pulls this exactly when something looks wrong, so the
        // full decode chain belongs in the log next to it.
        diag?.logSummary("status-pull")
        return mapOf(
            "isReady" to (state == Player.STATE_READY || state == Player.STATE_ENDED),
            "isEnded" to (state == Player.STATE_ENDED),
            "isPlaying" to current.isPlaying,
            "duration" to duration,
            "width" to videoSize.width,
            "height" to videoSize.height,
            "position" to current.currentPosition,
            "renderedFirstFrame" to (diag?.renderedFirstFrame ?: false),
            "videoDecoder" to diag?.videoDecoderName,
            "diag" to diag?.summary()
        )
    }

    /**
     * Tears down the ExoPlayer and its Surface while keeping the texture entry
     * alive, so initialize() can restart playback on the same SurfaceTexture.
     */
    private fun resetPlayer() {
        mainHandler.removeCallbacks(frameWatchdog)
        stallTicks = 0
        watchdogTicks = 0
        diagnostics = null
        val current = player
        val currentSurface = surface
        player = null
        surface = null
        if (current != null) {
            logD("resetPlayer: textureId=$textureId, " +
                "state=${current.playbackState}, " +
                "position=${current.currentPosition}")
        }
        current?.stop()
        current?.clearVideoSurface()
        current?.release()
        currentSurface?.release()
    }

    /**
     * Full disposal: player, surface and the GL texture entry.
     */
    fun release() {
        logI("release: textureId=$textureId")
        resetPlayer()
        try {
            textureEntry.release()
        } catch (e: Exception) {
            logW("textureEntry.release failed: ${e.message}")
        }
    }
}