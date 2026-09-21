package com.privi.app

import android.net.Uri
import androidx.media3.common.C
import androidx.media3.common.DataReader
import androidx.media3.common.Format
import androidx.media3.common.util.ParsableByteArray
import androidx.media3.datasource.DataSpec
import androidx.media3.datasource.FileDataSource
import androidx.media3.extractor.DefaultExtractorInput
import androidx.media3.extractor.DefaultExtractorsFactory
import androidx.media3.extractor.Extractor
import androidx.media3.extractor.ExtractorInput
import androidx.media3.extractor.ExtractorOutput
import androidx.media3.extractor.ExtractorsFactory
import androidx.media3.extractor.PositionHolder
import androidx.media3.extractor.SeekMap
import androidx.media3.extractor.TrackOutput
import java.io.EOFException
import java.io.File
import java.io.IOException

/**
 * Repairs the one file defect that makes a clip play as "the timeline moves but
 * the picture stays frozen".
 *
 * Such a file carries two tracks on two different timelines: one track (in every
 * observed case the audio) starts ~2^32 ticks into the future - 13.2 hours at
 * the 90 kHz MP4 timescale, 49.7 days when the ticks are microseconds - while
 * the video track starts at 0. ExoPlayer's clock follows the displaced track, so
 * every video frame looks hours late; `MediaCodecVideoRenderer` then drops the
 * whole stream through `skipSource` (visible as `droppedBufferCount` in the log)
 * and only the progress bar keeps moving.
 *
 * Media3 has no per-track timestamp offset API, so the repair is applied inside
 * the extractor chain: the tracks that start far outside the container duration
 * are shifted back by a constant, which puts every track onto the container's own
 * timeline again. Sample queues, seek map, renderers and the Dart-side timeline
 * offset then all agree on the same numbers, and nothing is written to disk.
 *
 * The patch is deliberately narrow, because it sits on the playback path of
 * every clip:
 *
 *  * the plan is derived from a throw-away pass through Media3's *own* extractors,
 *    so the numbers used are exactly the ones the player will see - there is no
 *    second opinion about the container that could disagree with the decoder;
 *  * a plan is only built when the file proves to be inconsistent, i.e. some
 *    track starts more than [ANOMALY_MARGIN_US] past the container duration;
 *  * tracks already inside `0..duration` are left untouched, so the reference
 *    track (the video, which the MP4 seek map is built from) keeps its
 *    timestamps and seeking stays exact;
 *  * "every track is displaced", a failed probe, an unreadable file and an
 *    unknown container all keep today's behaviour (plain factory).
 */
internal object VideoTimestampNormalizer {

    /**
     * A track start beyond `duration + this` cannot be intentional: a track may
     * not begin after the container it lives in has ended. One minute is far
     * larger than any real lead-in and still ~800x smaller than the 32-bit wraps
     * this fixes.
     */
    private const val ANOMALY_MARGIN_US = 60_000_000L

    /**
     * Probe budgets. A moov-first file answers after a few dozen KB; the budgets
     * only stop a damaged or moov-in-tail file from being read twice, and they
     * bound how long `initialize` can block its caller.
     */
    private const val MAX_PROBE_READS = 2_000
    private const val MAX_PROBE_NANOS = 250_000_000L

    /** Constant shift to add to every sample timestamp of one track. */
    internal class Plan internal constructor(
        val shiftsUs: Map<Int, Long>,
        val trackTypes: Map<Int, Int>,
        val detail: String
    )

    /** What [prepare] decided for one file. */
    internal class Prepared internal constructor(
        /** Factory for `ProgressiveMediaSource.Factory`. */
        val factory: ExtractorsFactory,
        /** Non-null when the file is patched in memory, for the VDIAG log. */
        val patch: Plan?,
        /** One-line outcome, for the VDIAG log. */
        val note: String
    )

