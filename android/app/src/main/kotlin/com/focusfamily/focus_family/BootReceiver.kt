package com.focusfamily.focus_family

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import androidx.core.content.ContextCompat

class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val uid = context.getSharedPreferences("ff_prefs", Context.MODE_PRIVATE).getString("childUid", null)
        if (uid != null) {
            try {
                ContextCompat.startForegroundService(context, Intent(context, SyncService::class.java))
            } catch (_: Exception) {
            }
        }
    }
}
