package com.example.tachocontrol

import android.content.ContentUris
import android.content.ContentValues
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
	private val channelName = "tachocontrol/storage"

	override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
		super.configureFlutterEngine(flutterEngine)

		MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
			.setMethodCallHandler { call, result ->
				if (call.method != "saveBackupToDownloads") {
					result.notImplemented()
					return@setMethodCallHandler
				}

				if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
					result.error(
						"ANDROID_VERSION",
						"Public Download backup requires Android 10 or newer",
						null,
					)
					return@setMethodCallHandler
				}

				val fileName = call.argument<String>("fileName")
				val bytes = call.argument<ByteArray>("bytes")
				if (fileName == null || bytes == null) {
					result.error("INVALID_ARGUMENTS", "Backup data is missing", null)
					return@setMethodCallHandler
				}

				try {
					val resolver = contentResolver
					val values = ContentValues().apply {
						put(MediaStore.Downloads.DISPLAY_NAME, fileName)
						put(MediaStore.Downloads.MIME_TYPE, "text/csv")
						put(
							MediaStore.Downloads.RELATIVE_PATH,
							Environment.DIRECTORY_DOWNLOADS + "/tachocontrol_backups",
						)
						put(MediaStore.Downloads.IS_PENDING, 1)
					}

					val uri = resolver.insert(
						MediaStore.Downloads.EXTERNAL_CONTENT_URI,
						values,
					) ?: throw IllegalStateException("Could not create backup file")

					resolver.openOutputStream(uri)?.use { output ->
						output.write(bytes)
					} ?: throw IllegalStateException("Could not write backup file")

					values.clear()
					values.put(MediaStore.Downloads.IS_PENDING, 0)
					resolver.update(uri, values, null, null)
					removeOldBackups()
					result.success(null)
				} catch (error: Exception) {
					result.error("BACKUP_FAILED", error.message, null)
				}
			}
	}

	private fun removeOldBackups() {
		val resolver = contentResolver
		val collection = MediaStore.Downloads.EXTERNAL_CONTENT_URI
		val projection = arrayOf(
			MediaStore.Downloads._ID,
			MediaStore.Downloads.DISPLAY_NAME,
			MediaStore.Downloads.DATE_ADDED,
		)
		val backups = mutableListOf<Triple<Long, Long, String>>()

		resolver.query(
			collection,
			projection,
			"${MediaStore.Downloads.RELATIVE_PATH} = ? AND " +
				"${MediaStore.Downloads.DISPLAY_NAME} LIKE ?",
			arrayOf(
				Environment.DIRECTORY_DOWNLOADS + "/tachocontrol_backups/",
				"tachocontrol_backup_%",
			),
			null,
		)?.use { cursor ->
			val idIndex = cursor.getColumnIndexOrThrow(MediaStore.Downloads._ID)
			val nameIndex = cursor.getColumnIndexOrThrow(MediaStore.Downloads.DISPLAY_NAME)
			val dateIndex = cursor.getColumnIndexOrThrow(MediaStore.Downloads.DATE_ADDED)
			while (cursor.moveToNext()) {
				backups.add(
					Triple(
						cursor.getLong(idIndex),
						cursor.getLong(dateIndex),
						cursor.getString(nameIndex),
					),
				)
			}
		}

		backups.sortedByDescending { it.second }
			.drop(3)
			.forEach { oldBackup ->
				resolver.delete(
					ContentUris.withAppendedId(collection, oldBackup.first),
					null,
					null,
				)
			}
	}
}