    /**
     * Probes [filePath] and returns the extractors factory to play it with.
     *
     * Never throws: a file that cannot be probed simply plays exactly as it does
     * today. The work is bounded by [MAX_PROBE_NANOS], which matters because the
     * handler calls this on the thread that builds the player.
     */
    fun prepare(filePath: String): Prepared {
        val delegate: ExtractorsFactory = DefaultExtractorsFactory()
        val analysis = try {
            analyze(filePath)
        } catch (t: Throwable) {
            Analysis(null, "probe failed (${t.javaClass.simpleName}: ${t.message})")
        }
        val plan = analysis.plan
        return if (plan == null) {
            Prepared(delegate, null, analysis.note)
        } else {
            Prepared(PatchingFactory(delegate, plan), plan, analysis.note)
        }
    }

    private class Analysis(val plan: Plan?, val note: String)

    /**
     * Probe-side [ExtractorOutput]: remembers the container duration and the first
     * sample timestamp of every track, and swallows the sample payload.
     */
    private class Recorder : ExtractorOutput {
        val probes = LinkedHashMap<Int, TrackProbe>()
        var durationUs: Long = C.TIME_UNSET
            private set
        private var endTracksSeen = false

        /** True once every track has reported a first sample. */
        val isComplete: Boolean
            get() = endTracksSeen && durationUs != C.TIME_UNSET && probes.isNotEmpty() &&
                probes.values.all { it.firstSampleUs != C.TIME_UNSET }

        override fun track(id: Int, type: Int): TrackOutput {
            probes.getOrPut(id) { TrackProbe(id, type) }
            return ProbeTrackOutput(this, id)
        }

        override fun endTracks() {
            endTracksSeen = true
        }

        override fun seekMap(seekMap: SeekMap) {
            if (seekMap.durationUs != C.TIME_UNSET) durationUs = seekMap.durationUs
        }

        fun onSample(trackId: Int, timeUs: Long) {
            val probe = probes[trackId] ?: return
            if (probe.firstSampleUs == C.TIME_UNSET) probe.firstSampleUs = timeUs
        }
    }

    /** Sink used during the probe: keeps timestamps, reads the payload away. */
    private class ProbeTrackOutput(
        private val recorder: Recorder,
        private val trackId: Int
    ) : TrackOutput {
        private var scratch = ByteArray(0)

        override fun format(format: Format) {
        }

        override fun sampleData(
            input: DataReader,
            length: Int,
            allowEndOfInput: Boolean,
            sampleDataPart: Int
        ): Int {
            if (scratch.size < length) scratch = ByteArray(length)
            val read = input.read(scratch, 0, length)
            if (read == C.RESULT_END_OF_INPUT && !allowEndOfInput) throw EOFException()
            return read
        }

        override fun sampleData(data: ParsableByteArray, length: Int, sampleDataPart: Int) {
            data.skipBytes(length)
        }

        override fun sampleMetadata(
            timeUs: Long,
            flags: Int,
            size: Int,
            offset: Int,
            cryptoData: TrackOutput.CryptoData?
        ) {
            recorder.onSample(trackId, timeUs)
        }
    }

    /** First sample timestamp seen for one track during the probe. */
    private class TrackProbe(val id: Int, val type: Int) {
        var firstSampleUs: Long = C.TIME_UNSET
    }

    /**
     * Applies a [Plan] to every extractor Media3 instantiates for the file. Only
     * sample timestamps are rewritten; the container itself is parsed exactly as
     * the player parses it today.
     */
    private class PatchingFactory(
        private val delegate: ExtractorsFactory,
        private val plan: Plan
    ) : ExtractorsFactory {

        override fun createExtractors(): Array<Extractor> =
            delegate.createExtractors().map { PatchingExtractor(it, plan) }.toTypedArray()

        override fun createExtractors(
            uri: Uri,
            responseHeaders: Map<String, List<String>>
        ): Array<Extractor> = delegate.createExtractors(uri, responseHeaders)
            .map { PatchingExtractor(it, plan) }
            .toTypedArray()
    }

    private class PatchingExtractor(
        private val delegate: Extractor,
        private val plan: Plan
    ) : Extractor {

        override fun sniff(input: ExtractorInput): Boolean = delegate.sniff(input)

        override fun init(output: ExtractorOutput) {
            delegate.init(PatchingOutput(output, plan))
        }

        override fun read(input: ExtractorInput, seekPosition: PositionHolder): Int =
            delegate.read(input, seekPosition)

        override fun seek(position: Long, timeUs: Long) {
            delegate.seek(position, timeUs)
        }

        override fun release() {
            delegate.release()
        }

        override fun getUnderlyingImplementation(): Extractor = delegate
    }

