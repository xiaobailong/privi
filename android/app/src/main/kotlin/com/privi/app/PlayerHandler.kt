package com.privi.app

internal interface PlayerHandler {
    val textureId: Long

    fun initialize(filePath: String)
    fun play()
    fun pause()
    fun seekTo(positionMs: Long)
    fun setVolume(volume: Double)
    fun setPlaybackSpeed(speed: Double)
    fun getPosition(): Long
    fun getDuration(): Long
    fun isPlaying(): Boolean
    fun status(): Map<String, Any?>
    fun release()
}