package com.focusfamily.focus_family

import android.Manifest
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.net.VpnService
import android.os.Build
import android.provider.Settings
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var vpnResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "focusfamily/native")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "permissions" -> result.success(Perms.all(this))
                    "openUsageAccess" -> {
                        startActivity(Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS))
                        result.success(null)
                    }
                    "openAccessibility" -> {
                        startActivity(Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS))
                        result.success(null)
                    }
                    "openBattery" -> {
                        try {
                            startActivity(
                                Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS)
                                    .setData(Uri.parse("package:$packageName"))
                            )
                        } catch (_: Exception) {
                            startActivity(Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS))
                        }
                        result.success(null)
                    }
                    "requestNotifications" -> {
                        if (Build.VERSION.SDK_INT >= 33) {
                            requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 11)
                        }
                        result.success(null)
                    }
                    "requestVpn" -> {
                        val i = VpnService.prepare(this)
                        if (i == null) {
                            startService(Intent(this, GuardVpnService::class.java))
                            result.success(true)
                        } else {
                            vpnResult = result
                            startActivityForResult(i, REQ_VPN)
                        }
                    }
                    "startGuard" -> {
                        getSharedPreferences("ff_prefs", Context.MODE_PRIVATE).edit()
                            .putString("childUid", call.argument<String>("childUid"))
                            .putString("parentUid", call.argument<String>("parentUid"))
                            .putString("childName", call.argument<String>("childName"))
                            .apply()
                        try {
                            ContextCompat.startForegroundService(this, Intent(this, SyncService::class.java))
                        } catch (_: Exception) {
                        }
                        result.success(null)
                    }
                    "stopGuard" -> {
                        getSharedPreferences("ff_prefs", Context.MODE_PRIVATE).edit().clear().apply()
                        RuleStore.update(this, emptyMap())
                        stopService(Intent(this, SyncService::class.java))
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode == REQ_VPN) {
            val ok = resultCode == RESULT_OK
            if (ok) startService(Intent(this, GuardVpnService::class.java))
            vpnResult?.success(ok)
            vpnResult = null
        } else {
            @Suppress("DEPRECATION")
            super.onActivityResult(requestCode, resultCode, data)
        }
    }

    companion object {
        const val REQ_VPN = 4711
    }
}