    /**
     * Hands out a [ShiftingTrackOutput] for the tracks the plan knows about, and
     * the untouched output for everything else.
     */
    private class PatchingOutput(
        private val delegate: ExtractorOutput,
        private val plan: Plan
    ) : ExtractorOutput {
        private val patched = HashMap<Int, TrackOutput>()

        override fun track(id: Int, type: Int): TrackOutput {
            val output = delegate.track(id, type)
            val shiftUs = plan.shiftsUs[id] ?: 0L
            // A different type means these are not the tracks the probe saw, so
            // nothing may be shifted.
            if (shiftUs == 0L || plan.trackTypes[id] != type) return output
            return patched.getOrPut(id) { ShiftingTrackOutput(output, shiftUs) }
        }

        override fun endTracks() {
            delegate.endTracks()
        }

        override fun seekMap(seekMap: SeekMap) {
            delegate.seekMap(seekMap)
        }
    }

    /**
     * Adds the plan's constant to every sample timestamp of one track, which is all
     * it takes to move a track back onto the container timeline: durations, sizes
     * and sync flags are untouched, so the timing inside the track is preserved.
     */
    private class ShiftingTrackOutput(
        private val delegate: TrackOutput,
        private val shiftUs: Long
    ) : TrackOutput {

        override fun format(format: Format) {
            delegate.format(format)
        }

        override fun sampleData(
            input: DataReader,
            length: Int,
            allowEndOfInput: Boolean,
            sampleDataPart: Int
        ): Int = delegate.sampleData(input, length, allowEndOfInput, sampleDataPart)

        override fun sampleData(data: ParsableByteArray, length: Int, sampleDataPart: Int) {
            delegate.sampleData(data, length, sampleDataPart)
        }

        override fun sampleMetadata(
            timeUs: Long,
            flags: Int,
            size: Int,
            offset: Int,
            cryptoData: TrackOutput.CryptoData?
        ) {
            val shifted = if (timeUs == C.TIME_UNSET || timeUs == C.TIME_END_OF_SOURCE) {
                timeUs
            } else {
                timeUs + shiftUs
            }
            delegate.sampleMetadata(shifted, flags, size, offset, cryptoData)
        }
    }

    /**
     * Runs one extraction pass over the file with Media3's bundled extractors and
     * stops as soon as every track has delivered its first sample: that is all the
     * plan needs, and it keeps the pass down to a few dozen KB of reads.
     */
    private fun analyze(filePath: String): Analysis {
        val file = File(filePath)
        if (!file.isFile) return Analysis(null, "skipped: not a readable file")
        val recorder = Recorder()
        val dataSource = FileDataSource()
        val uri = Uri.fromFile(file)
        val length = file.length()
        var extractor: Extractor? = null
        try {
            var input = openInput(dataSource, uri, 0L, length)
            extractor = firstSniffingExtractor(input)
                ?: return Analysis(null, "skipped: no bundled extractor sniffs the file")
            // Sniffing only peeks, but the player's own adapter still resets the peek
            // position before the first read, so doing the same keeps this pass
            // bit-for-bit the pass playback will make.
            input.resetPeekPosition()
            extractor.init(recorder)
            val seekPosition = PositionHolder()
            val deadline = System.nanoTime() + MAX_PROBE_NANOS
            var reads = 0
            while (!recorder.isComplete && reads < MAX_PROBE_READS &&
                System.nanoTime() < deadline
            ) {
                reads++
                when (extractor.read(input, seekPosition)) {
                    Extractor.RESULT_END_OF_INPUT -> break
                    // A moov-in-tail file asks to jump to the moov instead of reading
                    // through the mdat ahead of it, exactly as it does during playback.
                    // Following the jump keeps the probe on the bytes the player will
                    // read - an ignored jump would leave it parsing whatever the
                    // previous call happened to stop on - and it keeps the pass cheap.
                    Extractor.RESULT_SEEK ->
                        input = openInput(dataSource, uri, seekPosition.position, length)
                    else -> Unit
                }
            }
        } catch (e: IOException) {
            return Analysis(null, "skipped: probe read failed (${e.message})")
        } finally {
            try {
                extractor?.release()
            } catch (ignored: Exception) {
            }
            try {
                dataSource.close()
            } catch (ignored: Exception) {
            }
        }
        return decide(recorder)
    }

