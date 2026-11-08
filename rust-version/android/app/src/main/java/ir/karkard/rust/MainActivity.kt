package ir.karkard.rust

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.provider.OpenableColumns
import android.webkit.JavascriptInterface
import android.webkit.ValueCallback
import android.webkit.WebChromeClient
import android.webkit.WebSettings
import android.webkit.WebView
import android.webkit.WebViewClient
import java.io.File

class MainActivity : Activity() {

    companion object {
        init {
            try {
                System.loadLibrary("karkard_core")
            } catch (e: UnsatisfiedLinkError) {
                e.printStackTrace()
            }
        }
    }

    external fun invokeCore(cmd: String, argsJson: String): String

    private lateinit var webView: WebView
    private var filePathCallback: ValueCallback<Array<Uri>>? = null
    private val FILE_CHOOSER_REQUEST_CODE = 1001

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        webView = WebView(this)
        setContentView(webView)

        val settings: WebSettings = webView.settings
        settings.javaScriptEnabled = true
        settings.domStorageEnabled = true
        settings.databaseEnabled = true
        settings.allowFileAccess = true
        settings.allowContentAccess = true
        settings.allowFileAccessFromFileURLs = true
        settings.allowUniversalAccessFromFileURLs = true
        settings.useWideViewPort = true
        settings.loadWithOverviewMode = true
        settings.textZoom = 100

        webView.addJavascriptInterface(AndroidBridge(this), "AndroidBridge")
        webView.webViewClient = object : WebViewClient() {}

        webView.webChromeClient = object : WebChromeClient() {
            override fun onConsoleMessage(consoleMessage: android.webkit.ConsoleMessage?): Boolean {
                android.util.Log.i("KarkardWebView", "${consoleMessage?.message()} -- line ${consoleMessage?.lineNumber()}")
                return true
            }

            override fun onShowFileChooser(
                webView: WebView?,
                filePathCallback: ValueCallback<Array<Uri>>?,
                fileChooserParams: FileChooserParams?
            ): Boolean {
                this@MainActivity.filePathCallback?.onReceiveValue(null)
                this@MainActivity.filePathCallback = filePathCallback
                launchFilePicker()
                return true
            }
        }

        webView.loadUrl("file:///android_asset/index.html")
    }

    fun launchFilePicker() {
        val intent = Intent(Intent.ACTION_GET_CONTENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "*/*"
        }
        startActivityForResult(
            Intent.createChooser(intent, "انتخاب فایل اکسل کارکرد"),
            FILE_CHOOSER_REQUEST_CODE
        )
    }

    private fun getFileName(uri: Uri): String {
        var name = "selected_excel.xlsx"
        try {
            val cursor = contentResolver.query(uri, null, null, null, null)
            cursor?.use {
                if (it.moveToFirst()) {
                    val idx = it.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                    if (idx >= 0) {
                        val str = it.getString(idx)
                        if (!str.isNullOrBlank()) {
                            name = str
                        }
                    }
                }
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }
        return name
    }

    override fun onBackPressed() {
        if (webView.canGoBack()) {
            webView.goBack()
        } else {
            super.onBackPressed()
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == FILE_CHOOSER_REQUEST_CODE) {
            if (resultCode == Activity.RESULT_OK && data != null) {
                val uri: Uri? = data.data ?: (
                    if (data.clipData != null && data.clipData!!.itemCount > 0)
                        data.clipData!!.getItemAt(0).uri
                    else null
                )

                if (uri != null) {
                    val displayName = getFileName(uri)
                    val targetFile = File(filesDir, "selected_import.xlsx")
                    try {
                        contentResolver.openInputStream(uri)?.use { input ->
                            targetFile.outputStream().use { output ->
                                input.copyTo(output)
                            }
                        }
                        val safePath = targetFile.absolutePath.replace("'", "\\'")
                        val safeName = displayName.replace("'", "\\'")
                        webView.post {
                            webView.evaluateJavascript(
                                "if (window.onAndroidFileSelected) window.onAndroidFileSelected('$safePath', '$safeName');",
                                null
                            )
                        }
                    } catch (e: Exception) {
                        e.printStackTrace()
                    }
                }

                val results = WebChromeClient.FileChooserParams.parseResult(resultCode, data) ?: (
                    if (uri != null) arrayOf(uri) else null
                )
                filePathCallback?.onReceiveValue(results)
                filePathCallback = null
            } else {
                filePathCallback?.onReceiveValue(null)
                filePathCallback = null
            }
        }
    }

    class AndroidBridge(private val activity: MainActivity) {
        @JavascriptInterface
        fun pickExcelFile() {
            activity.runOnUiThread {
                activity.launchFilePicker()
            }
        }

        @JavascriptInterface
        fun invoke(cmd: String, argsJson: String): String {
            return try {
                val res = activity.invokeCore(cmd, argsJson)
                android.util.Log.i("KarkardBridge", "cmd: $cmd -> len: ${res.length}")
                res
            } catch (e: Throwable) {
                android.util.Log.e("KarkardBridge", "Error calling $cmd", e)
                "{\"error\":\"${e.message?.replace("\"", "\\\"")}\"}"
            }
        }

        @JavascriptInterface
        fun getInternalFilesDir(): String {
            return activity.filesDir.absolutePath
        }
    }
}
