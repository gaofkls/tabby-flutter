package com.tabby.tabby

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log

/// 闹钟到点。
///
/// 这里做两件事，互为兜底：
/// 1. 先起前台服务——它是铃声的持有者，界面弹不弹出来都不影响它响，
///    而且它的通知挂了 fullScreenIntent，系统会替我们把响铃页拉到最前面；
/// 2. 再尝试自己直接弹 Activity——App 还在前台 / ROM 放行时这条会更快。
class TabbyAlarmReceiver : BroadcastReceiver() {
    companion object {
        const val ACTION_FIRE = "com.tabby.tabby.ALARM_FIRE"
        private const val TAG = "TabbyAlarmReceiver"
    }

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != ACTION_FIRE) return
        val id = intent.getIntExtra(TabbyAlarmActivity.EXTRA_ID, 0)
        val title = intent.getStringExtra(TabbyAlarmActivity.EXTRA_TITLE) ?: "提醒"
        val body = intent.getStringExtra(TabbyAlarmActivity.EXTRA_BODY) ?: ""

        startRingingService(context, id, title, body)
        tryLaunchUi(context, id, title, body)
    }

    private fun startRingingService(
        context: Context,
        id: Int,
        title: String,
        body: String,
    ) {
        val service = TabbyAlarmService.intent(context, id, title, body)
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(service)
            } else {
                context.startService(service)
            }
        } catch (e: Exception) {
            Log.w(TAG, "起前台服务失败，退回普通方式", e)
            try {
                context.startService(service)
            } catch (e2: Exception) {
                Log.e(TAG, "连普通服务都起不来，这次闹钟可能不会响", e2)
            }
        }
    }

    private fun tryLaunchUi(
        context: Context,
        id: Int,
        title: String,
        body: String,
    ) {
        try {
            context.startActivity(TabbyAlarmActivity.intent(context, id, title, body))
        } catch (e: Exception) {
            // 被 ROM 拦了（小米 / Redmi 常见的「后台弹出界面」未放行）。
            // 无所谓：服务已经在响，全屏意图那条通知也还在。
            Log.w(TAG, "弹响铃页被拦", e)
        }
    }
}