    /**
     * Positions [dataSource] at [position] and wraps it as an extractor input. A file
     * source reopens at the offset, so following an extractor's seek request costs one
     * reposition instead of a read through everything in between.
     */
    private fun openInput(
        dataSource: FileDataSource,
        uri: Uri,
        position: Long,
        length: Long
    ): ExtractorInput {
        dataSource.close()
        dataSource.open(DataSpec(uri, position, C.LENGTH_UNSET.toLong()))
        return DefaultExtractorInput(dataSource, position, length)
    }

    /**
     * Mirrors `BundledExtractorsAdapter`: the first bundled extractor that
     * recognises the container is the one playback will use, so the probe cannot
     * disagree with the player about the track layout.
     */
    private fun firstSniffingExtractor(input: ExtractorInput): Extractor? {
        val extractors = DefaultExtractorsFactory()
            .createExtractors(Uri.EMPTY, emptyMap<String, List<String>>())
        for (extractor in extractors) {
            if (extractor.sniff(input)) return extractor
        }
        return null
    }

    /**
     * Turns the probe into a decision. Shifting only ever moves tracks that are
     * provably outside the container window, and only by the constant that makes
     * them meet the tracks that are already inside it.
     */
    private fun decide(recorder: Recorder): Analysis {
        val durationUs = recorder.durationUs
        if (durationUs == C.TIME_UNSET || durationUs <= 0L) {
            return Analysis(null, "skipped: container duration unknown")
        }
        val tracks = recorder.probes.values.filter { it.firstSampleUs != C.TIME_UNSET }
        if (tracks.isEmpty()) return Analysis(null, "skipped: no sample timestamps observed")
        val displaced = tracks.filter { it.firstSampleUs > durationUs + ANOMALY_MARGIN_US }
        if (displaced.isEmpty()) {
            return Analysis(null, "clean: ${describe(tracks)} duration=${durationUs}us")
        }
        if (displaced.size == tracks.size) {
            // Every track agrees with the others, so the picture already advances
            // and only the player's own position sits past the duration - that is
            // the case the Dart-side timeline offset covers. Shifting here would
            // have to move the seek map too, so it is left alone.
            return Analysis(
                null,
                "all ${tracks.size} track(s) displaced, left as is: ${describe(tracks)}"
            )
        }
        val baseUs = tracks.minOf { it.firstSampleUs }
        val shifts = LinkedHashMap<Int, Long>()
        val types = LinkedHashMap<Int, Int>()
        for (track in tracks) {
            types[track.id] = track.type
            shifts[track.id] =
                if (track.firstSampleUs > durationUs + ANOMALY_MARGIN_US) {
                    baseUs - track.firstSampleUs
                } else {
                    0L
                }
        }
        val detail = "shifted ${displaced.size}/${tracks.size} track(s) onto the container base: " +
            describe(tracks) + " -> " + describeShifted(tracks, shifts) +
            ", duration=${durationUs}us"
        return Analysis(Plan(shifts, types, detail), detail)
    }

    private fun describe(tracks: Collection<TrackProbe>): String =
        tracks.joinToString(separator = " ") {
            "t${it.id}(${typeName(it.type)})=${it.firstSampleUs}"
        }

    private fun describeShifted(tracks: Collection<TrackProbe>, shifts: Map<Int, Long>): String =
        tracks.joinToString(separator = " ") {
            "t${it.id}=${it.firstSampleUs + (shifts[it.id] ?: 0L)}"
        }

    private fun typeName(type: Int): String = when (type) {
        C.TRACK_TYPE_VIDEO -> "video"
        C.TRACK_TYPE_AUDIO -> "audio"
        C.TRACK_TYPE_TEXT -> "text"
        else -> "type$type"
    }
}
