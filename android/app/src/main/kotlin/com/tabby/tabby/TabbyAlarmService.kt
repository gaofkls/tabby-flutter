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
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.util.Log
import java.text.SimpleDateFormat
import java.util.Locale

/// 真正负责「响」的地方，也负责「响多久」和「什么时候再响一次」。
///
/// 为什么不放在 Activity 里：App 退到后台或锁屏时，系统不一定允许我们直接弹 Activity，
/// 而没有界面也必须能把人叫醒。所以铃声和震动交给前台服务持有——它不依赖界面是否可见，
/// 并且顺带带出一条挂了 fullScreenIntent 的通知，由系统决定是否把响铃页拉到最前面。
///
/// 响铃节奏（可在设置里改）：
///   响 ringMinutes 分钟 → 自动停 → 隔 snoozeMinutes 分钟 → 再响一轮，
///   最多 repeatTimes 轮（0 表示一直重复到手动关闭）。
/// 每一轮之间服务会退出前台，改由 AlarmManager 负责叫醒，避免长时间占着前台服务。
class TabbyAlarmService : Service() {
    companion object {
        const val ACTION_START = "com.tabby.tabby.ALARM_START"
        const val ACTION_STOP = "com.tabby.tabby.ALARM_STOP"
        const val CHANNEL_ID = "tabby_alarm_ringing"
        const val CHANNEL_WAITING_ID = "tabby_alarm_waiting"
        const val NOTIFICATION_ID = 910_001

        const val EXTRA_ID = "alarm_id"
        const val EXTRA_TITLE = "alarm_title"
        const val EXTRA_BODY = "alarm_body"
        const val EXTRA_ROUND = "alarm_round"

        private const val TAG = "TabbyAlarmService"

        fun intent(
            context: Context,
            id: Int,
            title: String,
            body: String,
            round: Int = 1,
            stop: Boolean = false,
        ) = Intent(context, TabbyAlarmService::class.java).apply {
            action = if (stop) ACTION_STOP else ACTION_START
            putExtra(EXTRA_ID, id)
            putExtra(EXTRA_TITLE, title)
            putExtra(EXTRA_BODY, body)
            putExtra(EXTRA_ROUND, round)
        }

        /// 立刻停止响铃，并取消还没到的后续轮次（通知上的「关闭」走这条路）。
        ///
        /// 注意：这里用 [Context.stopService] 而不是 startForegroundService——
        /// 之前用 startForegroundService 下发 ACTION_STOP 时，如果服务当时没在运行，
        /// Android 8+ 会要求新拉起的服务必须在 5 秒内调用 startForeground()，
        /// 否则抛出 RemoteServiceException 直接杀掉整个进程。
        /// 而我们的 STOP 分支恰恰不会调用 startForeground()，于是每次切到「系统通知」模式
        /// （或任何会触发 cancelAll 的路径）都会崩，且因模式已持久化而每次启动都崩、进不去。
        /// stopService 在服务没运行时只是返回 false，安全无副作用。
        fun stopAll(context: Context) {
            TabbyAlarmScheduler.cancelPendingRepeat(context)
            val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            nm.cancel(NOTIFICATION_ID)
            try {
                context.stopService(intent(context, 0, "提醒", "", 1, stop = true))
            } catch (e: Exception) {
                Log.w(TAG, "停止响铃失败", e)
            }
        }
    }

