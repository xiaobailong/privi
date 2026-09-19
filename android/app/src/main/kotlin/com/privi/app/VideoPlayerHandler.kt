package com.privi.app

import android.content.Context
import android.net.Uri
import android.util.Log
import android.view.Surface
import androidx.media3.common.MediaItem
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.source.ProgressiveMediaSource
import androidx.media3.datasource.DefaultDataSource
import io.flutter.view.TextureRegistry

class VideoPlayerHandler(
    private val context: Context,
    private val textureEntry: TextureRegistry.SurfaceTextureEntry,
    private val eventSink: (String, Map<String, Any?>?) -> Unit
) {
    companion object {
        private const val TAG = "PriviVideoPlayer"
    }

    private var player: ExoPlayer? = null
    private var surface: Surface? = null

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
        resetPlayer()

        val exoPlayer = ExoPlayer.Builder(context).build()
        this.player = exoPlayer

        surface = Surface(textureEntry.surfaceTexture())
        exoPlayer.setVideoSurface(surface)

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
                logE(
                    "onPlayerError: textureId=$textureId, " +
                        "code=${error.errorCode}, msg=${error.localizedMessage}",
                    error
                )
                eventSink("error", mapOf(
                    "textureId" to textureId,
                    "message" to (error.localizedMessage ?: "Playback error"),
                    "code" to error.errorCode
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
        return mapOf(
            "isReady" to (state == Player.STATE_READY || state == Player.STATE_ENDED),
            "isEnded" to (state == Player.STATE_ENDED),
            "isPlaying" to current.isPlaying,
            "duration" to duration,
            "width" to videoSize.width,
            "height" to videoSize.height,
            "position" to current.currentPosition
        )
    }

    /**
     * Tears down the ExoPlayer and its Surface while keeping the texture entry
     * alive, so initialize() can restart playback on the same SurfaceTexture.
     */
    private fun resetPlayer() {
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