package com.focusfamily.focus_family

import android.accessibilityservice.AccessibilityService
import android.content.Context
import android.content.Intent
import android.view.accessibility.AccessibilityEvent
import androidx.core.content.ContextCompat

/**
 * Watches which app (and which website in browsers) is on screen.
 * When something is blocked it sends the child to the home screen and shows the lock screen.
 */
class GuardAccessibilityService : AccessibilityService() {
    private var lastBlockedKey = ""
    private var lastBlockAt = 0L

    override fun onServiceConnected() {
        super.onServiceConnected()
        instance = this
        RuleStore.load(this)
        RuleStore.refreshEssentials(this)
        val uid = getSharedPreferences("ff_prefs", Context.MODE_PRIVATE).getString("childUid", null)
        if (uid != null) {
            try {
                ContextCompat.startForegroundService(this, Intent(this, SyncService::class.java))
            } catch (_: Exception) {
            }
        }
    }

    override fun onUnbind(intent: Intent?): Boolean {
        instance = null
        return super.onUnbind(intent)
    }

    override fun onInterrupt() {}

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        val e = event ?: return
        val pkg = e.packageName?.toString() ?: return
        if (pkg == packageName) return
        UsageTracker.refresh(this)
        if (e.eventType == AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED) {
            val reason = RuleStore.blockReason(pkg)
            if (reason != null) {
                block(pkg, reason)
                return
            }
        }
        val urlId = BROWSER_URL_IDS[pkg]
        if (urlId != null) checkBrowser(pkg, urlId)
    }

    /** Called on a timer and when rules change, so an open app is locked right away. */
    fun recheckForeground() {
        try {
            val root = rootInActiveWindow ?: return
            val pkg = root.packageName?.toString() ?: return
            if (pkg == packageName) return
            val reason = RuleStore.blockReason(pkg)
            if (reason != null) block(pkg, reason)
        } catch (_: Exception) {
        }
    }

    private fun checkBrowser(pkg: String, urlId: String) {
        try {
            val root = rootInActiveWindow ?: return
            if (root.packageName?.toString() != pkg) return
            val nodes = root.findAccessibilityNodeInfosByViewId(urlId)
            val text = nodes?.firstOrNull()?.text?.toString() ?: return
            val host = extractHost(text) ?: return
            if (RuleStore.isDomainBlocked(host)) {
                block("$pkg|web", "This website is blocked: $host")
            }
        } catch (_: Exception) {
        }
    }

    private fun extractHost(text: String): String? {
        var t = text.trim().lowercase()
        if (t.isEmpty() || t.contains(" ")) return null
        t = t.removePrefix("https://").removePrefix("http://")
        t = t.substringBefore('/').substringBefore('?').substringBefore('#').substringBefore(':')
        if (!t.contains('.')) return null
        return t.removePrefix("www.")
    }

    private fun block(key: String, reason: String) {
        val now = System.currentTimeMillis()
        if (key == lastBlockedKey && now - lastBlockAt < 1500) return
        lastBlockedKey = key
        lastBlockAt = now
        performGlobalAction(GLOBAL_ACTION_HOME)
        try {
            val i = Intent(this, LockActivity::class.java)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_NO_ANIMATION)
                .putExtra("pkg", key)
                .putExtra("reason", reason)
            startActivity(i)
        } catch (_: Exception) {
        }
    }

    companion object {
        @Volatile
        var instance: GuardAccessibilityService? = null

        val BROWSER_URL_IDS: Map<String, String> = mapOf(
            "com.android.chrome" to "com.android.chrome:id/url_bar",
            "com.chrome.beta" to "com.chrome.beta:id/url_bar",
            "com.brave.browser" to "com.brave.browser:id/url_bar",
            "com.microsoft.emmx" to "com.microsoft.emmx:id/url_bar",
            "com.sec.android.app.sbrowser" to "com.sec.android.app.sbrowser:id/location_bar_edit_text",
            "org.mozilla.firefox" to "org.mozilla.firefox:id/mozac_browser_toolbar_url_view",
            "com.opera.browser" to "com.opera.browser:id/url_field"
        )
    }
}
