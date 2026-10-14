package com.tabby.tabby

import android.app.Activity
import android.app.KeyguardManager
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.graphics.Typeface
import android.os.Build
import android.os.Bundle
import android.util.TypedValue
import android.view.Gravity
import android.view.WindowManager
import android.widget.Button
import android.widget.LinearLayout
import android.widget.TextView

/// 闹钟响铃页面：只负责「看」和「关」，铃声交由 TabbyAlarmService 持有。
///
/// 这样分工是为了后台 / 锁屏也能响：就算系统不让我们弹界面，服务已经在响了；
/// 反过来只是为了点「关闭」，有没有界面都不影响铃声。
class TabbyAlarmActivity : Activity() {
    companion object {
        const val EXTRA_ID = "alarm_id"
        const val EXTRA_TITLE = "alarm_title"
        const val EXTRA_BODY = "alarm_body"
        const val EXTRA_AT = "alarm_at"
        private const val SNOOZE_MINUTES = 10

        fun intent(context: Context, id: Int, title: String, body: String) =
            Intent(context, TabbyAlarmActivity::class.java).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP)
                putExtra(EXTRA_ID, id)
                putExtra(EXTRA_TITLE, title)
                putExtra(EXTRA_BODY, body)
            }
    }

    private val alarmId by lazy { intent.getIntExtra(EXTRA_ID, 0) }
    private val titleText by lazy { intent.getStringExtra(EXTRA_TITLE) ?: "提醒" }
    private val bodyText by lazy { intent.getStringExtra(EXTRA_BODY) ?: "" }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setupWindow()
        setContentView(buildUi())
        // 幂等：服务已经在响的话不会重复再响一遍
        startService(TabbyAlarmService.intent(this, alarmId, titleText, bodyText))
    }

    private fun setupWindow() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
        } else {
            @Suppress("DEPRECATION")
            window.addFlags(
                WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                    WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON or
                    WindowManager.LayoutParams.FLAG_DISMISS_KEYGUARD,
            )
        }
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val km = getSystemService(Context.KEYGUARD_SERVICE) as KeyguardManager
            km.requestDismissKeyguard(this, null)
        }
    }

    private fun buildUi(): LinearLayout {
        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setBackgroundColor(Color.parseColor("#FF1C1B1F"))
            setPadding(56, 96, 56, 72)
            gravity = Gravity.CENTER_HORIZONTAL
        }

        fun label(text: String, sizeSp: Float, color: Int, bold: Boolean = false) =
            TextView(this).apply {
                this.text = text
                setTextColor(color)
                setTextSize(TypedValue.COMPLEX_UNIT_SP, sizeSp)
                gravity = Gravity.CENTER_HORIZONTAL
                if (bold) setTypeface(null, Typeface.BOLD)
            }

        root.addView(
            label("⏰", 44f, Color.WHITE).apply { setPadding(0, 0, 0, 24) },
        )
        root.addView(
            label(titleText, 26f, Color.WHITE, bold = true).apply {
                setPadding(0, 0, 0, 12)
            },
        )
        if (bodyText.isNotBlank()) {
            root.addView(
                label(bodyText, 16f, Color.parseColor("#FFC7C4CC")).apply {
                    setPadding(0, 0, 0, 40)
                },
            )
        }

        val close = Button(this).apply {
            text = "关闭"
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 17f)
            setBackgroundColor(Color.parseColor("#FF6750A4"))
            setTextColor(Color.WHITE)
        }
        close.setOnClickListener { stopEverything() }

        val snooze = Button(this).apply {
            text = "稍后 $SNOOZE_MINUTES 分钟"
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 15f)
            setBackgroundColor(Color.TRANSPARENT)
            setTextColor(Color.parseColor("#FFC7C4CC"))
        }
        snooze.setOnClickListener {
            TabbyAlarmScheduler.scheduleOne(
                this@TabbyAlarmActivity,
                AlarmSpec(
                    id = alarmId,
                    atMillis = System.currentTimeMillis() + SNOOZE_MINUTES * 60_000L,
                    title = titleText,
                    body = bodyText,
                ),
            )
            stopEverything()
        }

        root.addView(
            close,
            LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT,
            ),
        )
        root.addView(
            snooze,
            LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT,
            ).apply { topMargin = 16 },
        )

        return root
    }

    private fun stopEverything() {
        startService(
            TabbyAlarmService.intent(this, alarmId, titleText, bodyText, stop = true),
        )
        finish()
    }
}
