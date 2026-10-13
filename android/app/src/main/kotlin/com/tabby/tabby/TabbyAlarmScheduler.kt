package com.tabby.tabby

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log
import org.json.JSONArray
import org.json.JSONObject

/// 一条待响的闹钟。
data class AlarmSpec(
    val id: Int,
    val atMillis: Long,
    val title: String,
    val body: String,
)

/// 用系统 AlarmManager 排真正的闹钟。
///
/// 为什么不用通知：通知只能「叮」一声就结束，声音和长度都受通知渠道约束，
/// 变不成会把人叫醒的闹钟。这里用 `setAlarmClock`——它除了精确触发，
/// 还被 Android 明确豁免于「后台启动 Activity」的限制，
/// 因此到点能直接弹出锁屏之上的响铃页面。
object TabbyAlarmScheduler {
    private const val TAG = "TabbyAlarm"
    private const val PREFS = "tabby_alarms"
    private const val KEY_SPECS = "specs"

    fun scheduleAll(context: Context, specs: List<AlarmSpec>): Int {
        val am = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        cancelAll(context)

        val canExact = Build.VERSION.SDK_INT < Build.VERSION_CODES.S ||
                am.canScheduleExactAlarms()
        var count = 0

        for (spec in specs) {
            try {
                val pi = alarmPendingIntent(context, spec)
                if (canExact) {
                    // 第二个参数是「状态栏闹钟图标点击后打开谁」，这里指向响铃页。
                    val show = Intent(context, TabbyAlarmActivity::class.java).apply {
                        putExtra(TabbyAlarmActivity.EXTRA_ID, spec.id)
                        putExtra(TabbyAlarmActivity.EXTRA_TITLE, spec.title)
                        putExtra(TabbyAlarmActivity.EXTRA_BODY, spec.body)
                    }
                    val showPi = PendingIntent.getActivity(
                        context,
                        spec.id + 500_000,
                        show,
                        pendingFlags(),
                    )
                    am.setAlarmClock(AlarmManager.AlarmClockInfo(spec.atMillis, showPi), pi)
                } else {
                    // 没拿到精确闹钟授权时的兜底：可能延后几分钟，但至少会响。
                    am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, spec.atMillis, pi)
                }
                count++
            } catch (e: Exception) {
                Log.w(TAG, "排闹钟失败 id=${spec.id}", e)
            }
        }

        save(context, specs)
        return count
    }

    /// 只排一条、不动其它已排的闹钟（「稍后提醒」用）。
    fun scheduleOne(context: Context, spec: AlarmSpec) {
        val am = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        try {
            val pi = alarmPendingIntent(context, spec)
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S || am.canScheduleExactAlarms()) {
                am.setAlarmClock(AlarmManager.AlarmClockInfo(spec.atMillis, null), pi)
            } else {
                am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, spec.atMillis, pi)
            }
        } catch (e: Exception) {
            Log.w(TAG, "排单条闹钟失败 id=${spec.id}", e)
        }
    }

    fun cancelAll(context: Context) {
        val am = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        for (spec in load(context)) {
            try {
                am.cancel(alarmPendingIntent(context, spec))
            } catch (e: Exception) {
                Log.w(TAG, "取消闹钟失败 id=${spec.id}", e)
            }
        }
        save(context, emptyList())
    }

    /// 开机 / 升级后由 TabbyAlarmBootReceiver 调用，把上次排好的闹钟重新装上。
    fun rescheduleFromPrefs(context: Context): Int {
        val specs = load(context).filter { it.atMillis > System.currentTimeMillis() }
        return scheduleAll(context, specs)
    }

    fun pendingCount(context: Context): Int =
        load(context).count { it.atMillis > System.currentTimeMillis() }

    private fun alarmPendingIntent(context: Context, spec: AlarmSpec): PendingIntent {
        val intent = Intent(context, TabbyAlarmReceiver::class.java).apply {
            action = TabbyAlarmReceiver.ACTION_FIRE
            putExtra(TabbyAlarmActivity.EXTRA_ID, spec.id)
            putExtra(TabbyAlarmActivity.EXTRA_TITLE, spec.title)
            putExtra(TabbyAlarmActivity.EXTRA_BODY, spec.body)
            putExtra(TabbyAlarmActivity.EXTRA_AT, spec.atMillis)
        }
        return PendingIntent.getBroadcast(
            context,
            spec.id,
            intent,
            pendingFlags(),
        )
    }

    private fun pendingFlags(): Int {
        var flags = PendingIntent.FLAG_UPDATE_CURRENT
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            flags = flags or PendingIntent.FLAG_IMMUTABLE
        }
        return flags
    }

    private fun save(context: Context, specs: List<AlarmSpec>) {
        val arr = JSONArray()
        for (s in specs) {
            arr.put(
                JSONObject()
                    .put("id", s.id)
                    .put("at", s.atMillis)
                    .put("title", s.title)
                    .put("body", s.body),
            )
        }
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit()
            .putString(KEY_SPECS, arr.toString())
            .apply()
    }

    private fun load(context: Context): List<AlarmSpec> {
        val raw = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .getString(KEY_SPECS, null) ?: return emptyList()
        return try {
            val arr = JSONArray(raw)
            (0 until arr.length()).mapNotNull { i ->
                val o = arr.getJSONObject(i)
                AlarmSpec(
                    id = o.getInt("id"),
                    atMillis = o.getLong("at"),
                    title = o.optString("title", ""),
                    body = o.optString("body", ""),
                )
            }
        } catch (e: Exception) {
            Log.w(TAG, "读取已排闹钟失败", e)
            emptyList()
        }
    }
}
