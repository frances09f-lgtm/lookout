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
            if (call.method == "findSource") {
                val start=call.argument<String>("url") ?: ""
                val uri=android.net.Uri.parse(start)
                if(uri.scheme!="https" || uri.host !in listOf("www.flipkart.com","www.amazon.in","in.bookmyshow.com"))result.error("invalid", "Unsupported source",null)
                else if(browserOpen)result.error("busy","A browser is already open",null)
                else {browserOpen=true;findSource(start,call.argument<String>("prompt") ?: "",result)}
                return@setMethodCallHandler
            }
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

    private fun findSource(start: String, prompt: String, result: MethodChannel.Result) {
        val web=WebView(this)
        web.settings.javaScriptEnabled=true
        web.settings.domStorageEnabled=true
        web.webViewClient=object: WebViewClient(){
            override fun shouldOverrideUrlLoading(view:WebView, request:android.webkit.WebResourceRequest):Boolean {
                val u=request.url
                return u.scheme!="https" || u.host !in listOf("www.flipkart.com","flipkart.com","www.amazon.in","amazon.in","in.bookmyshow.com")
            }
        }
        val layout=LinearLayout(this).apply{orientation=LinearLayout.VERTICAL}
        val note=TextView(this).apply{text="Find the exact model/storage/condition or cinema/date/show for: $prompt. Select the page, then confirm. This only picks a source, never buys or books. Background price reads may be blocked.";setPadding(20,20,20,20)}
        val use=Button(this).apply{text="Use this exact page"}
        layout.addView(note);layout.addView(web,LinearLayout.LayoutParams(-1,0,1f));layout.addView(use)
        var finished=false
        val dialog=AlertDialog.Builder(this).setTitle("Find watch source").setView(layout).setNegativeButton("Cancel",null).create()
        dialog.setOnDismissListener{browserOpen=false;if(!finished){finished=true;result.error("cancelled","Source selection cancelled",null)};web.stopLoading();web.destroy()}
        use.setOnClickListener{
            val url=web.url ?: "";val u=android.net.Uri.parse(url);val path=u.path ?: ""
            val exact=u.scheme=="https" && when(u.host){
                "www.flipkart.com","flipkart.com" -> Regex("/p/itm[a-zA-Z0-9]+").containsMatchIn(path)
                "www.amazon.in","amazon.in" -> Regex("/(dp|gp/product)/[A-Z0-9]{10}(/|$)").containsMatchIn(path)
                "in.bookmyshow.com" -> Regex("/seat-layout/[A-Za-z0-9]+/[A-Za-z0-9]+/[0-9]+/[0-9]{8}").containsMatchIn(path)
                else -> false
            }
            if(!exact){note.text="Open an exact product variant or dated cinema show. A search or movie listing cannot be used.";return@setOnClickListener}
            AlertDialog.Builder(this).setTitle("Confirm exact watch source").setMessage("${web.title ?: "Page"}\n$url\nCheck product variant or cinema/date/show before confirming. No purchase.")
                .setNegativeButton("Back",null).setPositiveButton("Use page"){_,_->finished=true;result.success(url);dialog.dismiss()}.show()
        }
        dialog.show();dialog.window?.setLayout(-1,(resources.displayMetrics.heightPixels*0.9).toInt());web.loadUrl(start)
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
