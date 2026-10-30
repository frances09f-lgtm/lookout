package com.ambi.lookout_render

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.webkit.WebView
import android.webkit.WebViewClient
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.json.JSONTokener

/**
 * Headless on-device rendered reads. A detached WebView on the main thread
 * loads a public https page once and returns the rendered DOM. No user-agent
 * spoofing, no challenge solving: if the site asks for verification the read
 * returns what the site served and the caller fails honestly. Registered as a
 * plugin so BOTH the foreground engine and the background alarm engine get it.
 */
class LookoutRenderPlugin : FlutterPlugin, MethodChannel.MethodCallHandler {
    private lateinit var channel: MethodChannel
    private lateinit var context: Context
    private val main = Handler(Looper.getMainLooper())
    private var active = 0

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, "lookout/render")
        channel.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (call.method != "readRendered") { result.notImplemented(); return }
        val url = call.argument<String>("url") ?: ""
        val uri = android.net.Uri.parse(url)
        if (uri.scheme != "https" || uri.host.isNullOrEmpty()) {
            result.error("invalid_url", "Only public https pages can be read", null)
            return
        }
        if (active >= 3) { result.error("busy", "Rendered reads are busy", null); return }
        active++
        main.post { render(url, result) }
    }

    private fun render(url: String, result: MethodChannel.Result) {
        val web = WebView(context)
        var finished = false
        fun done(block: () -> Unit) {
            if (finished) return
            finished = true
            try { block() } finally {
                active--
                main.post { web.stopLoading(); web.destroy() }
            }
        }
        val timeout = Runnable {
            done { result.error("timeout", "Rendered read timed out", null) }
        }
        main.postDelayed(timeout, 25000)
        web.settings.javaScriptEnabled = true
        web.settings.domStorageEnabled = true
        web.webViewClient = object : WebViewClient() {
            var settled = false
            override fun onPageFinished(view: WebView, u: String) {
                if (settled || finished) return
                settled = true
                // Short settle so deferred price widgets render, then one read.
                main.postDelayed({
                    if (finished) return@postDelayed
                    view.evaluateJavascript(
                        "(function(){return document.documentElement.outerHTML;})()"
                    ) { raw ->
                        main.removeCallbacks(timeout)
                        if (raw == null || raw == "null") {
                            done { result.error("empty", "The page rendered no readable content", null) }
                            return@evaluateJavascript
                        }
                        try {
                            val body = JSONTokener(raw).nextValue() as String
                            if (body.length > 4000000) {
                                done { result.error("too_large", "Rendered page is too large to read", null) }
                            } else {
                                val finalUrl = view.url ?: u
                                val payload = org.json.JSONObject()
                                    .put("status", 200)
                                    .put("url", finalUrl)
                                    .put("body", body)
                                    .toString()
                                done { result.success(payload) }
                            }
                        } catch (_: Exception) {
                            done { result.error("empty", "The page rendered no readable content", null) }
                        }
                    }
                }, 2500)
            }
            override fun onReceivedError(
                view: WebView, request: android.webkit.WebResourceRequest,
                error: android.webkit.WebResourceError
            ) {
                if (request.isForMainFrame) {
                    main.removeCallbacks(timeout)
                    done {
                        result.error(
                            "load_failed",
                            "The page failed to load (${error.errorCode})",
                            null
                        )
                    }
                }
            }
        }
        web.loadUrl(url)
    }
}
