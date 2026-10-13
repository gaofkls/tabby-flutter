package com.tabby.tabby

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log
import android.widget.Toast

/// 闹钟到点：把响铃页面顶到最前面。
///
/// 用 `setAlarmClock` 排的闹钟在这里触发，Android 对这类闹钟豁免了
/// 「后台不能启动 Activity」的限制，所以锁屏状态下也能弹出来。
class TabbyAlarmReceiver : BroadcastReceiver() {
    companion object {
        const val ACTION_FIRE = "com.tabby.tabby.ALARM_FIRE"
    }

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != ACTION_FIRE) return
        val id = intent.getIntExtra(TabbyAlarmActivity.EXTRA_ID, 0)
        val title = intent.getStringExtra(TabbyAlarmActivity.EXTRA_TITLE) ?: "提醒"
        val body = intent.getStringExtra(TabbyAlarmActivity.EXTRA_BODY) ?: ""

        try {
            val launch = Intent(context, TabbyAlarmActivity::class.java).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP)
                putExtra(TabbyAlarmActivity.EXTRA_ID, id)
                putExtra(TabbyAlarmActivity.EXTRA_TITLE, title)
                putExtra(TabbyAlarmActivity.EXTRA_BODY, body)
            }
            context.startActivity(launch)
        } catch (e: Exception) {
            // 极少数 ROM 拦掉了后台弹页面，至少给个 Toast 让人知道到点了。
            Log.w("TabbyAlarm", "无法弹出响铃页面", e)
            Toast.makeText(context, "$title $body", Toast.LENGTH_LONG).show()
        }
    }
}
