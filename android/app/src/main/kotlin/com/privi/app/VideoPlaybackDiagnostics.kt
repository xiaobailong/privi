package com.privi.app

import android.os.SystemClock
import androidx.media3.common.C
import androidx.media3.common.ColorInfo
import androidx.media3.common.Format
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.common.Tracks
import androidx.media3.common.VideoSize
import androidx.media3.exoplayer.DecoderCounters
import androidx.media3.exoplayer.DecoderReuseEvaluation
import androidx.media3.exoplayer.analytics.AnalyticsListener
import androidx.media3.exoplayer.source.LoadEventInfo
import androidx.media3.exoplayer.source.MediaLoadData
import java.io.IOException
import java.util.Locale

/**
 * Collects everything the decoder chain knows about a clip and prints it as one
 * greppable `VDIAG[...]` line.
 *
 * Why this exists: users report clips that stay black (or frozen) while
 * dragging the seek bar still shows frames, and the log had no way to tell such
 * a clip apart from a player that never started. What was logged before were
 * state changes, `onIsPlayingChanged` and errors - not the facts that decide
 * whether a decode can be shown at all: container brand, codec string, the
 * decoder that was picked (hardware or software), colour bit depth, whether a
 * frame ever reached the surface, how many frames were dropped. Without those
 * lines a phone-only failure can only be guessed at.
 *
 * The class is passive: it never drives the player, so an unsupported file
 * still fails in exactly the same way - only louder.
 *
 * [Player.Listener] and [AnalyticsListener] are implemented by the same object,
 * so the handler registers one instance twice. Every callback arrives on
 * ExoPlayer's application looper.
 */
