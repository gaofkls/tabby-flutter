package com.tabby.tabby

import android.content.Context
import org.json.JSONObject

/// 响铃行为的配置：每次响多久、隔多久再响、一共响几次。
///
/// 为什么存在原生而不是只留在 Dart：闹钟到点时 App 往往根本没运行，
/// 响铃服务必须自己知道该响多久、要不要再响，所以配置得落在 SharedPreferences 里。
/// 用与 MainActivity 相同的 preferences 文件，Dart 通过 MethodChannel 读写同一份。
object TabbyAlarmPrefs {
    private const val PREFS = "tabby_settings"

    const val KEY_RING_MINUTES = "alarm_ring_minutes"
    const val KEY_SNOOZE_MINUTES = "alarm_snooze_minutes"
    const val KEY_REPEAT_TIMES = "alarm_repeat_times"
    private const val KEY_PENDING_REPEAT = "alarm_pending_repeat"

    const val DEFAULT_RING_MINUTES = 1
    const val DEFAULT_SNOOZE_MINUTES = 5
    const val DEFAULT_REPEAT_TIMES = 3

    /// repeatTimes 取这个值表示「一直重复，直到手动关闭」。
    const val REPEAT_UNTIL_DISMISSED = 0

    private fun prefs(context: Context) =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    fun ringMinutes(context: Context): Int =
        prefs(context).getInt(KEY_RING_MINUTES, DEFAULT_RING_MINUTES).coerceIn(1, 60)

    fun snoozeMinutes(context: Context): Int =
        prefs(context).getInt(KEY_SNOOZE_MINUTES, DEFAULT_SNOOZE_MINUTES).coerceIn(1, 120)

    fun repeatTimes(context: Context): Int =
        prefs(context).getInt(KEY_REPEAT_TIMES, DEFAULT_REPEAT_TIMES).coerceAtLeast(0)

    fun save(context: Context, ringMinutes: Int, snoozeMinutes: Int, repeatTimes: Int) {
        prefs(context).edit()
            .putInt(KEY_RING_MINUTES, ringMinutes.coerceIn(1, 60))
            .putInt(KEY_SNOOZE_MINUTES, snoozeMinutes.coerceIn(1, 120))
            .putInt(KEY_REPEAT_TIMES, repeatTimes.coerceAtLeast(0))
            .apply()
    }

    /// 记下「还有一轮待响」，这样点「关闭」时能把它一并取消掉。
    fun savePendingRepeat(context: Context, spec: AlarmSpec) {
        prefs(context).edit()
            .putString(
                KEY_PENDING_REPEAT,
                JSONObject()
                    .put("id", spec.id)
                    .put("at", spec.atMillis)
                    .put("title", spec.title)
                    .put("body", spec.body)
                    .put("round", spec.round)
                    .toString(),
            )
            .apply()
    }

    fun pendingRepeat(context: Context): AlarmSpec? {
        val raw = prefs(context).getString(KEY_PENDING_REPEAT, null) ?: return null
        return try {
            val o = JSONObject(raw)
            AlarmSpec(
                id = o.getInt("id"),
                atMillis = o.getLong("at"),
                title = o.optString("title", "提醒"),
                body = o.optString("body", ""),
                round = o.optInt("round", 1),
            )
        } catch (e: Exception) {
            null
        }
    }

    fun clearPendingRepeat(context: Context) {
        prefs(context).edit().remove(KEY_PENDING_REPEAT).apply()
    }
}
