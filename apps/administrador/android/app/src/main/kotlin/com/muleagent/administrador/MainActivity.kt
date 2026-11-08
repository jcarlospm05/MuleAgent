package com.muleagent.administrador

import android.content.Intent
import android.net.Uri
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.UUID
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    private var channel: MethodChannel? = null
    private val worker = Executors.newSingleThreadExecutor()
    private var incomingError: String? = null
    private val inbox: File get() = File(filesDir, "mule-inbox").apply { mkdirs() }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "muleagent/incoming")
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

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        receiveIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        receiveIntent(intent)
    }

    @Suppress("DEPRECATION")
    private fun receiveIntent(source: Intent?) {
        val uri: Uri? = when (source?.action) {
            Intent.ACTION_VIEW -> source.data
            Intent.ACTION_SEND -> source.getParcelableExtra(Intent.EXTRA_STREAM) as? Uri
            else -> null
        }
        if (uri == null) return
        setIntent(Intent(this, MainActivity::class.java))
        worker.execute {
            var temporary: File? = null
            try {
                require(uri.scheme == "content") { "Selecciona un archivo local desde WhatsApp o Archivos." }
                check((inbox.listFiles()?.count { it.extension == "mule" } ?: 0) < 3) {
                    "Hay tres archivos pendientes. Impórtalos o descártalos antes de abrir otro."
                }
                val id = UUID.randomUUID().toString()
                val copy = File(inbox, "$id.part")
                temporary = copy
                contentResolver.openInputStream(uri).use { input ->
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
                runOnUiThread { incomingError = e.message ?: "No se pudo recibir el archivo." }
            }
            runOnUiThread { channel?.invokeMethod("available", null) }
        }
    }

    override fun onDestroy() {
        channel?.setMethodCallHandler(null)
        channel = null
        worker.shutdown()
        super.onDestroy()
    }
}
