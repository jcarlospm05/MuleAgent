package com.muleagent.platform

import android.content.Intent
import android.net.Uri
import android.provider.OpenableColumns
import android.app.Activity
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.UUID
import java.util.concurrent.Executors

class IncomingReports(private val activity: Activity, messenger: BinaryMessenger) {
    private var channel: MethodChannel? = null
    private val worker = Executors.newSingleThreadExecutor()
    private var incomingError: String? = null
    private val inbox: File get() = File(activity.filesDir, "mule-inbox").apply { mkdirs() }

    init {
        channel = MethodChannel(messenger, "muleagent/incoming")
        channel!!.setMethodCallHandler { call, result ->
            when (call.method) {
                "peek" -> {
                    val error = incomingError
                    incomingError = null
                    if (error != null) result.error("incoming_file", error, null)
                    else result.success(inbox.listFiles()?.filter { it.extension == "mule" }
                        ?.minByOrNull { it.lastModified() }?.absolutePath)
                }
                "remove" -> {
                    val path = call.argument<String>("path")
                    val file = path?.let { File(it) }
                    if (file == null || file.parentFile?.canonicalFile != inbox.canonicalFile || file.extension != "mule") {
                        result.error("invalid_file", "Archivo recibido no válido.", null)
                    } else {
                        if (!file.exists() || file.delete()) result.success(null)
                        else result.error("remove_failed", "No se pudo retirar la copia temporal.", null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    @Suppress("DEPRECATION")
    fun receive(source: Intent?) {
        val uris: List<Uri> = when (source?.action) {
            Intent.ACTION_VIEW -> listOfNotNull(source.data)
            Intent.ACTION_SEND -> listOfNotNull(source.getParcelableExtra<Uri>(Intent.EXTRA_STREAM))
            Intent.ACTION_SEND_MULTIPLE -> source.getParcelableArrayListExtra<Uri>(Intent.EXTRA_STREAM) ?: emptyList()
            else -> emptyList()
        }
        if (uris.isEmpty()) return
        val multiple = source?.action == Intent.ACTION_SEND_MULTIPLE
        activity.intent = Intent(activity, activity.javaClass)
        worker.execute {
            val selected = if (multiple) uris.distinct().filter { isReportCandidate(it) } else uris
            if (selected.isEmpty()) {
                activity.runOnUiThread {
                    incomingError = "Comparte el archivo .mule del reporte. El PDF solo no contiene sus datos."
                    channel?.invokeMethod("available", null)
                }
            }
            selected.take(4).forEach { uri -> copyIncoming(uri) }
        }
    }

    private fun isReportCandidate(uri: Uri): Boolean {
        if (uri.scheme != "content") return false
        return try {
            var name = ""
            activity.contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { cursor ->
                if (cursor.moveToFirst()) name = cursor.getString(0) ?: ""
            }
            name.endsWith(".mule", ignoreCase = true) ||
                activity.contentResolver.getType(uri) in setOf("application/vnd.muleagent.report", "application/octet-stream", "application/x-mule", "application/mule")
        } catch (_: Exception) { false }
    }

    private fun copyIncoming(uri: Uri) {
        var temporary: File? = null
        try {
            require(uri.scheme == "content") { "Selecciona un archivo local desde WhatsApp o Archivos." }
            check((inbox.listFiles()?.count { it.extension == "mule" } ?: 0) < 3) {
                "Hay tres archivos pendientes. Impórtalos o descártalos antes de abrir otro."
            }
            val id = UUID.randomUUID().toString()
            val copy = File(inbox, "$id.part")
            temporary = copy
            activity.contentResolver.openInputStream(uri).use { input ->
                requireNotNull(input) { "No se pudo leer el archivo recibido." }
                copy.outputStream().use { output ->
                    val buffer = ByteArray(64 * 1024)
                    var size = 0L
                    while (true) {
                        val count = input.read(buffer)
                        if (count < 0) break
                        size += count
                        require(size <= 300L * 1024 * 1024) { "El archivo supera 300 MB." }
                        output.write(buffer, 0, count)
                    }
                    require(size > 0) { "El archivo está vacío." }
                }
            }
            check(copy.renameTo(File(inbox, "$id.mule"))) { "No se pudo guardar la copia recibida." }
        } catch (e: Exception) {
            temporary?.delete()
            activity.runOnUiThread { incomingError = e.message ?: "No se pudo recibir el archivo." }
        }
        activity.runOnUiThread { channel?.invokeMethod("available", null) }
    }

    fun close() {
        channel?.setMethodCallHandler(null)
        channel = null
        worker.shutdown()
    }
}
