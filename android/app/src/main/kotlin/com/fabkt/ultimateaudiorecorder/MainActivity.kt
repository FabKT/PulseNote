package com.fabkt.ultimateaudiorecorder

import android.content.ContentValues
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.media.MediaCodec
import android.media.MediaCodecInfo
import android.media.MediaExtractor
import android.media.MediaFormat
import android.media.MediaMuxer
import android.media.MediaScannerConnection
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.RandomAccessFile
import java.nio.ByteBuffer
import kotlin.math.max
import kotlin.math.min

class MainActivity : FlutterActivity() {
    private val channelName = "ultimate_audio_recorder/media_export"
    private val timeoutUs = 10_000L

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                if (call.method != "saveAudio" && call.method != "saveAudioVideo") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }

                val filePath = call.argument<String>("filePath")
                val displayName =
                    call.argument<String>("displayName") ?: "Ultimate Audio Recorder audio"
                if (filePath.isNullOrBlank()) {
                    result.error("missing_file", "Missing audio file path.", null)
                    return@setMethodCallHandler
                }

                try {
                    result.success(
                        if (call.method == "saveAudioVideo") {
                            saveAudioVideo(filePath, displayName)
                        } else {
                            saveAudio(filePath, displayName)
                        }
                    )
                } catch (error: Exception) {
                    Log.e("UARMediaExport", "Media export failed", error)
                    result.error("save_failed", error.message, null)
                }
            }
    }

    private fun saveAudio(filePath: String, displayName: String): String {
        val source = File(filePath)
        if (!source.exists()) throw IllegalArgumentException("Audio file not found.")
        val extension = source.extension.ifBlank { "m4a" }
        val cleanName = displayName
            .replace(Regex("[\\\\/:*?\"<>|]"), "_")
            .ifBlank { "Ultimate Audio Recorder audio" }
        val fileName = if (cleanName.endsWith(".$extension")) cleanName else "$cleanName.$extension"
        val mimeType = when (extension.lowercase()) {
            "wav" -> "audio/wav"
            "mp3" -> "audio/mpeg"
            "aac" -> "audio/aac"
            else -> "audio/mp4"
        }

        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val resolver = applicationContext.contentResolver
            val values = ContentValues().apply {
                put(MediaStore.Audio.Media.DISPLAY_NAME, fileName)
                put(MediaStore.Audio.Media.MIME_TYPE, mimeType)
                put(MediaStore.Audio.Media.RELATIVE_PATH, "Music/Ultimate Audio Recorder")
                put(MediaStore.Audio.Media.IS_PENDING, 1)
            }
            val uri: Uri = resolver.insert(MediaStore.Audio.Media.EXTERNAL_CONTENT_URI, values)
                ?: throw IllegalStateException("Unable to create MediaStore entry.")
            resolver.openOutputStream(uri)?.use { output ->
                source.inputStream().use { input -> input.copyTo(output) }
            } ?: throw IllegalStateException("Unable to open MediaStore output.")
            values.clear()
            values.put(MediaStore.Audio.Media.IS_PENDING, 0)
            resolver.update(uri, values, null, null)
            uri.toString()
        } else {
            val musicDir = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_MUSIC)
            val targetDir = File(musicDir, "Ultimate Audio Recorder")
            if (!targetDir.exists()) targetDir.mkdirs()
            val target = File(targetDir, fileName)
            source.copyTo(target, overwrite = true)
            MediaScannerConnection.scanFile(
                applicationContext,
                arrayOf(target.absolutePath),
                arrayOf(mimeType),
                null,
            )
            target.absolutePath
        }
    }

    private fun saveAudioVideo(filePath: String, displayName: String): String {
        val source = File(filePath)
        if (!source.exists()) throw IllegalArgumentException("Audio file not found.")
        val cleanName = displayName
            .replace(Regex("[\\\\/:*?\"<>|]"), "_")
            .ifBlank { "Ultimate Audio Recorder audio" }
        val fileName = if (cleanName.endsWith(".mp4")) cleanName else "$cleanName.mp4"
        val tempVideo = File(cacheDir, "uar_gallery_${System.currentTimeMillis()}.mp4")

        createAudioVideoFile(source, tempVideo, cleanName)

        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val resolver = applicationContext.contentResolver
            val values = ContentValues().apply {
                put(MediaStore.Video.Media.DISPLAY_NAME, fileName)
                put(MediaStore.Video.Media.MIME_TYPE, "video/mp4")
                put(MediaStore.Video.Media.RELATIVE_PATH, "Movies/Ultimate Audio Recorder")
                put(MediaStore.Video.Media.IS_PENDING, 1)
            }
            val uri: Uri = resolver.insert(MediaStore.Video.Media.EXTERNAL_CONTENT_URI, values)
                ?: throw IllegalStateException("Unable to create MediaStore video entry.")
            resolver.openOutputStream(uri)?.use { output ->
                tempVideo.inputStream().use { input -> input.copyTo(output) }
            } ?: throw IllegalStateException("Unable to open MediaStore video output.")
            values.clear()
            values.put(MediaStore.Video.Media.IS_PENDING, 0)
            resolver.update(uri, values, null, null)
            tempVideo.delete()
            uri.toString()
        } else {
            val moviesDir = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_MOVIES)
            val targetDir = File(moviesDir, "Ultimate Audio Recorder")
            if (!targetDir.exists()) targetDir.mkdirs()
            val target = File(targetDir, fileName)
            tempVideo.copyTo(target, overwrite = true)
            tempVideo.delete()
            MediaScannerConnection.scanFile(
                applicationContext,
                arrayOf(target.absolutePath),
                arrayOf("video/mp4"),
                null,
            )
            target.absolutePath
        }
    }

    private fun createAudioVideoFile(audioFile: File, outputFile: File, title: String) {
        val extractor = MediaExtractor()
        extractor.setDataSource(audioFile.absolutePath)
        val audioTrackIndex = findAudioTrack(extractor)
        if (audioTrackIndex < 0) {
            extractor.release()
            throw IllegalArgumentException("No audio track found.")
        }
        val audioFormat = extractor.getTrackFormat(audioTrackIndex)
        Log.d("UARMediaExport", "Input audio format: $audioFormat")
        val mime = audioFormat.getString(MediaFormat.KEY_MIME)
        if (mime == "audio/raw") {
            extractor.release()
            val tempAac = File(cacheDir, "uar_gallery_audio_${System.currentTimeMillis()}.m4a")
            try {
                transcodeRawAudioToAac(audioFile, tempAac)
                createAudioVideoFile(tempAac, outputFile, title)
            } finally {
                tempAac.delete()
            }
            return
        }
        val durationUs = if (audioFormat.containsKey(MediaFormat.KEY_DURATION)) {
            max(audioFormat.getLong(MediaFormat.KEY_DURATION), 1_000_000L)
        } else {
            1_000_000L
        }
        extractor.selectTrack(audioTrackIndex)

        val muxer = MediaMuxer(outputFile.absolutePath, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
        val audioMuxerTrack = muxer.addTrack(sanitizeAudioFormat(audioFormat))
        val encoder = MediaCodec.createEncoderByType(MediaFormat.MIMETYPE_VIDEO_AVC)
        val videoFormat = MediaFormat.createVideoFormat(MediaFormat.MIMETYPE_VIDEO_AVC, 1080, 1080).apply {
            setInteger(MediaFormat.KEY_COLOR_FORMAT, MediaCodecInfo.CodecCapabilities.COLOR_FormatSurface)
            setInteger(MediaFormat.KEY_BIT_RATE, 2_800_000)
            setInteger(MediaFormat.KEY_FRAME_RATE, 1)
            setInteger(MediaFormat.KEY_I_FRAME_INTERVAL, 1)
        }
        encoder.configure(videoFormat, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
        val inputSurface = encoder.createInputSurface()
        encoder.start()

        var muxerStarted = false
        var videoMuxerTrack = -1
        val bufferInfo = MediaCodec.BufferInfo()
        var frameIndex = 0
        val frameCount = max(1, ((durationUs + 999_999L) / 1_000_000L).toInt())
        var signaledEnd = false

        try {
            while (true) {
                if (frameIndex < frameCount) {
                    val canvas = inputSurface.lockCanvas(null)
                    drawAudioPoster(canvas, title, frameIndex, frameCount)
                    inputSurface.unlockCanvasAndPost(canvas)
                    frameIndex++
                } else if (!signaledEnd) {
                    encoder.signalEndOfInputStream()
                    signaledEnd = true
                }

                val outputIndex = encoder.dequeueOutputBuffer(bufferInfo, timeoutUs)
                if (outputIndex == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED) {
                    videoMuxerTrack = muxer.addTrack(encoder.outputFormat)
                    muxer.start()
                    muxerStarted = true
                } else if (outputIndex >= 0) {
                    val encodedData = encoder.getOutputBuffer(outputIndex)
                    if (encodedData != null && bufferInfo.size > 0 && muxerStarted) {
                        encodedData.position(bufferInfo.offset)
                        encodedData.limit(bufferInfo.offset + bufferInfo.size)
                        bufferInfo.presentationTimeUs = min(
                            (frameIndex - 1).coerceAtLeast(0) * 1_000_000L,
                            durationUs,
                        )
                        muxer.writeSampleData(videoMuxerTrack, encodedData, bufferInfo)
                    }
                    val endOfStream = bufferInfo.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0
                    encoder.releaseOutputBuffer(outputIndex, false)
                    if (endOfStream) break
                }
            }

            if (!muxerStarted) throw IllegalStateException("Video encoder did not start.")
            writeAudioTrack(extractor, muxer, audioMuxerTrack)
        } finally {
            extractor.release()
            encoder.stop()
            encoder.release()
            inputSurface.release()
            muxer.stop()
            muxer.release()
        }
    }

    private fun transcodeRawAudioToAac(inputFile: File, outputFile: File) {
        val extractor = MediaExtractor()
        extractor.setDataSource(inputFile.absolutePath)
        val audioTrackIndex = findAudioTrack(extractor)
        if (audioTrackIndex < 0) {
            extractor.release()
            throw IllegalArgumentException("No audio track found.")
        }

        val sourceFormat = extractor.getTrackFormat(audioTrackIndex)
        val sampleRate = sourceFormat.getInteger(MediaFormat.KEY_SAMPLE_RATE)
        val channelCount = sourceFormat.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
        val bytesPerSample = 2
        val bytesPerFrame = channelCount * bytesPerSample
        extractor.release()
        val pcmInput = RandomAccessFile(inputFile, "r")
        val dataOffset = findWavDataOffset(pcmInput)
        pcmInput.seek(dataOffset)

        val encoder = MediaCodec.createEncoderByType(MediaFormat.MIMETYPE_AUDIO_AAC)
        val encodeFormat = MediaFormat.createAudioFormat(
            MediaFormat.MIMETYPE_AUDIO_AAC,
            sampleRate,
            channelCount,
        ).apply {
            setInteger(MediaFormat.KEY_BIT_RATE, 96_000)
            setInteger(
                MediaFormat.KEY_AAC_PROFILE,
                MediaCodecInfo.CodecProfileLevel.AACObjectLC,
            )
        }
        encoder.configure(encodeFormat, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)

        val muxer = MediaMuxer(outputFile.absolutePath, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
        val info = MediaCodec.BufferInfo()
        var muxerStarted = false
        var muxerTrack = -1
        var inputDone = false
        var outputDone = false
        var submittedBytes = 0L
        val readBuffer = ByteArray(16 * 1024)

        encoder.start()
        try {
            while (!outputDone) {
                if (!inputDone) {
                    val inputIndex = encoder.dequeueInputBuffer(timeoutUs)
                    if (inputIndex >= 0) {
                        val inputBuffer = encoder.getInputBuffer(inputIndex)
                            ?: throw IllegalStateException("AAC input buffer unavailable.")
                        inputBuffer.clear()
                        val maxRead = min(readBuffer.size, inputBuffer.remaining())
                        val sampleSize = pcmInput.read(readBuffer, 0, maxRead)
                        if (sampleSize <= 0) {
                            val ptsUs = if (bytesPerFrame > 0) {
                                submittedBytes / bytesPerFrame * 1_000_000L / sampleRate
                            } else {
                                0L
                            }
                            encoder.queueInputBuffer(
                                inputIndex,
                                0,
                                0,
                                ptsUs,
                                MediaCodec.BUFFER_FLAG_END_OF_STREAM,
                            )
                            inputDone = true
                        } else {
                            inputBuffer.put(readBuffer, 0, sampleSize)
                            val ptsUs = if (bytesPerFrame > 0) {
                                submittedBytes / bytesPerFrame * 1_000_000L / sampleRate
                            } else {
                                0L
                            }
                            encoder.queueInputBuffer(inputIndex, 0, sampleSize, ptsUs, 0)
                            submittedBytes += sampleSize.toLong()
                        }
                    }
                }

                val outputIndex = encoder.dequeueOutputBuffer(info, timeoutUs)
                when {
                    outputIndex == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> {
                        muxerTrack = muxer.addTrack(encoder.outputFormat)
                        muxer.start()
                        muxerStarted = true
                    }
                    outputIndex >= 0 -> {
                        val outputBuffer = encoder.getOutputBuffer(outputIndex)
                        if (
                            outputBuffer != null &&
                            info.size > 0 &&
                            muxerStarted &&
                            (info.flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG) == 0
                        ) {
                            outputBuffer.position(info.offset)
                            outputBuffer.limit(info.offset + info.size)
                            muxer.writeSampleData(muxerTrack, outputBuffer, info)
                        }
                        outputDone = (info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM) != 0
                        encoder.releaseOutputBuffer(outputIndex, false)
                    }
                }
            }
        } finally {
            pcmInput.close()
            encoder.stop()
            encoder.release()
            if (muxerStarted) muxer.stop()
            muxer.release()
        }
    }

    private fun findWavDataOffset(file: RandomAccessFile): Long {
        file.seek(12L)
        val chunkId = ByteArray(4)
        while (file.filePointer + 8 <= file.length()) {
            file.readFully(chunkId)
            val chunkSize = readLittleEndianInt(file)
            if (String(chunkId, Charsets.US_ASCII) == "data") {
                return file.filePointer
            }
            file.seek(file.filePointer + chunkSize + (chunkSize and 1))
        }
        return 44L
    }

    private fun readLittleEndianInt(file: RandomAccessFile): Int {
        val b0 = file.read()
        val b1 = file.read()
        val b2 = file.read()
        val b3 = file.read()
        if (b0 < 0 || b1 < 0 || b2 < 0 || b3 < 0) return 0
        return (b0 and 0xff) or
            ((b1 and 0xff) shl 8) or
            ((b2 and 0xff) shl 16) or
            ((b3 and 0xff) shl 24)
    }

    private fun findAudioTrack(extractor: MediaExtractor): Int {
        for (i in 0 until extractor.trackCount) {
            val format = extractor.getTrackFormat(i)
            val mime = format.getString(MediaFormat.KEY_MIME) ?: continue
            if (mime.startsWith("audio/")) return i
        }
        return -1
    }

    private fun sanitizeAudioFormat(source: MediaFormat): MediaFormat {
        val mime = source.getString(MediaFormat.KEY_MIME)
            ?: throw IllegalArgumentException("Audio MIME type missing.")
        if (mime != MediaFormat.MIMETYPE_AUDIO_AAC && mime != "audio/mp4a-latm") {
            throw IllegalArgumentException("Audio format not supported for gallery video: $mime")
        }

        val sampleRate = source.getInteger(MediaFormat.KEY_SAMPLE_RATE)
        val channelCount = source.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
        val clean = MediaFormat.createAudioFormat(
            MediaFormat.MIMETYPE_AUDIO_AAC,
            sampleRate,
            channelCount,
        )
        if (source.containsKey(MediaFormat.KEY_BIT_RATE)) {
            clean.setInteger(MediaFormat.KEY_BIT_RATE, source.getInteger(MediaFormat.KEY_BIT_RATE))
        }
        if (source.containsKey(MediaFormat.KEY_AAC_PROFILE)) {
            clean.setInteger(MediaFormat.KEY_AAC_PROFILE, source.getInteger(MediaFormat.KEY_AAC_PROFILE))
        }
        if (source.containsKey("csd-0")) {
            clean.setByteBuffer("csd-0", source.getByteBuffer("csd-0"))
        }
        return clean
    }

    private fun writeAudioTrack(
        extractor: MediaExtractor,
        muxer: MediaMuxer,
        muxerTrack: Int,
    ) {
        val bufferSize = 512 * 1024
        val buffer = ByteBuffer.allocateDirect(bufferSize)
        val info = MediaCodec.BufferInfo()
        while (true) {
            val sampleSize = extractor.readSampleData(buffer, 0)
            if (sampleSize < 0) break
            info.set(0, sampleSize, extractor.sampleTime, extractor.sampleFlags)
            muxer.writeSampleData(muxerTrack, buffer, info)
            extractor.advance()
        }
    }

    private fun drawAudioPoster(canvas: Canvas, title: String, frameIndex: Int, frameCount: Int) {
        canvas.drawColor(Color.BLACK)
    }
}
