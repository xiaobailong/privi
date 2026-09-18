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

    fun initialize(filePath: String) {
        Log.i(TAG, "initialize: textureId=$textureId, path=$filePath")
        release()

        val exoPlayer = ExoPlayer.Builder(context).build()
        this.player = exoPlayer

        surface = Surface(textureEntry.surfaceTexture())
        exoPlayer.setVideoSurface(surface)

        val dataSourceFactory = DefaultDataSource.Factory(context)
        val mediaUri = Uri.parse("file://$filePath")
        val mediaSource = ProgressiveMediaSource.Factory(dataSourceFactory)
            .createMediaSource(MediaItem.fromUri(mediaUri))

        exoPlayer.setMediaSource(mediaSource)
        exoPlayer.prepare()
        Log.i(TAG, "prepare() called for textureId=$textureId")

        exoPlayer.addListener(object : Player.Listener {
            override fun onPlaybackStateChanged(state: Int) {
                when (state) {
                    Player.STATE_READY -> {
                        val dur = exoPlayer.duration
                        val duration = if (dur < 0) 0L else dur
                        val vs = exoPlayer.videoSize
                        Log.i(TAG, "STATE_READY: textureId=$textureId, " +
                            "duration=${duration}ms, size=${vs.width}x${vs.height}")
                        eventSink("initialized", mapOf(
                            "duration" to duration,
                            "width" to vs.width,
                            "height" to vs.height
                        ))
                    }
                    Player.STATE_ENDED -> {
                        Log.i(TAG, "STATE_ENDED: textureId=$textureId")
                        eventSink("completed", null)
                    }
                    Player.STATE_BUFFERING -> {
                        Log.d(TAG, "STATE_BUFFERING: textureId=$textureId")
                    }
                    Player.STATE_IDLE -> {
                        Log.d(TAG, "STATE_IDLE: textureId=$textureId")
                    }
                }
            }

            override fun onPlayerError(error: PlaybackException) {
                Log.e(TAG, "onPlayerError: textureId=$textureId, " +
                    "code=${error.errorCode}, msg=${error.localizedMessage}", error)
                eventSink("error", mapOf(
                    "message" to (error.localizedMessage ?: "Playback error"),
                    "code" to error.errorCode
                ))
            }

            override fun onIsPlayingChanged(isPlaying: Boolean) {
                Log.d(TAG, "onIsPlayingChanged: textureId=$textureId, isPlaying=$isPlaying")
                eventSink("playingChanged", mapOf("isPlaying" to isPlaying))
            }
        })
    }

    fun play() {
        Log.d(TAG, "play: textureId=$textureId")
        player?.play()
    }

    fun pause() {
        Log.d(TAG, "pause: textureId=$textureId")
        player?.pause()
    }

    fun seekTo(positionMs: Long) {
        Log.d(TAG, "seekTo: textureId=$textureId, positionMs=$positionMs")
        player?.seekTo(positionMs)
    }

    fun setVolume(volume: Double) {
        player?.volume = volume.toFloat().coerceIn(0f, 1f)
    }

    fun setPlaybackSpeed(speed: Double) {
        Log.d(TAG, "setPlaybackSpeed: textureId=$textureId, speed=$speed")
        player?.setPlaybackSpeed(speed.toFloat())
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

    fun release() {
        Log.i(TAG, "release: textureId=$textureId")
        player?.stop()
        player?.clearVideoSurface()
        player?.release()
        surface?.release()
        player = null
        surface = null
    }
}