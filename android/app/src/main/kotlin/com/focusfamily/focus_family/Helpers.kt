package com.focusfamily.focus_family

import android.app.AppOpsManager
import android.app.usage.UsageEvents
import android.app.usage.UsageStatsManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.VpnService
import android.os.Build
import android.os.PowerManager
import android.os.Process
import android.provider.Settings
import java.util.Calendar

object Perms {
    fun usageAccess(ctx: Context): Boolean {
        return try {
            val ops = ctx.getSystemService(Context.APP_OPS_SERVICE) as AppOpsManager
            val mode = if (Build.VERSION.SDK_INT >= 29) {
                ops.unsafeCheckOpNoThrow(AppOpsManager.OPSTR_GET_USAGE_STATS, Process.myUid(), ctx.packageName)
            } else {
                @Suppress("DEPRECATION")
                ops.checkOpNoThrow(AppOpsManager.OPSTR_GET_USAGE_STATS, Process.myUid(), ctx.packageName)
            }
            mode == AppOpsManager.MODE_ALLOWED
        } catch (_: Exception) {
            false
        }
    }

    fun accessibility(ctx: Context): Boolean {
        val enabled = Settings.Secure.getString(ctx.contentResolver, Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES) ?: ""
        return enabled.contains(ctx.packageName) && enabled.contains("GuardAccessibilityService")
    }

    fun vpn(ctx: Context): Boolean = try {
        VpnService.prepare(ctx) == null
    } catch (_: Exception) {
        false
    }

    fun battery(ctx: Context): Boolean = try {
        (ctx.getSystemService(Context.POWER_SERVICE) as PowerManager).isIgnoringBatteryOptimizations(ctx.packageName)
    } catch (_: Exception) {
        false
    }

    fun notifications(ctx: Context): Boolean =
        if (Build.VERSION.SDK_INT >= 33) {
            ctx.checkSelfPermission(android.Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED
        } else {
            true
        }

    fun all(ctx: Context): Map<String, Boolean> = mapOf(
        "usageAccess" to usageAccess(ctx),
        "accessibility" to accessibility(ctx),
        "vpn" to vpn(ctx),
        "vpnRunning" to GuardVpnService.running,
        "battery" to battery(ctx),
        "notifications" to notifications(ctx)
    )
}

object UsageTracker {
    @Volatile private var lastRefresh = 0L

    /** Recomputes minutes used today for every app (includes the app open right now). */
    fun refresh(ctx: Context, force: Boolean = false) {
        val now = System.currentTimeMillis()
        if (!force && now - lastRefresh < 15_000) return
        lastRefresh = now
        if (!Perms.usageAccess(ctx)) return
        try {
            val usm = ctx.getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
            val cal = Calendar.getInstance().apply {
                set(Calendar.HOUR_OF_DAY, 0)
                set(Calendar.MINUTE, 0)
                set(Calendar.SECOND, 0)
                set(Calendar.MILLISECOND, 0)
            }
            val events = usm.queryEvents(cal.timeInMillis, now)
            val e = UsageEvents.Event()
            val open = HashMap<String, Long>()
            val total = HashMap<String, Long>()
            while (events.hasNextEvent()) {
                events.getNextEvent(e)
                val pkg = e.packageName ?: continue
                @Suppress("DEPRECATION")
                when (e.eventType) {
                    UsageEvents.Event.MOVE_TO_FOREGROUND -> if (!open.containsKey(pkg)) open[pkg] = e.timeStamp
                    UsageEvents.Event.MOVE_TO_BACKGROUND -> {
                        val start = open.remove(pkg)
                        if (start != null) total[pkg] = (total[pkg] ?: 0L) + (e.timeStamp - start)
                    }
                }
            }
            for ((pkg, start) in open) {
                val dur = now - start
                if (dur in 0..(4 * 60 * 60 * 1000L)) total[pkg] = (total[pkg] ?: 0L) + dur
            }
            RuleStore.usageMinutes = total.mapValues { (it.value / 60_000L).toInt() }
        } catch (_: Exception) {
        }
    }
}

object AppCatalog {
    fun list(ctx: Context): List<Map<String, String>> {
        val pm = ctx.packageManager
        val i = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER)
        return pm.queryIntentActivities(i, 0)
            .map { it.activityInfo.packageName to it.loadLabel(pm).toString() }
            .filter { it.first != ctx.packageName }
            .distinctBy { it.first }
            .map { mapOf("pkg" to it.first, "name" to it.second) }
    }
}
