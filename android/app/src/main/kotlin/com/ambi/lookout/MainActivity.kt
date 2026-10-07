package com.ambi.lookout

import android.app.AlertDialog
import android.os.Handler
import android.os.Looper
import android.webkit.WebView
import android.webkit.WebViewClient
import android.widget.Button
import android.widget.LinearLayout
import android.widget.TextView
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import org.json.JSONTokener

class MainActivity : FlutterActivity() {
    private var browserOpen = false
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "lookout/browser").setMethodCallHandler { call, result ->
            if (call.method != "readBookMyShow") { result.notImplemented(); return@setMethodCallHandler }
            val url = call.argument<String>("url") ?: ""
            val api = call.argument<String>("api") ?: ""
            val pageUri = android.net.Uri.parse(url)
            val apiUri = android.net.Uri.parse(api)
            if (pageUri.scheme != "https" || pageUri.host != "in.bookmyshow.com" ||
                apiUri.scheme != "https" || apiUri.host != "in.bookmyshow.com" ||
                apiUri.path != "/api/movies-data/seatlayout/v1/primary") {
                result.error("invalid_source", "Invalid BookMyShow source", null)
            } else if (browserOpen) {
                result.error("busy", "A browser check is already open", null)
            } else {
                browserOpen = true
                openBrowser(url, api, result)
            }
        }
    }

    private fun openBrowser(url: String, api: String, result: MethodChannel.Result) {
        val web = WebView(this)
        web.settings.javaScriptEnabled = true
        web.settings.domStorageEnabled = true
        web.webViewClient = WebViewClient()
        val layout = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL }
        val status = TextView(this).apply {
            text = "Let the show page load. If asked, complete the site's verification. Tap Read prices when ready. This is a manual check, not background monitoring."
            setPadding(20, 20, 20, 20)
        }
        val read = Button(this).apply { text = "Read prices" }
        layout.addView(status)
        layout.addView(web, LinearLayout.LayoutParams(-1, 0, 1f))
        layout.addView(read)
        val dialog = AlertDialog.Builder(this).setTitle("BookMyShow price check")
            .setView(layout).setNegativeButton("Cancel", null).create()
        var finished = false
        var attempt = 0
        val handler = Handler(Looper.getMainLooper())
        dialog.setOnDismissListener {
            browserOpen = false
            if (!finished) { finished = true; result.error("cancelled", "Browser check cancelled", null) }
            web.stopLoading()
            web.destroy()
        }
        read.setOnClickListener {
            val current = android.net.Uri.parse(web.url ?: "")
            if (current.scheme != "https" || current.host != "in.bookmyshow.com") {
                status.text = "Return to the BookMyShow show page before reading prices."
                return@setOnClickListener
            }
            read.isEnabled = false
            status.text = "Reading ticket prices..."
            val token = ++attempt
            // One read request per explicit tap. No automatic retries or DOM price guessing.
            val quotedApi = org.json.JSONObject.quote(api)
            web.evaluateJavascript("window.__lookoutRead = null; fetch($quotedApi, {credentials:'include'}).then(async r => { window.__lookoutRead = JSON.stringify({status:r.status, body:await r.text()}); }).catch(() => {window.__lookoutRead = JSON.stringify({status:0, body:''});});", null)
            var checks = 0
            val poll = object : Runnable {
                override fun run() {
                    if (finished || attempt != token) return
                    if (++checks > 40) {
                        read.isEnabled = true
                        status.text = "Price read timed out. No value was checked."
                        return
                    }
                    web.evaluateJavascript("window.__lookoutRead", { raw ->
                        if (finished || attempt != token) return@evaluateJavascript
                        if (raw == null || raw == "null") {
                            handler.postDelayed(this, 500)
                        } else {
                            try {
                                val decoded = JSONTokener(raw).nextValue() as String
                                finished = true
                                result.success(decoded)
                                dialog.dismiss()
                            } catch (_: Exception) {
                                read.isEnabled = true
                                status.text = "Could not read a price response. No value was checked."
                            }
                        }
                    })
                }
            }
            handler.postDelayed(poll, 500)
        }
        dialog.show()
        dialog.window?.setLayout(-1, (resources.displayMetrics.heightPixels * 0.9).toInt())
        web.loadUrl(url)
    }
}
