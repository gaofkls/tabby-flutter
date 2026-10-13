package com.tabby.tabby

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/// 开机 / 应用升级后把之前排好的闹钟重新装上，否则重启就不响了。
class TabbyAlarmBootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        when (intent.action) {
            Intent.ACTION_BOOT_COMPLETED,
            Intent.ACTION_MY_PACKAGE_REPLACED,
            "android.intent.action.QUICKBOOT_POWERON",
            "com.htc.intent.action.QUICKBOOT_POWERON",
            -> TabbyAlarmScheduler.rescheduleFromPrefs(context)
        }
    }
}
