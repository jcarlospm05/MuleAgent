package com.muleagent.platform

import android.Manifest
import android.app.Activity
import android.content.ContentUris
import android.content.ContentValues
import android.content.pm.PackageManager
import android.media.MediaScannerConnection
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream
import java.io.InputStream
import java.security.MessageDigest
import java.util.UUID
import java.util.concurrent.Executors

/** Publishes exact private originals to Downloads without broad storage access on Android 10+. */
class PublicReports(private val activity: Activity, messenger: BinaryMessenger) {
    private val channel = MethodChannel(messenger, "muleagent/public-reports")
    private val worker = Executors.newSingleThreadExecutor()
    private val registry = activity.getSharedPreferences("public-report-copies-v1", 0)
    private var permissionResult: MethodChannel.Result? = null
    private val permissionCode = 2804

    init {
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "prepare" -> {
                    if (hasPermission()) prepare(result)
                    else if (permissionResult != null) result.error("busy", "Ya se solicitó permiso de almacenamiento.", null)
                    else {
                        permissionResult = result
                        activity.requestPermissions(arrayOf(Manifest.permission.WRITE_EXTERNAL_STORAGE), permissionCode)
                    }
                }
                "publish" -> run(result) {
                    check(hasPermission()) { "Permite guardar archivos en Descargas y vuelve a intentarlo." }
                    val directory = call.argument<String>("directory") ?: error("Carpeta no válida.")
                    require(directory.startsWith("MuleAgent/") && directory.split('/').all { safeName(it) }) { "Carpeta no válida." }
                    val files = call.argument<List<Map<String, Any>>>("files") ?: error("Faltan archivos.")
                    require(files.isNotEmpty() && files.size <= 1002) { "Cantidad de archivos no válida." }
                    files.forEach { item ->
                        val source = File(item["source"] as String).canonicalFile
                        val privateRoot = File(activity.applicationInfo.dataDir).canonicalPath + File.separator
                        require(source.path.startsWith(privateRoot) && source.isFile) { "Falta un original privado." }
                        val name = item["name"] as String
                        val hash = item["sha256"] as String
                        val mime = item["mime"] as String
                        require(safeName(name) && hash.matches(Regex("[a-f0-9]{64}"))) { "Archivo no válido." }
                        require(source.length() in 1..(300L * 1024 * 1024)) { "Tamaño de archivo no válido." }
                        check(source.inputStream().use { digest(it) } == hash) { "El original no coincide con su huella." }
                        publish(directory, name, mime, hash) { source.inputStream() }
                    }
                    mapOf("folder" to "Descargas/$directory", "count" to files.size)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun safeName(name: String) = name.isNotBlank() && name != "." && name != ".." &&
        !name.contains('/') && !name.contains('\\') && name.none { it.code < 32 }

    private fun hasPermission() = Build.VERSION.SDK_INT >= 29 ||
        activity.checkSelfPermission(Manifest.permission.WRITE_EXTERNAL_STORAGE) == PackageManager.PERMISSION_GRANTED

    fun permissionResult(requestCode: Int): Boolean {
        if (requestCode != permissionCode) return false
        val result = permissionResult ?: return true
        permissionResult = null
        if (hasPermission()) prepare(result)
        else result.error("storage_permission", "Sin permiso de almacenamiento. El cierre queda guardado dentro de la app; reintenta la copia en Descargas.", null)
        return true
    }

    private fun prepare(result: MethodChannel.Result) = run(result) {
        val bytes = "MuleAgent: copias automáticas de cierres.\nPor fecha y etapa: PDF, archivo cifrado .mule y fotos originales.\nConserva estos archivos y respaldos fuera del teléfono.\n".toByteArray(Charsets.UTF_8)
        publish("MuleAgent", "LEEME.txt", "text/plain", digest(bytes.inputStream())) { bytes.inputStream() }
        "Descargas/MuleAgent"
    }

    private fun run(result: MethodChannel.Result, task: () -> Any) {
        worker.execute {
            try {
                val value = task()
                activity.runOnUiThread { result.success(value) }
            } catch (e: Exception) {
                activity.runOnUiThread { result.error("public_copy", e.message ?: "No se pudo guardar en Descargas.", null) }
            }
        }
    }

    private fun digest(input: InputStream): String {
        val hash = MessageDigest.getInstance("SHA-256")
        val buffer = ByteArray(64 * 1024)
        while (true) {
            val n = input.read(buffer)
            if (n < 0) break
            hash.update(buffer, 0, n)
        }
        return hash.digest().joinToString("") { "%02x".format(it.toInt() and 255) }
    }

    private fun publish(directory: String, name: String, mime: String, hash: String, open: () -> InputStream) {
        if (Build.VERSION.SDK_INT >= 29) publishScoped(directory, name, mime, hash, open)
        else publishLegacy(directory, name, mime, hash, open)
    }

    @android.annotation.TargetApi(29)
    private fun publishScoped(directory: String, name: String, mime: String, hash: String, open: () -> InputStream) {
        val resolver = activity.contentResolver
        val relative = "${Environment.DIRECTORY_DOWNLOADS}/$directory/"
        val key = MessageDigest.getInstance("SHA-256").digest("$relative$name".toByteArray())
            .joinToString("") { "%02x".format(it.toInt() and 255) }
        fun matches(uri: Uri): Boolean = try {
            resolver.openInputStream(uri)?.use { digest(it) == hash } ?: false
        } catch (_: Exception) { false }
        registry.getString(key, null)?.let { saved -> if (matches(Uri.parse(saved))) return }
        val collection = MediaStore.Downloads.EXTERNAL_CONTENT_URI
        resolver.query(collection, arrayOf(MediaStore.MediaColumns._ID),
            "${MediaStore.MediaColumns.RELATIVE_PATH}=? AND ${MediaStore.MediaColumns.DISPLAY_NAME}=? AND ${MediaStore.MediaColumns.IS_PENDING}=0",
            arrayOf(relative, name), null)?.use { cursor ->
            while (cursor.moveToNext()) {
                val uri = ContentUris.withAppendedId(collection, cursor.getLong(0))
                if (matches(uri)) {
                    registry.edit().putString(key, uri.toString()).apply()
                    return
                }
            }
        }
        val values = ContentValues().apply {
            put(MediaStore.MediaColumns.DISPLAY_NAME, name)
            put(MediaStore.MediaColumns.MIME_TYPE, mime)
            put(MediaStore.MediaColumns.RELATIVE_PATH, relative)
            put(MediaStore.MediaColumns.IS_PENDING, 1)
        }
        val uri = resolver.insert(collection, values) ?: error("No se pudo crear el archivo en Descargas.")
        try {
            resolver.openOutputStream(uri, "w").use { output ->
                requireNotNull(output) { "No se pudo escribir en Descargas." }
                open().use { it.copyTo(output, 64 * 1024) }
                output.flush()
            }
            check(matches(uri)) { "No se verificó la copia de $name." }
            check(resolver.update(uri, ContentValues().apply { put(MediaStore.MediaColumns.IS_PENDING, 0) }, null, null) == 1) { "No se pudo publicar $name." }
            registry.edit().putString(key, uri.toString()).apply()
        } catch (e: Exception) {
            resolver.delete(uri, null, null)
            throw e
        }
    }

    @Suppress("DEPRECATION")
    private fun publishLegacy(directory: String, name: String, mime: String, hash: String, open: () -> InputStream) {
        val folder = File(Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS), directory)
        check(folder.isDirectory || folder.mkdirs()) { "No se pudo crear la carpeta en Descargas." }
        var target = File(folder, name)
        if (target.exists()) {
            if (target.inputStream().use { digest(it) } == hash) return
            target = File(folder, "${name.substringBeforeLast('.', name)}_recuperado_${UUID.randomUUID().toString().take(8)}.${name.substringAfterLast('.', "bin")}")
        }
        val temporary = File(folder, ".${UUID.randomUUID()}.tmp")
        try {
            FileOutputStream(temporary).use { output ->
                open().use { it.copyTo(output, 64 * 1024) }
                output.fd.sync()
            }
            check(temporary.inputStream().use { digest(it) } == hash) { "No se verificó la copia de $name." }
            check(temporary.renameTo(target)) { "No se pudo guardar $name." }
            MediaScannerConnection.scanFile(activity, arrayOf(target.path), arrayOf(mime), null)
        } finally { temporary.delete() }
    }

    fun close() {
        channel.setMethodCallHandler(null)
        permissionResult?.error("activity_closed", "Se cerró la pantalla de permisos. Reintenta el guardado.", null)
        permissionResult = null
        worker.shutdown()
    }
}
