package com.tabby.tabby

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.media.AudioAttributes
import android.media.MediaPlayer
import android.media.RingtoneManager
import android.os.Build
import android.os.IBinder
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.util.Log

/// 真正负责「响」的地方。
///
/// 为什么不放在 Activity 里：App 退到后台或锁屏时，系统不一定允许我们直接弹 Activity，
/// 而没有界面也必须能把人叫醒。所以铃声和震动交给前台服务持有——它不依赖界面是否可见，
/// 并且顺带带出一条挂了 fullScreenIntent 的通知，由系统决定是否把响铃页拉到最前面。
class TabbyAlarmService : Service() {
    companion object {
        const val ACTION_START = "com.tabby.tabby.ALARM_START"
        const val ACTION_STOP = "com.tabby.tabby.ALARM_STOP"
        const val CHANNEL_ID = "tabby_alarm_ringing"
        const val NOTIFICATION_ID = 910_001

        const val EXTRA_ID = "alarm_id"
        const val EXTRA_TITLE = "alarm_title"
        const val EXTRA_BODY = "alarm_body"

        private const val TAG = "TabbyAlarmService"

        fun intent(
            context: Context,
            id: Int,
            title: String,
            body: String,
            stop: Boolean = false,
        ) = Intent(context, TabbyAlarmService::class.java).apply {
            action = if (stop) ACTION_STOP else ACTION_START
            putExtra(EXTRA_ID, id)
            putExtra(EXTRA_TITLE, title)
            putExtra(EXTRA_BODY, body)
        }
    }

    private var player: MediaPlayer? = null
    private var vibrator: Vibrator? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            stopRinging()
            stopSelfSafely()
            return START_NOT_STICKY
        }

        val id = intent?.getIntExtra(EXTRA_ID, 0) ?: 0
        val title = intent?.getStringExtra(EXTRA_TITLE) ?: "提醒"
        val body = intent?.getStringExtra(EXTRA_BODY) ?: ""

        ensureChannel()
        try {
            startForeground(NOTIFICATION_ID, buildNotification(this, id, title, body))
        } catch (e: Exception) {
            // 极少数情况下前台服务起不来，但铃声还是得响
            Log.w(TAG, "前台服务起不来，退化为无通知响铃", e)
        }
        startRinging()
        return START_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        stopRinging()
        super.onDestroy()
    }

    private fun startRinging() {
        if (player != null) return

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
            Log.w(TAG, "播放闹钟铃声失败", e)
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
            Log.w(TAG, "震动失败", e)
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

    private fun stopSelfSafely() {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                stopForeground(STOP_FOREGROUND_REMOVE)
            } else {
                @Suppress("DEPRECATION")
                stopForeground(true)
            }
        } catch (_: Exception) {
        }
        stopSelf()
    }

    private fun ensureChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (nm.getNotificationChannel(CHANNEL_ID) != null) return
        val channel = NotificationChannel(
            CHANNEL_ID,
            "正在响铃",
            NotificationManager.IMPORTANCE_HIGH,
        ).apply {
            description = "闹钟到点响铃时的常驻通知"
            // 声音和震动都由服务自己放，通知不再重复出声
            setSound(null, null)
            enableVibration(false)
        }
        nm.createNotificationChannel(channel)
    }

    private fun pFlags(): Int {
        var flags = PendingIntent.FLAG_UPDATE_CURRENT
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            flags = flags or PendingIntent.FLAG_IMMUTABLE
        }
        return flags
    }

    private fun buildNotification(
        context: Context,
        id: Int,
        title: String,
        body: String,
    ): Notification {
        val contentIntent = PendingIntent.getActivity(
            context,
            id + 600_000,
            TabbyAlarmActivity.intent(context, id, title, body),
            pFlags(),
        )
        // fullScreenIntent：系统在锁屏 / 熄屏时会替我们把响铃页拉到最前面，
        // 这是 Android 允许的从后台弹界面的正规通道。
        val fullScreenIntent = PendingIntent.getActivity(
            context,
            id + 700_000,
            TabbyAlarmActivity.intent(context, id, title, body),
            pFlags(),
        )
        val stopIntent = PendingIntent.getService(
            context,
            id + 800_000,
            intent(context, id, title, body, stop = true),
            pFlags(),
        )

        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(context, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(context)
        }

        builder
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle(title)
            .setContentText(body)
            .setCategory(Notification.CATEGORY_ALARM)
            .setOngoing(true)
            .setAutoCancel(false)
            .setContentIntent(contentIntent)
            .setFullScreenIntent(fullScreenIntent, true)
            .addAction(
                Notification.Action.Builder(
                    R.mipmap.ic_launcher,
                    "关闭",
                    stopIntent,
                ).build(),
            )

        @Suppress("DEPRECATION")
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            builder.setPriority(Notification.PRIORITY_MAX)
        }
        // 声音与震动都由服务自己放。通知不再出声靠的是渠道本身没配铃声
        // （见 ensureChannel 里的 setSound(null, null)），所以这里不用再处理。
        return builder.build()
    }
}
