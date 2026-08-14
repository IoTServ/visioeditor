package cloud.iothub.visioeditor

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.provider.OpenableColumns
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.UUID

class MainActivity : FlutterActivity() {
    private val fileChannelName = "visioeditor/files"
    private var fileChannel: MethodChannel? = null
    private var dartIsReady = false
    private val pendingPaths = mutableListOf<String>()
    private var pickerResult: MethodChannel.Result? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        handleOpenIntent(intent)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        fileChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            fileChannelName,
        ).also { channel ->
            channel.setMethodCallHandler { call, result ->
                when (call.method) {
                    "ready" -> {
                        dartIsReady = true
                        flushPendingPaths()
                        result.success(null)
                    }
                    "pickVisioFile" -> startVisioPicker(result)
                    else -> result.notImplemented()
                }
            }
        }
        flushPendingPaths()
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleOpenIntent(intent)
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != visioPickerRequestCode) return
        val result = pickerResult ?: return
        pickerResult = null
        if (resultCode != Activity.RESULT_OK) {
            result.success(null)
            return
        }
        val path = data?.data?.let(::copyToReadablePath)
        if (path == null) {
            result.error("visio_file_unreadable", "The selected Visio file could not be read.", null)
        } else {
            result.success(path)
        }
    }

    private fun startVisioPicker(result: MethodChannel.Result) {
        if (pickerResult != null) {
            result.error("visio_picker_active", "A Visio file picker is already open.", null)
            return
        }
        pickerResult = result
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "*/*"
            putExtra(Intent.EXTRA_MIME_TYPES, visioMimeTypes)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        try {
            startActivityForResult(intent, visioPickerRequestCode)
        } catch (error: Exception) {
            pickerResult = null
            result.error("visio_picker_unavailable", error.message, null)
        }
    }

    private fun handleOpenIntent(intent: Intent?) {
        if (intent?.action != Intent.ACTION_VIEW) return
        val uri = intent.data ?: return
        val path = copyToReadablePath(uri) ?: return
        pendingPaths.add(path)
        flushPendingPaths()
    }

    private fun flushPendingPaths() {
        val channel = fileChannel ?: return
        if (!dartIsReady || pendingPaths.isEmpty()) return
        val paths = pendingPaths.toList()
        pendingPaths.clear()
        channel.invokeMethod("openFiles", paths)
    }

    /**
     * Content-provider grants usually last only for the inbound intent. Copy
     * the document into app cache before handing a normal readable path to
     * Dart. Plain file URIs can be used directly.
     */
    private fun copyToReadablePath(uri: Uri): String? {
        if (uri.scheme == "file") return uri.path
        if (uri.scheme != "content") return null

        val extension = extensionForMimeType(uri)
        val queriedName = queryDisplayName(uri)
        val displayName = when {
            queriedName == null -> "document.$extension"
            queriedName.matches(Regex(".*\\.(vsd|vss|vst|vdx|vsx|vtx|vsdx|vsdm|vstx|vstm|vssx|vssm|drawio)$", RegexOption.IGNORE_CASE)) -> queriedName
            else -> "$queriedName.$extension"
        }
        val safeName = displayName.replace(Regex("[^A-Za-z0-9._ -]"), "_")
        val directory = File(cacheDir, "opened-docs").apply { mkdirs() }
        val destination = File(directory, "${UUID.randomUUID()}-$safeName")
        return try {
            contentResolver.openInputStream(uri)?.use { input ->
                destination.outputStream().use(input::copyTo)
            } ?: return null
            destination.path
        } catch (_: Exception) {
            destination.delete()
            null
        }
    }

    private fun queryDisplayName(uri: Uri): String? = try {
        contentResolver.query(
            uri,
            arrayOf(OpenableColumns.DISPLAY_NAME),
            null,
            null,
            null,
        )?.use { cursor ->
            if (!cursor.moveToFirst()) return@use null
            val index = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
            if (index < 0) null else cursor.getString(index)
        }
    } catch (_: Exception) {
        null
    }

    private fun extensionForMimeType(uri: Uri): String =
        when (contentResolver.getType(uri)?.lowercase()) {
            "application/vnd.visio" -> "vsd"
            "application/vnd.ms-visio.viewer" -> "vdx"
            "application/vnd.ms-visio.drawing" -> "vsdx"
            "application/vnd.ms-visio.drawing.macroenabled.12",
            "application/vnd.ms-visio.drawing.macroenabled" -> "vsdm"
            "application/vnd.ms-visio.template" -> "vstx"
            "application/vnd.ms-visio.template.macroenabled.12",
            "application/vnd.ms-visio.template.macroenabled" -> "vstm"
            "application/vnd.ms-visio.stencil" -> "vssx"
            "application/vnd.ms-visio.stencil.macroenabled.12",
            "application/vnd.ms-visio.stencil.macroenabled" -> "vssm"
            "application/vnd.jgraph.mxfile" -> "drawio"
            else -> "vsdx"
        }

    companion object {
        private const val visioPickerRequestCode = 47031
        private val visioMimeTypes = arrayOf(
            "application/vnd.visio",
            "application/vnd.ms-visio.viewer",
            "application/vnd.ms-visio.drawing",
            "application/vnd.ms-visio.drawing.macroEnabled.12",
            "application/vnd.ms-visio.template",
            "application/vnd.ms-visio.template.macroEnabled.12",
            "application/vnd.ms-visio.stencil",
            "application/vnd.ms-visio.stencil.macroEnabled.12",
            "application/vnd.jgraph.mxfile",
            "application/xml",
            "text/xml",
            // Providers commonly report OPC packages or unknown office files
            // generically. Dart validates the returned filename extension.
            "application/zip",
            "application/octet-stream",
        )
    }
}
