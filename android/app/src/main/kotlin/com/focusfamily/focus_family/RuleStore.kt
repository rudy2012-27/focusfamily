package com.focusfamily.focus_family

import android.content.Context
import android.content.Intent
import android.telecom.TelecomManager
import android.view.inputmethod.InputMethodManager
import org.json.JSONArray
import org.json.JSONObject
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Date
import java.util.Locale

/** Known websites for popular apps. Blocked automatically while the app is blocked. */
object DomainMap {
    val map: Map<String, List<String>> = mapOf(
        "com.google.android.youtube" to listOf("youtube.com", "youtu.be", "googlevideo.com", "ytimg.com", "youtube-nocookie.com"),
        "com.google.android.apps.youtube.music" to listOf("music.youtube.com"),
        "com.instagram.android" to listOf("instagram.com", "cdninstagram.com"),
        "com.facebook.katana" to listOf("facebook.com", "fb.com", "fbcdn.net"),
        "com.facebook.orca" to listOf("messenger.com"),
        "com.snapchat.android" to listOf("snapchat.com", "sc-cdn.net"),
        "com.zhiliaoapp.musically" to listOf("tiktok.com", "tiktokv.com", "tiktokcdn.com", "musical.ly"),
        "com.netflix.mediaclient" to listOf("netflix.com", "nflxvideo.net", "nflximg.net"),
        "com.twitter.android" to listOf("twitter.com", "x.com", "twimg.com"),
        "com.reddit.frontpage" to listOf("reddit.com", "redd.it", "redditstatic.com", "redditmedia.com"),
        "com.discord" to listOf("discord.com", "discordapp.com", "discord.gg"),
        "org.telegram.messenger" to listOf("telegram.org", "t.me"),
        "com.pinterest" to listOf("pinterest.com"),
        "tv.twitch.android.app" to listOf("twitch.tv", "ttvnw.net"),
        "com.roblox.client" to listOf("roblox.com", "rbxcdn.com"),
        "com.spotify.music" to listOf("spotify.com", "scdn.co"),
        "com.whatsapp" to listOf("whatsapp.com", "whatsapp.net"),
        "com.amazon.avod.thirdpartyclient" to listOf("primevideo.com"),
        "in.startv.hotstar" to listOf("hotstar.com")
    )
}

/** The current rules for this child phone. Updated live from Firestore and cached on disk. */
object RuleStore {
    private const val PREFS = "ff_prefs"

    @Volatile var lockedApps: Set<String> = emptySet()
    @Volatile var timedLocks: Map<String, Long> = emptyMap()
    @Volatile var dailyLimits: Map<String, Int> = emptyMap()
    @Volatile var allowances: Map<String, Long> = emptyMap()
    @Volatile var customDomains: Set<String> = emptySet()
    @Volatile var phoneLockedUntil: Long = 0L
    @Volatile var bedtimeEnabled: Boolean = false
    @Volatile var bedtimeStart: Int = 22 * 60
    @Volatile var bedtimeEnd: Int = 6 * 60
    @Volatile var usageMinutes: Map<String, Int> = emptyMap()
    @Volatile var essentials: Set<String> = emptySet()
    @Volatile private var loaded = false

    private fun pairList(raw: Any?, valueKey: String): Map<String, Long> {
        val out = HashMap<String, Long>()
        (raw as? List<*>)?.forEach { m ->
            if (m is Map<*, *>) {
                val pkg = m["pkg"] as? String
                val v = (m[valueKey] as? Number)?.toLong()
                if (pkg != null && v != null) out[pkg] = v
            }
        }
        return out
    }

    fun update(ctx: Context, data: Map<String, Any?>) {
        lockedApps = (data["lockedApps"] as? List<*>)?.filterIsInstance<String>()?.toSet() ?: emptySet()
        timedLocks = pairList(data["timedLocks"], "until")
        dailyLimits = pairList(data["dailyLimits"], "minutes").mapValues { it.value.toInt() }
        allowances = pairList(data["allowances"], "until")
        customDomains = (data["customDomains"] as? List<*>)?.filterIsInstance<String>()
            ?.map { it.lowercase().trim() }?.filter { it.isNotEmpty() }?.toSet() ?: emptySet()
        phoneLockedUntil = (data["phoneLockedUntil"] as? Number)?.toLong() ?: 0L
        val b = data["bedtime"] as? Map<*, *>
        bedtimeEnabled = b?.get("enabled") == true
        bedtimeStart = (b?.get("start") as? Number)?.toInt() ?: (22 * 60)
        bedtimeEnd = (b?.get("end") as? Number)?.toInt() ?: (6 * 60)
        save(ctx, data)
    }

