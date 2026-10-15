package com.tabby.tabby

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.SystemClock

/**
 * 让桌面小组件「自动」刷新。
 *
 * App 关闭后 Flutter 不会再重写那份快照，系统自己的 updatePeriodMillis 在
 * 息屏 / Doze / 厂商省电策略下又常常不触发，于是组件停在旧内容上，
 * 直到用户点开 App 才刷新一次。这里用 AlarmManager 定时（唤醒）主动推一次，
 * 原生 TabbyWidgetService 会按「当前日期」重新筛选今天 / 明天，组件自然就自行更新。
 */
class TabbyWidgetRefreshReceiver : BroadcastReceiver() {
    companion object {
        const val ACTION_TICK = "com.tabby.tabby.WIDGET_REFRESH_TICK"
        private const val REQUEST_CODE = 910_200
        private const val INTERVAL_MS = 30L * 60_000L

        /// 排一个每 30 分钟一次的唤醒刷新。重复设置会覆盖旧的，所以可多次安全调用。
        fun arm(context: Context) {
            val am = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
            val pi = PendingIntent.getBroadcast(
                context,
                REQUEST_CODE,
                Intent(context, TabbyWidgetRefreshReceiver::class.java).apply {
                    action = ACTION_TICK
                },
                PendingIntent.FLAG_UPDATE_CURRENT or
                    (if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M)
                        PendingIntent.FLAG_IMMUTABLE else 0),
            )
            am.setInexactRepeating(
                AlarmManager.ELAPSED_REALTIME_WAKEUP,
                SystemClock.elapsedRealtime() + 60_000L,
                INTERVAL_MS,
                pi,
            )
        }
    }

    override fun onReceive(context: Context, intent: Intent?) {
        when (intent?.action) {
            ACTION_TICK -> WidgetRefresher.update(context)
            Intent.ACTION_BOOT_COMPLETED,
            Intent.ACTION_MY_PACKAGE_REPLACED -> {
                // 开机 / 更新后重排定时，并立刻刷一次（避免开机当天的旧内容）
                arm(context)
                WidgetRefresher.update(context)
            }
        }
    }
}