    private var player: MediaPlayer? = null
    private var vibrator: Vibrator? = null
    private val handler = Handler(Looper.getMainLooper())

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            TabbyAlarmScheduler.cancelPendingRepeat(this)
            handler.removeCallbacksAndMessages(null)
            stopRinging()
            clearNotification()
            stopSelfSafely()
            return START_NOT_STICKY
        }

        val id = intent?.getIntExtra(EXTRA_ID, 0) ?: 0
        val title = intent?.getStringExtra(EXTRA_TITLE) ?: "提醒"
        val body = intent?.getStringExtra(EXTRA_BODY) ?: ""
        val round = intent?.getIntExtra(EXTRA_ROUND, 1) ?: 1

        ensureChannels()
        try {
            startForeground(NOTIFICATION_ID, buildRingingNotification(this, id, title, body, round))
        } catch (e: Exception) {
            // 极少数情况下前台服务起不来，但铃声还是得响
            Log.w(TAG, "前台服务起不来，退化为无通知响铃", e)
        }

        startRinging()
        // 到点自动停：不再需要人手动关才会停。
        val ringMillis = TabbyAlarmPrefs.ringMinutes(this) * 60_000L
        handler.removeCallbacksAndMessages(null)
        handler.postDelayed({ onRingFinished(id, title, body, round) }, ringMillis)
        return START_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        handler.removeCallbacksAndMessages(null)
        stopRinging()
        super.onDestroy()
    }

    /// 这一轮响满了：要么收工，要么排下一轮。
    private fun onRingFinished(id: Int, title: String, body: String, round: Int) {
        stopRinging()

        val repeatTimes = TabbyAlarmPrefs.repeatTimes(this)
        val again = repeatTimes == TabbyAlarmPrefs.REPEAT_UNTIL_DISMISSED || round < repeatTimes
        if (!again) {
            clearNotification()
            stopSelfSafely()
            return
        }

        val snoozeMillis = TabbyAlarmPrefs.snoozeMinutes(this) * 60_000L
        val next = AlarmSpec(
            id = id,
            atMillis = System.currentTimeMillis() + snoozeMillis,
            title = title,
            body = body,
            round = round + 1,
        )
        TabbyAlarmScheduler.scheduleOne(this, next)
        TabbyAlarmPrefs.savePendingRepeat(this, next)

        // 退出前台但留下一条「待响」提示，让人知道它还会再响、也还能取消。
        stopForegroundSafely()
        showWaitingNotification(id, title, body, next)
        stopSelf()
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

    private fun stopForegroundSafely() {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                stopForeground(STOP_FOREGROUND_REMOVE)
            } else {
                @Suppress("DEPRECATION")
                stopForeground(true)
            }
        } catch (_: Exception) {
        }
    }

    private fun stopSelfSafely() {
        stopForegroundSafely()
        stopSelf()
    }

    private fun clearNotification() {
        try {
            (getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager)
                .cancel(NOTIFICATION_ID)
        } catch (_: Exception) {
        }
    }

    private fun ensureChannels() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

        if (nm.getNotificationChannel(CHANNEL_ID) == null) {
            nm.createNotificationChannel(
                NotificationChannel(
                    CHANNEL_ID,
                    "正在响铃",
                    NotificationManager.IMPORTANCE_HIGH,
                ).apply {
                    description = "闹钟到点响铃时的常驻通知"
                    // 声音和震动都由服务自己放，通知不再重复出声
                    setSound(null, null)
                    enableVibration(false)
                },
            )
        }

        if (nm.getNotificationChannel(CHANNEL_WAITING_ID) == null) {
            nm.createNotificationChannel(
                NotificationChannel(
                    CHANNEL_WAITING_ID,
                    "待再次响铃",
                    NotificationManager.IMPORTANCE_DEFAULT,
                ).apply {
                    description = "闹钟两轮之间的等待提示"
                    setSound(null, null)
                    enableVibration(false)
                },
            )
        }
    }

    private fun pFlags(): Int {
        var flags = PendingIntent.FLAG_UPDATE_CURRENT
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            flags = flags or PendingIntent.FLAG_IMMUTABLE
        }
        return flags
    }

    private fun buildRingingNotification(
        context: Context,
        id: Int,
        title: String,
        body: String,
        round: Int,
    ): Notification {
        val contentIntent = PendingIntent.getActivity(
            context,
            id + 600_000,
            TabbyAlarmActivity.intent(context, id, title, body, round),
            pFlags(),
        )
        // fullScreenIntent：系统在锁屏 / 熄屏时会替我们把响铃页拉到最前面，
        // 这是 Android 允许的从后台弹界面的正规通道。
        val fullScreenIntent = PendingIntent.getActivity(
            context,
            id + 700_000,
            TabbyAlarmActivity.intent(context, id, title, body, round),
            pFlags(),
        )
        val stopPending = PendingIntent.getService(
            context,
            id + 800_000,
            intent(context, id, title, body, round, stop = true),
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
            .setContentText(ringingSummary(body, round))
            .setCategory(Notification.CATEGORY_ALARM)
            .setOngoing(true)
            .setAutoCancel(false)
            .setContentIntent(contentIntent)
            .setFullScreenIntent(fullScreenIntent, true)
            .addAction(
                Notification.Action.Builder(
                    R.mipmap.ic_launcher,
                    "关闭",
                    stopPending,
                ).build(),
            )

        @Suppress("DEPRECATION")
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            builder.setPriority(Notification.PRIORITY_MAX)
        }
        // 声音与震动都由服务自己放。通知不再出声靠的是渠道本身没配铃声
        // （见 ensureChannels 里的 setSound(null, null)），所以这里不用再处理。
        return builder.build()
    }

    private fun ringingSummary(body: String, round: Int): String {
        val ring = TabbyAlarmPrefs.ringMinutes(this)
        val repeat = TabbyAlarmPrefs.repeatTimes(this)
        val head = if (repeat == TabbyAlarmPrefs.REPEAT_UNTIL_DISMISSED) {
            "第 $round 次 · 这次响 $ring 分钟，之后还会再响"
        } else if (repeat <= 1) {
            "只响这一次 · 共 $ring 分钟"
        } else {
            "第 $round/$repeat 次 · 这次响 $ring 分钟"
        }
        return if (body.isBlank()) head else "$head\n$body"
    }

    private fun showWaitingNotification(
        id: Int,
        title: String,
        body: String,
        next: AlarmSpec,
    ) {
        val time = SimpleDateFormat("HH:mm", Locale.getDefault()).format(next.atMillis)
        // 走广播而不是 service：等待期间服务已停，后台 startService 会被系统拒绝。
        val stopPending = PendingIntent.getBroadcast(
            this,
            id + 900_000,
            TabbyAlarmReceiver.cancelIntent(this),
            pFlags(),
        )
        // 等待期间点通知只是看看，不要把下一轮提前拉响
        val openPending = PendingIntent.getActivity(
            this,
            id + 950_000,
            TabbyAlarmActivity.intent(this, id, title, body, next.round, autoStart = false),
            pFlags(),
        )

        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_WAITING_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }
        val notification = builder
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle("$title · $time 再响一次")
            .setContentText(
                if (body.isBlank()) "点「取消后续」就不会再响了" else body,
            )
            .setContentIntent(openPending)
            .setAutoCancel(true)
            .addAction(
                Notification.Action.Builder(
                    R.mipmap.ic_launcher,
                    "取消后续",
                    stopPending,
                ).build(),
            )
            .build()

        try {
            (getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager)
                .notify(NOTIFICATION_ID, notification)
        } catch (e: Exception) {
            Log.w(TAG, "显示待响通知失败", e)
        }
    }
}
