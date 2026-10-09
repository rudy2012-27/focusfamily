package com.focusfamily.focus_family

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.graphics.Typeface
import android.os.Bundle
import android.view.Gravity
import android.view.ViewGroup
import android.widget.Button
import android.widget.LinearLayout
import android.widget.TextView
import android.widget.Toast
import com.google.firebase.firestore.FieldValue
import com.google.firebase.firestore.FirebaseFirestore

/** The screen the child sees when something is blocked. */
class LockActivity : Activity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        render()
    }

    override fun onNewIntent(intent: Intent?) {
        super.onNewIntent(intent)
        setIntent(intent)
        render()
    }

    private fun appLabel(pkg: String): String = try {
        val pm = packageManager
        pm.getApplicationLabel(pm.getApplicationInfo(pkg, 0)).toString()
    } catch (_: Exception) {
        pkg
    }

    private fun dp(v: Int): Int = (v * resources.displayMetrics.density).toInt()

    private fun render() {
        val key = intent.getStringExtra("pkg") ?: ""
        val reason = intent.getStringExtra("reason") ?: "This is locked."
        val isWeb = key.endsWith("|web")
        val pkg = key.substringBefore('|')
        val name = if (isWeb) "Website blocked" else appLabel(pkg)

        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
            setBackgroundColor(Color.parseColor("#12332D"))
            setPadding(dp(32), dp(32), dp(32), dp(32))
            layoutParams = ViewGroup.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT)
        }
        fun text(t: String, size: Float, bold: Boolean = false) = TextView(this).apply {
            text = t
            textSize = size
            setTextColor(Color.WHITE)
            gravity = Gravity.CENTER
            if (bold) setTypeface(typeface, Typeface.BOLD)
            setPadding(0, dp(8), 0, dp(8))
        }
        root.addView(text("\uD83D\uDD12", 56f))
        root.addView(text(name, 24f, true))
        root.addView(text(reason, 16f))

        val home = Button(this).apply {
            text = "Go to home screen"
            setOnClickListener { goHome() }
        }
        root.addView(home)

        if (!isWeb) {
            val ask = Button(this).apply {
                text = "Ask parent for more time"
                setOnClickListener { sendRequest(pkg, name) }
            }
            root.addView(ask)
        }
        setContentView(root)
    }

    private fun sendRequest(pkg: String, name: String) {
        val p = getSharedPreferences("ff_prefs", Context.MODE_PRIVATE)
        val uid = p.getString("childUid", null)
        val parent = p.getString("parentUid", null)
        if (uid == null || parent == null) return
        FirebaseFirestore.getInstance().collection("requests").add(
            hashMapOf(
                "childUid" to uid,
                "parentUid" to parent,
                "childName" to (p.getString("childName", "") ?: ""),
                "pkg" to pkg,
                "appName" to name,
                "status" to "pending",
                "createdAt" to FieldValue.serverTimestamp()
            )
        )
        Toast.makeText(this, "Request sent to your parent", Toast.LENGTH_LONG).show()
    }

    private fun goHome() {
        startActivity(
            Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_HOME).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        )
        finish()
    }

    @Deprecated("Deprecated in Java")
    override fun onBackPressed() {
        goHome()
    }
}
