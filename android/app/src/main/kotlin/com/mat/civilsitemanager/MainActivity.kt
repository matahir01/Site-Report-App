package com.mat.civilsitemanager

import android.content.ContentValues
import android.content.Intent
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileInputStream

class MainActivity : FlutterActivity() {
    companion object {
        private const val REPORT_CHANNEL = "com.mat.civilsitemanager/reports"
        private const val REPORT_FOLDER = "Civil Site Manager"
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            REPORT_CHANNEL,
        ).setMethodCallHandler { call, result ->
            if (call.method != "saveAndOpen") {
                result.notImplemented()
                return@setMethodCallHandler
            }

            val sourcePath = call.argument<String>("sourcePath")
            val fileName = call.argument<String>("fileName")
            val mimeType = call.argument<String>("mimeType") ?: "application/pdf"

            if (sourcePath.isNullOrBlank() || fileName.isNullOrBlank()) {
                result.error(
                    "INVALID_REPORT",
                    "Report path or file name is missing.",
                    null,
                )
                return@setMethodCallHandler
            }

            try {
                val saved = saveToDownloads(File(sourcePath), fileName, mimeType)
                val opened = openReport(saved.first, mimeType)
                result.success(
                    mapOf(
                        "location" to saved.second,
                        "opened" to opened,
                    ),
                )
            } catch (error: Exception) {
                result.error(
                    "REPORT_SAVE_FAILED",
                    error.message ?: "Unable to save report.",
                    null,
                )
            }
        }
    }

    private fun saveToDownloads(
        source: File,
        fileName: String,
        mimeType: String,
    ): Pair<android.net.Uri, String> {
        require(source.exists()) { "Generated report does not exist." }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val resolver = contentResolver
            val values = ContentValues().apply {
                put(MediaStore.MediaColumns.DISPLAY_NAME, fileName)
                put(MediaStore.MediaColumns.MIME_TYPE, mimeType)
                put(
                    MediaStore.MediaColumns.RELATIVE_PATH,
                    Environment.DIRECTORY_DOWNLOADS + "/$REPORT_FOLDER",
                )
                put(MediaStore.MediaColumns.IS_PENDING, 1)
            }

            val uri = resolver.insert(
                MediaStore.Downloads.EXTERNAL_CONTENT_URI,
                values,
            ) ?: error("Android could not create a Downloads entry.")

            try {
                resolver.openOutputStream(uri)?.use { output ->
                    FileInputStream(source).use { input -> input.copyTo(output) }
                } ?: error("Android could not open the Downloads file.")
                values.clear()
                values.put(MediaStore.MediaColumns.IS_PENDING, 0)
                resolver.update(uri, values, null, null)
            } catch (error: Exception) {
                resolver.delete(uri, null, null)
                throw error
            }

            return uri to "Downloads/$REPORT_FOLDER/$fileName"
        }

        @Suppress("DEPRECATION")
        val downloads = Environment.getExternalStoragePublicDirectory(
            Environment.DIRECTORY_DOWNLOADS,
        )
        val folder = File(downloads, REPORT_FOLDER).apply { mkdirs() }
        val destination = File(folder, fileName)
        FileInputStream(source).use { input ->
            destination.outputStream().use { output -> input.copyTo(output) }
        }
        val uri = FileProvider.getUriForFile(
            this,
            "$packageName.fileprovider",
            destination,
        )
        return uri to destination.absolutePath
    }

    private fun openReport(uri: android.net.Uri, mimeType: String): Boolean {
        return try {
            val viewIntent = Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(uri, mimeType)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }
            startActivity(Intent.createChooser(viewIntent, "Open report with"))
            true
        } catch (_: Exception) {
            false
        }
    }
}