    fun load(ctx: Context) {
        if (loaded) return
        loaded = true
        val s = ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getString("rules", null) ?: return
        try {
            @Suppress("UNCHECKED_CAST")
            val map = fromJson(JSONObject(s)) as? Map<String, Any?> ?: return
            update(ctx, map)
        } catch (_: Exception) {
        }
    }

    private fun save(ctx: Context, data: Map<String, Any?>) {
        try {
            val json = toJson(data)?.toString() ?: return
            ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().putString("rules", json).apply()
        } catch (_: Exception) {
        }
    }

    private fun toJson(v: Any?): Any? = when (v) {
        is Map<*, *> -> JSONObject().also { o ->
            v.forEach { (k, x) -> if (k is String) toJson(x)?.let { o.put(k, it) } }
        }
        is List<*> -> JSONArray().also { a -> v.forEach { x -> toJson(x)?.let { a.put(it) } } }
        is String, is Boolean, is Number -> v
        else -> null
    }

    private fun fromJson(v: Any?): Any? = when (v) {
        is JSONObject -> v.keys().asSequence().associateWith { fromJson(v.get(it)) }
        is JSONArray -> (0 until v.length()).map { fromJson(v.get(it)) }
        else -> v
    }

    fun refreshEssentials(ctx: Context) {
        val s = HashSet<String>()
        s.add(ctx.packageName)
        s.add("android")
        s.add("com.android.systemui")
        s.add("com.android.emergency")
        s.add("com.google.android.permissioncontroller")
        s.add("com.android.permissioncontroller")
        try {
            val pm = ctx.packageManager
            val home = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_HOME)
            pm.queryIntentActivities(home, 0).forEach { s.add(it.activityInfo.packageName) }
            (ctx.getSystemService(Context.TELECOM_SERVICE) as? TelecomManager)?.defaultDialerPackage?.let { s.add(it) }
            (ctx.getSystemService(Context.INPUT_METHOD_SERVICE) as? InputMethodManager)
                ?.enabledInputMethodList?.forEach { s.add(it.packageName) }
        } catch (_: Exception) {
        }
        essentials = s
    }

    private fun fmt(ms: Long): String = SimpleDateFormat("h:mm a", Locale.getDefault()).format(Date(ms))

    private fun bedtimeActive(now: Long): Boolean {
        if (!bedtimeEnabled) return false
        val c = Calendar.getInstance().apply { timeInMillis = now }
        val m = c.get(Calendar.HOUR_OF_DAY) * 60 + c.get(Calendar.MINUTE)
        return if (bedtimeStart <= bedtimeEnd) {
            m >= bedtimeStart && m < bedtimeEnd
        } else {
            m >= bedtimeStart || m < bedtimeEnd
        }
    }

    /** Returns a message if this app must be blocked right now, otherwise null. */
    fun blockReason(pkg: String, now: Long = System.currentTimeMillis()): String? {
        if (essentials.contains(pkg)) return null
        if (phoneLockedUntil > now) return "Your parent locked your phone until ${fmt(phoneLockedUntil)}."
        if (bedtimeActive(now)) return "It's quiet hours right now."
        if ((allowances[pkg] ?: 0L) > now) return null
        if (lockedApps.contains(pkg)) return "This app is locked by your parent."
        val t = timedLocks[pkg]
        if (t != null && t > now) return "This app is locked until ${fmt(t)}."
        val lim = dailyLimits[pkg]
        if (lim != null && (usageMinutes[pkg] ?: 0) >= lim) return "Today's limit of $lim minutes is used up."
        return null
    }

    private fun matches(host: String, domain: String): Boolean =
        host == domain || host.endsWith(".$domain")

    fun isDomainBlocked(hostRaw: String, now: Long = System.currentTimeMillis()): Boolean {
        val host = hostRaw.lowercase().trimEnd('.')
        if (host.isEmpty()) return false
        if (customDomains.any { matches(host, it) }) return true
        for ((pkg, domains) in DomainMap.map) {
            if (domains.any { matches(host, it) } && blockReason(pkg, now) != null) return true
        }
        return false
    }
}
