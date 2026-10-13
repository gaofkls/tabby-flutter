package com.tabby.tabby

import android.app.Activity
import android.app.KeyguardManager
import android.content.Context
import android.graphics.Color
import android.graphics.Typeface
import android.media.AudioAttributes
import android.media.MediaPlayer
import android.media.RingtoneManager
import android.os.Build
import android.os.Bundle
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.util.TypedValue
import android.view.Gravity
import android.view.WindowManager
import android.widget.Button
import android.widget.LinearLayout
import android.widget.TextView

/// 闹钟响铃页面。
///
/// 通知做不到的事由它来做：锁屏之上直接显示、循环播放系统闹钟铃声、
/// 持续震动，直到用户点「关闭」。
class TabbyAlarmActivity : Activity() {
    companion object {
        const val EXTRA_ID = "alarm_id"
        const val EXTRA_TITLE = "alarm_title"
        const val EXTRA_BODY = "alarm_body"
        const val EXTRA_AT = "alarm_at"
        private const val SNOOZE_MINUTES = 10
    }

    private var player: MediaPlayer? = null
    private var vibrator: Vibrator? = null

    private val titleText by lazy { intent.getStringExtra(EXTRA_TITLE) ?: "提醒" }
    private val bodyText by lazy { intent.getStringExtra(EXTRA_BODY) ?: "" }
    private val alarmId by lazy { intent.getIntExtra(EXTRA_ID, 0) }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setupWindow()
        setContentView(buildUi())
        startRinging()
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
            label("⏰", 44f, Color.WHITE).apply {
                setPadding(0, 0, 0, 24)
            },
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
        close.setOnClickListener { finish() }

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
            finish()
        }

        root.addView(close, LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT,
            LinearLayout.LayoutParams.WRAP_CONTENT,
        ))
        root.addView(snooze, LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT,
            LinearLayout.LayoutParams.WRAP_CONTENT,
        ).apply { topMargin = 16 })

        return root
    }

    private fun startRinging() {
        try {
            val uri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM)
                ?: RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION)
            val p = MediaPlayer()
            p.setDataSource(this, uri)
            p.setAudioAttributes(
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_ALARM)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                    .build(),
            )
            p.isLooping = true
            p.prepare()
            p.start()
            player = p
        } catch (e: Exception) {
            // 没有可用铃声资源就只震动
        }

        try {
            val v = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                (getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as VibratorManager)
                    .defaultVibrator
            } else {
                @Suppress("DEPRECATION")
                getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
            }
            val pattern = longArrayOf(0, 800, 500, 800, 500, 800)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                v.vibrate(VibrationEffect.createWaveform(pattern, 0))
            } else {
                @Suppress("DEPRECATION")
                v.vibrate(pattern, 0)
            }
            vibrator = v
        } catch (e: Exception) {
            // 没震动马达就算了
        }
    }

    private fun stopRinging() {
        try {
            player?.let {
                if (it.isPlaying) it.stop()
                it.release()
            }
        } catch (_: Exception) {
        }
        player = null
        try {
            vibrator?.cancel()
        } catch (_: Exception) {
        }
        vibrator = null
    }

    override fun onDestroy() {
        stopRinging()
        super.onDestroy()
    }
}
