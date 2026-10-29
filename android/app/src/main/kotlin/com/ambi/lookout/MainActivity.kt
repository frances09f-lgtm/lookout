package com.ambi.lookout

import android.app.AlarmManager
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import androidx.core.content.FileProvider
import java.io.File

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
        registerUpdateChannel(flutterEngine)
        registerAlarmChannel(flutterEngine)
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
    // In-app update: APK is downloaded over HTTP in Dart and handed to the
    // Android package installer here. The only system steps are the one-time
    // "install unknown apps" toggle and the installer confirm, both owned by
    // Android. Also serves the app's versionName and cache dir so the Dart
    // side needs no extra plugins.
    private fun registerUpdateChannel(flutterEngine: FlutterEngine) {
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "app/update")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "appVersion" -> result.success(
                        packageManager.getPackageInfo(packageName, 0).versionName
                    )
                    "cacheDir" -> result.success(cacheDir.absolutePath)
                    "canInstall" -> result.success(
                        Build.VERSION.SDK_INT < Build.VERSION_CODES.O ||
                            packageManager.canRequestPackageInstalls()
                    )
                    "openInstallSettings" -> {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            startActivity(
                                Intent(
                                    Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                                    Uri.parse("package:$packageName")
                                ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            )
                        }
                        result.success(null)
                    }
                    "installApk" -> {
                        val path = call.argument<String>("path")
                        val file = path?.let { File(it) }
                        if (file == null || !file.exists()) {
                            result.error("no_apk", "APK not found: $path", null)
                            return@setMethodCallHandler
                        }
                        val uri = FileProvider.getUriForFile(
                            this,
                            "$packageName.updateprovider",
                            file
                        )
                        val intent = Intent(Intent.ACTION_VIEW)
                            .setDataAndType(
                                uri,
                                "application/vnd.android.package-archive"
                            )
                            .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        startActivity(intent)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }
    // Exact-alarm engine support: permission state + system settings
    // deep-links the Dart side cannot reach through the plugins.
    private fun registerAlarmChannel(flutterEngine: FlutterEngine) {
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "lookout/alarms")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "canScheduleExactAlarms" -> {
                        val ok = Build.VERSION.SDK_INT < Build.VERSION_CODES.S ||
                            (getSystemService(Context.ALARM_SERVICE) as AlarmManager)
                                .canScheduleExactAlarms()
                        result.success(ok)
                    }
                    "openExactAlarmSettings" -> {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                            startActivity(
                                Intent(
                                    Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM,
                                    Uri.parse("package:$packageName")
                                ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            )
                        }
                        result.success(null)
                    }
                    "isIgnoringBatteryOptimizations" -> {
                        val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
                        result.success(pm.isIgnoringBatteryOptimizations(packageName))
                    }
                    "openBatteryOptimizationSettings" -> {
                        startActivity(
                            Intent(
                                Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS,
                                Uri.parse("package:$packageName")
                            ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        )
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

}