class VideoPlaybackDiagnostics(
    private val logI: (String) -> Unit,
    private val logW: (String) -> Unit
) : Player.Listener, AnalyticsListener {

    /** Container as reported by the track formats, e.g. `video/mp4`. */
    var containerMimeType: String? = null
        private set

    /** The video track format as declared by the container / extractor. */
    var videoFormat: Format? = null
        private set

    /** The audio track format as declared by the container / extractor. */
    var audioFormat: Format? = null
        private set

    /** Name of the MediaCodec instance actually used for video. */
    var videoDecoderName: String? = null
        private set

    /** Name of the MediaCodec instance actually used for audio. */
    var audioDecoderName: String? = null
        private set

    /** `true` once a frame reached the output surface. */
    var renderedFirstFrame: Boolean = false
        private set

    /** Set when this instance was built (player initialize), for elapsed math. */
    private val createdElapsedMs = SystemClock.elapsedRealtime()
    private var firstFrameAtMs: Long = -1L
    private var videoDecoderInitMs: Long = -1L
    private var audioDecoderInitMs: Long = -1L
    private var videoSize: VideoSize? = null
    private var videoTrackSupported: Boolean? = null
    private var audioTrackSupported: Boolean? = null
    private var videoRendererEnabled = false
    private var renderedFrames = 0
    private var droppedFrames = 0
    private var skippedFrames = 0
    private var maxConsecutiveDropped = 0
    private var decoderInits = 0
    private var loadErrors = 0
    private var lastDroppedLogged = 0
    private var frameProcessingOffsetUs = 0L
    private var frameProcessingOffsetCount = 0

    /** Prints the full picture under a reason tag; `VDIAG` is the grep key. */
    fun logSummary(reason: String) {
        logI("VDIAG[$reason] ${summary()}")
    }

    /**
     * One line describing the whole decode chain.
     *
     * `VideoSize.unappliedRotationDegrees` is deprecated in media3 (renderers
     * apply rotation themselves, so it reads 0 on current versions), but a
     * non-zero value is precisely the kind of oddity worth having in a user's
     * log, and this is a log-only reader - hence the suppressed warning.
     */
    @Suppress("DEPRECATION")
    fun summary(): String {
        val sb = StringBuilder()
        val video = videoFormat
        val audio = audioFormat
        val color = video?.colorInfo
        val size = videoSize
        sb.append("container=").append(containerMimeType ?: "-")
        sb.append(" video=").append(codecOf(video))
        if (video != null) {
            sb.append(' ').append(video.width).append('x').append(video.height)
            sb.append(" fps=").append(rateOf(video))
            sb.append(" rot=").append(video.rotationDegrees)
            sb.append(" par=").append(fixed(video.pixelWidthHeightRatio))
            if (video.bitrate > 0) {
                sb.append(" bitrate=").append(video.bitrate / 1000).append('k')
            }
        }
        sb.append(" color=").append(colorOf(color))
        sb.append(" bitDepth=").append(bitDepthOf(color))
        sb.append(" hdr=").append(isHdr(color))
        sb.append(" vTrackSupported=").append(videoTrackSupported ?: "?")
        sb.append(" vDecoder=").append(videoDecoderName ?: "-")
            .append(suffixOf(videoDecoderName))
        sb.append(" vDecoderInit=").append(videoDecoderInitMs).append("ms")
        sb.append(" audio=").append(codecOf(audio))
        if (audio != null) {
            sb.append(" ch=").append(audio.channelCount)
            sb.append(" sr=").append(audio.sampleRate)
        }
        sb.append(" aTrackSupported=").append(audioTrackSupported ?: "?")
        sb.append(" aDecoder=").append(audioDecoderName ?: "-")
        sb.append(" aDecoderInit=").append(audioDecoderInitMs).append("ms")
        if (size == null) {
            sb.append(" size=-")
        } else {
            sb.append(" size=").append(size.width).append('x').append(size.height)
            sb.append(" unappliedRotation=").append(size.unappliedRotationDegrees)
            sb.append(" sizePar=").append(fixed(size.pixelWidthHeightRatio))
        }
        sb.append(" videoRendererEnabled=").append(videoRendererEnabled)
        sb.append(" firstFrameRendered=").append(renderedFirstFrame)
            .append('@').append(firstFrameAtMs).append("ms")
        sb.append(" renderedFrames=").append(renderedFrames)
        sb.append(" droppedFrames=").append(droppedFrames)
        sb.append(" skippedFrames=").append(skippedFrames)
        sb.append(" maxConsecutiveDropped=").append(maxConsecutiveDropped)
        sb.append(" decoderInits=").append(decoderInits)
        sb.append(" loadErrors=").append(loadErrors)
        if (frameProcessingOffsetCount > 0) {
            sb.append(" avgFrameProcessingOffset=")
                .append(frameProcessingOffsetUs / frameProcessingOffsetCount)
                .append("us")
        }
        return sb.toString()
    }

    /**
     * `PlaybackException` plus its cause chain.
     *
     * ExoPlayer hides the interesting part one level down: a container it
     * cannot parse reports `ERROR_CODE_PARSING_CONTAINER_MALFORMED` and the
     * extractor's own exception (often naming the offending box) sits in the
     * cause, which the previous log line dropped.
     */
    fun describeError(error: PlaybackException): String {
        val sb = StringBuilder()
        sb.append("code=").append(error.errorCode)
        sb.append('(').append(error.errorCodeName).append(')')
        sb.append(" msg=").append(error.localizedMessage ?: "-")
        var cause: Throwable? = error.cause
        var depth = 0
        while (cause != null && depth < 6) {
            sb.append(" <- ").append(cause.javaClass.simpleName)
                .append(": ").append(cause.message ?: "-")
            cause = cause.cause
            depth++
        }
        return sb.toString()
    }

    // ---- Player.Listener: what the file declares ----

    /**
     * Dumps every track the extractor found, before any decoder runs.
     *
     * `supported=false` here is the quietest failure mode of all: the player
     * then plays the audio track only and the screen stays black, with no
     * error event at all.
     */
    override fun onTracksChanged(tracks: Tracks) {
        for (group in tracks.groups) {
            for (index in 0 until group.length) {
                val format = group.getTrackFormat(index)
                val supported = group.isTrackSupported(index)
                when (group.type) {
                    C.TRACK_TYPE_VIDEO -> {
                        if (videoFormat == null) videoFormat = format
                        containerMimeType = format.containerMimeType ?: containerMimeType
                        videoTrackSupported = supported
                    }
                    C.TRACK_TYPE_AUDIO -> {
                        if (audioFormat == null) audioFormat = format
                        containerMimeType = format.containerMimeType ?: containerMimeType
                        audioTrackSupported = supported
                    }
                    else -> Unit
                }
            }
        }
        logI("VDIAG[tracks] ${describeTracks(tracks)}")
    }

    /** Same deprecated-but-informative rotation field as [summary]. */
    @Suppress("DEPRECATION")
    override fun onVideoSizeChanged(videoSize: VideoSize) {
        this.videoSize = videoSize
        logI("VDIAG[size] ${videoSize.width}x${videoSize.height} " +
            "unappliedRotation=${videoSize.unappliedRotationDegrees} " +
            "par=${fixed(videoSize.pixelWidthHeightRatio)}")
    }

    // ---- AnalyticsListener: what the decoders actually do ----

    override fun onVideoInputFormatChanged(
        eventTime: AnalyticsListener.EventTime,
        format: Format,
        decoderReuseEvaluation: DecoderReuseEvaluation?
    ) {
        videoFormat = format
        containerMimeType = format.containerMimeType ?: containerMimeType
        logI("VDIAG[input] ${codecOf(format)} ${format.width}x${format.height} " +
            "fps=${rateOf(format)} rotation=${format.rotationDegrees} " +
            "color=${colorOf(format.colorInfo)} " +
            "bitDepth=${bitDepthOf(format.colorInfo)} " +
            "hdr=${isHdr(format.colorInfo)} reuse=$decoderReuseEvaluation")
    }

    override fun onVideoDecoderInitialized(
        eventTime: AnalyticsListener.EventTime,
        decoderName: String,
        initializedTimestampMs: Long,
        initializationDurationMs: Long
    ) {
        videoDecoderName = decoderName
        videoDecoderInitMs = initializationDurationMs
        decoderInits++
        logI("VDIAG[decoder] $decoderName init=${initializationDurationMs}ms" +
            suffixOf(decoderName))
    }

    override fun onAudioInputFormatChanged(
        eventTime: AnalyticsListener.EventTime,
        format: Format,
        decoderReuseEvaluation: DecoderReuseEvaluation?
    ) {
        audioFormat = format
        containerMimeType = format.containerMimeType ?: containerMimeType
        logI("VDIAG[input-audio] ${codecOf(format)} ch=${format.channelCount} " +
            "sr=${format.sampleRate} reuse=$decoderReuseEvaluation")
    }

    override fun onAudioDecoderInitialized(
        eventTime: AnalyticsListener.EventTime,
        decoderName: String,
        initializedTimestampMs: Long,
        initializationDurationMs: Long
    ) {
        audioDecoderName = decoderName
        audioDecoderInitMs = initializationDurationMs
        logI("VDIAG[decoder-audio] $decoderName " +
            "init=${initializationDurationMs}ms" + suffixOf(decoderName))
    }

    override fun onVideoEnabled(
        eventTime: AnalyticsListener.EventTime,
        decoderCounters: DecoderCounters
    ) {
        videoRendererEnabled = true
        sync(decoderCounters)
        logI("VDIAG[video-enabled] ${summary()}")
    }

    override fun onVideoDisabled(
        eventTime: AnalyticsListener.EventTime,
        decoderCounters: DecoderCounters
    ) {
        videoRendererEnabled = false
        sync(decoderCounters)
        logI("VDIAG[video-disabled] ${summary()}")
    }

    /**
     * The single most important callback: if it never fires, the renderer never
     * put a frame on screen, and no amount of state logging shows that.
     *
     * `output` is declared non-null on purpose. Media3 1.5.1 puts no
     * `@Nullable` on this parameter, so Kotlin would reject a nullable
     * override, and `MediaCodecVideoRenderer.maybeNotifyRenderedFirstFrame()`
     * returns early while `displaySurface == null` - the parameter can
     * therefore never be null. (Checked against the 1.5.1 bytecode in
     * `build/_m3disp2.ps1` and the method body it points at.)
     */
    override fun onRenderedFirstFrame(
        eventTime: AnalyticsListener.EventTime,
        output: Any,
        renderTimeMs: Long
    ) {
        if (renderedFirstFrame) return
        renderedFirstFrame = true
        firstFrameAtMs = renderTimeMs
        logI("VDIAG[first-frame] rendered at ${renderTimeMs}ms, " +
            "sinceInit=${SystemClock.elapsedRealtime() - createdElapsedMs}ms, " +
            "output=${output.javaClass.simpleName}")
        logSummary("first-frame")
    }

    override fun onDroppedVideoFrames(
        eventTime: AnalyticsListener.EventTime,
        droppedFrames: Int,
        elapsedMs: Long
    ) {
        this.droppedFrames = droppedFrames
        if (lastDroppedLogged > 0 && droppedFrames - lastDroppedLogged < DROP_LOG_STEP) {
            return
        }
        lastDroppedLogged = droppedFrames
        logW("VDIAG[dropped] total=$droppedFrames window=${elapsedMs}ms " +
            "firstFrameRendered=$renderedFirstFrame " +
            "renderedFrames=$renderedFrames")
    }

    override fun onVideoFrameProcessingOffset(
        eventTime: AnalyticsListener.EventTime,
        totalProcessingOffsetUs: Long,
        frameCount: Int
    ) {
        frameProcessingOffsetUs += totalProcessingOffsetUs
        frameProcessingOffsetCount += frameCount
    }

    /**
     * A local file that cannot be read is reported here, not as a player error.
     */
    override fun onLoadError(
        eventTime: AnalyticsListener.EventTime,
        loadEventInfo: LoadEventInfo,
        mediaLoadData: MediaLoadData,
        error: IOException,
        canceled: Boolean
    ) {
        loadErrors++
        logW("VDIAG[load-error] canceled=$canceled " +
            "${error.javaClass.simpleName}: ${error.message}")
    }

    private fun sync(counters: DecoderCounters) {
        renderedFrames = counters.renderedOutputBufferCount
        skippedFrames = counters.skippedOutputBufferCount
        droppedFrames = maxOf(droppedFrames, counters.droppedBufferCount)
        maxConsecutiveDropped =
            maxOf(maxConsecutiveDropped, counters.maxConsecutiveDroppedBufferCount)
        decoderInits = maxOf(decoderInits, counters.decoderInitCount)
    }

    /** Per-track listing: the rawest evidence a file carries about itself. */
    private fun describeTracks(tracks: Tracks): String {
        val sb = StringBuilder()
        for (group in tracks.groups) {
            val kind = when (group.type) {
                C.TRACK_TYPE_VIDEO -> "video"
                C.TRACK_TYPE_AUDIO -> "audio"
                C.TRACK_TYPE_TEXT -> "text"
                else -> "type${group.type}"
            }
            for (index in 0 until group.length) {
                val format = group.getTrackFormat(index)
                sb.append(kind).append('{')
                sb.append("id=").append(format.id ?: "-").append(',')
                sb.append("container=").append(format.containerMimeType ?: "-").append(',')
                sb.append("codecs=").append(format.codecs ?: "-")
                if (group.type == C.TRACK_TYPE_VIDEO) {
                    sb.append(',').append(format.width).append('x').append(format.height)
                    sb.append(",fps=").append(rateOf(format))
                    sb.append(",color=").append(colorOf(format.colorInfo))
                    sb.append(",bitDepth=").append(bitDepthOf(format.colorInfo))
                }
                if (group.type == C.TRACK_TYPE_AUDIO) {
                    sb.append(",ch=").append(format.channelCount)
                    sb.append(",sr=").append(format.sampleRate)
                }
                sb.append(",supported=").append(group.isTrackSupported(index))
                sb.append("} ")
            }
        }
        return sb.toString().trim().ifEmpty { "no tracks found" }
    }

    private fun codecOf(format: Format?): String {
        if (format == null) return "-"
        val mime = format.sampleMimeType ?: "-"
        val codecs = format.codecs
        if (codecs.isNullOrEmpty() || codecs == mime) return mime
        return "$mime/$codecs"
    }

    private fun rateOf(format: Format?): String {
        if (format == null || format.frameRate <= 0f) return "-"
        return String.format(Locale.US, "%.3f", format.frameRate)
    }

    private fun fixed(value: Float): String =
        String.format(Locale.US, "%.2f", value)

    private fun colorOf(colorInfo: ColorInfo?): String {
        if (colorInfo == null) return "-"
        val space = when (colorInfo.colorSpace) {
            C.COLOR_SPACE_BT601 -> "bt601"
            C.COLOR_SPACE_BT709 -> "bt709"
            C.COLOR_SPACE_BT2020 -> "bt2020"
            else -> "cs${colorInfo.colorSpace}"
        }
        val range = when (colorInfo.colorRange) {
            C.COLOR_RANGE_LIMITED -> "limited"
            C.COLOR_RANGE_FULL -> "full"
            else -> "range${colorInfo.colorRange}"
        }
        val transfer = when (colorInfo.colorTransfer) {
            C.COLOR_TRANSFER_SDR -> "sdr"
            C.COLOR_TRANSFER_SRGB -> "srgb"
            C.COLOR_TRANSFER_LINEAR -> "linear"
            C.COLOR_TRANSFER_GAMMA_2_2 -> "gamma22"
            C.COLOR_TRANSFER_ST2084 -> "pq"
            C.COLOR_TRANSFER_HLG -> "hlg"
            else -> "transfer${colorInfo.colorTransfer}"
        }
        return "$space/$range/$transfer"
    }

    /** `8/8`, or `?` when the container never declared the bit depth. */
    private fun bitDepthOf(colorInfo: ColorInfo?): String {
        if (colorInfo == null || !colorInfo.isBitdepthValid()) return "?"
        return "${colorInfo.lumaBitdepth}/${colorInfo.chromaBitdepth}"
    }

    /** PQ or HLG transfer means the clip is HDR, which many decoders reject. */
    private fun isHdr(colorInfo: ColorInfo?): Boolean {
        if (colorInfo == null) return false
        return colorInfo.colorTransfer == C.COLOR_TRANSFER_ST2084 ||
            colorInfo.colorTransfer == C.COLOR_TRANSFER_HLG
    }

    /**
     * `(software)` / `(hardware)` hint for a decoder name.
     *
     * Software decoders are one of the usual reasons a clip plays on one phone
     * and not on another: they are slower, they drop frames at high
     * resolutions, and their surface output behaves unlike a vendor decoder.
     */
    private fun suffixOf(name: String?): String {
        if (name == null) return ""
        val lower = name.lowercase(Locale.US)
        val software = lower.contains(".sw.") ||
            lower.startsWith("omx.google.") ||
            lower.startsWith("c2.android.")
        return if (software) " (software)" else " (hardware)"
    }

    private companion object {
        /** Log only every Nth dropped frame, so the file stays readable. */
        const val DROP_LOG_STEP = 30
    }
}
