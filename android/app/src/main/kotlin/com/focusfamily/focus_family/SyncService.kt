package com.focusfamily.focus_family

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.net.VpnService
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import com.google.firebase.firestore.FieldValue
import com.google.firebase.firestore.FirebaseFirestore
import com.google.firebase.firestore.ListenerRegistration
import com.google.firebase.firestore.SetOptions
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * Foreground service on the child's phone. Listens to the parent's rules in real time,
 * measures usage, and reports status back to the parent.
 */
class SyncService : Service() {
    private val handler = Handler(Looper.getMainLooper())
    private var rulesReg: ListenerRegistration? = null
    private var running = false
    private var lastUsageHash = 0
    private var lastUsageUpload = 0L
    private var lastHeartbeat = 0L
    private var lastApps = 0L

    private val tick = object : Runnable {
        override fun run() {
            try {
                doTick()
            } catch (_: Exception) {
            }
            if (running) handler.postDelayed(this, 30_000)
        }
    }

    override fun onCreate() {
        super.onCreate()
        RuleStore.load(this)
        RuleStore.refreshEssentials(this)
        val n = buildNotification()
        if (Build.VERSION.SDK_INT >= 34) {
            startForeground(NOTIF_ID, n, ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE)
        } else {
            startForeground(NOTIF_ID, n)
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val prefs = getSharedPreferences("ff_prefs", Context.MODE_PRIVATE)
        val uid = prefs.getString("childUid", null)
        if (uid == null) {
            stopSelf()
            return START_NOT_STICKY
        }
        if (rulesReg == null) {
            rulesReg = FirebaseFirestore.getInstance().collection("rules").document(uid)
                .addSnapshotListener { snap, err ->
                    if (err != null || snap == null) return@addSnapshotListener
                    RuleStore.update(this, snap.data ?: emptyMap())
                    GuardAccessibilityService.instance?.recheckForeground()
                }
        }
        startVpnIfPermitted()
        if (!running) {
            running = true
            handler.post(tick)
        }
        return START_STICKY
    }

    private fun startVpnIfPermitted() {
        try {
            if (!GuardVpnService.running && VpnService.prepare(this) == null) {
                startService(Intent(this, GuardVpnService::class.java))
            }
        } catch (_: Exception) {
        }
    }

    private fun doTick() {
        val uid = getSharedPreferences("ff_prefs", Context.MODE_PRIVATE).getString("childUid", null) ?: return
        RuleStore.refreshEssentials(this)
        UsageTracker.refresh(this, true)
        GuardAccessibilityService.instance?.recheckForeground()
        startVpnIfPermitted()

        val now = System.currentTimeMillis()
        val db = FirebaseFirestore.getInstance()

        val hash = RuleStore.usageMinutes.hashCode()
        if (hash != lastUsageHash && now - lastUsageUpload > 60_000) {
            val entries = RuleStore.usageMinutes.filter { it.value > 0 }
                .map { mapOf("pkg" to it.key, "min" to it.value) }
            db.collection("usage").document(uid).set(
                mapOf(
                    "date" to SimpleDateFormat("yyyy-MM-dd", Locale.US).format(Date()),
                    "entries" to entries,
                    "updatedAt" to FieldValue.serverTimestamp()
                )
            )
            lastUsageHash = hash
            lastUsageUpload = now
        }

        if (now - lastHeartbeat > 120_000) {
            db.collection("devices").document(uid).set(
                mapOf(
                    "heartbeat" to FieldValue.serverTimestamp(),
                    "model" to Build.MODEL,
                    "status" to Perms.all(this)
                ),
                SetOptions.merge()
            )
            lastHeartbeat = now
        }

        if (now - lastApps > 30 * 60_000L) {
            db.collection("devices").document(uid).set(
                mapOf("apps" to AppCatalog.list(this), "appsUpdatedAt" to FieldValue.serverTimestamp()),
                SetOptions.merge()
            )
            lastApps = now
        }
    }

    private fun buildNotification(): Notification {
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= 26) {
            nm.createNotificationChannel(
                NotificationChannel(CHANNEL, "FocusFamily protection", NotificationManager.IMPORTANCE_LOW)
            )
        }
        val open = PendingIntent.getActivity(
            this, 0,
            packageManager.getLaunchIntentForPackage(packageName),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )
        val b = if (Build.VERSION.SDK_INT >= 26) Notification.Builder(this, CHANNEL) else Notification.Builder(this)
        return b.setContentTitle("FocusFamily is active")
            .setContentText("Your parent's limits are running on this phone.")
            .setSmallIcon(android.R.drawable.ic_lock_lock)
            .setContentIntent(open)
            .setOngoing(true)
            .build()
    }

    override fun onDestroy() {
        running = false
        handler.removeCallbacksAndMessages(null)
        rulesReg?.remove()
        rulesReg = null
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    companion object {
        const val CHANNEL = "ff_guard"
        const val NOTIF_ID = 1001
    }
}
