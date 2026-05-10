package com.fabkt.ultimateaudiorecorder

import android.content.ContentValues
import android.media.MediaScannerConnection
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private val channelName = "ultimate_audio_recorder/media_export"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                if (call.method != "saveAudio") {
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
                    result.success(saveAudio(filePath, displayName))
                } catch (error: Exception) {
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
}
