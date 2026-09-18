package com.privi.app

import android.content.Context
import android.net.Uri
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
    private var player: ExoPlayer? = null
    private var surface: Surface? = null

    val textureId: Long get() = textureEntry.id()

    fun initialize(filePath: String) {
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

        exoPlayer.addListener(object : Player.Listener {
            override fun onPlaybackStateChanged(state: Int) {
                when (state) {
                    Player.STATE_READY -> {
                        val dur = exoPlayer.duration
                        val duration = if (dur < 0) 0L else dur
                        val vs = exoPlayer.videoSize
                        eventSink("initialized", mapOf(
                            "duration" to duration,
                            "width" to vs.width,
                            "height" to vs.height
                        ))
                    }
                    Player.STATE_ENDED -> {
                        eventSink("completed", null)
                    }
                    Player.STATE_BUFFERING -> {}
                    Player.STATE_IDLE -> {}
                }
            }

            override fun onPlayerError(error: PlaybackException) {
                eventSink("error", mapOf(
                    "message" to (error.localizedMessage ?: "Playback error"),
                    "code" to error.errorCode
                ))
            }

            override fun onIsPlayingChanged(isPlaying: Boolean) {
                eventSink("playingChanged", mapOf("isPlaying" to isPlaying))
            }
        })
    }

    fun play() {
        player?.play()
    }

    fun pause() {
        player?.pause()
    }

    fun seekTo(positionMs: Long) {
        player?.seekTo(positionMs)
    }

    fun setVolume(volume: Double) {
        player?.volume = volume.toFloat().coerceIn(0f, 1f)
    }

    fun setPlaybackSpeed(speed: Double) {
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
        player?.stop()
        player?.clearVideoSurface()
        player?.release()
        surface?.release()
        player = null
        surface = null
    }
}