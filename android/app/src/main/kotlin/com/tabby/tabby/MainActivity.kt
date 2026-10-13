package com.tabby.tabby

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    companion object {
        private const val CHANNEL = "tabby/system_settings"
        private const val ALARM_CHANNEL = "tabby/alarm"
        private const val PREFS_SETTINGS = "tabby_settings"
        private const val KEY_ALARM_MODE = "alarm_mode"
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        setupSettingsChannel(flutterEngine)
        setupAlarmChannel(flutterEngine)
    }

    private fun setupAlarmChannel(flutterEngine: FlutterEngine) {
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, ALARM_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "scheduleAll" -> {
                        val raw = call.argument<List<Map<String, Any?>>>("alarms")
                            ?: emptyList()
                        val specs = raw.mapNotNull { map ->
                            val at = (map["at"] as? Number)?.toLong() ?: return@mapNotNull null
                            AlarmSpec(
                                id = (map["id"] as? Number)?.toInt() ?: 0,
                                atMillis = at,
                                title = map["title"] as? String ?: "提醒",
                                body = map["body"] as? String ?: "",
                            )
                        }
                        result.success(TabbyAlarmScheduler.scheduleAll(this, specs))
                    }
                    "cancelAll" -> {
                        TabbyAlarmScheduler.cancelAll(this)
                        result.success(null)
                    }
                    "pendingCount" ->
                        result.success(TabbyAlarmScheduler.pendingCount(this))
                    "openSystemAlarm" -> {
                        val hour = call.argument<Int>("hour") ?: 7
                        val minute = call.argument<Int>("minute") ?: 0
                        val message = call.argument<String>("message") ?: "Tabby 提醒"
                        val days = call.argument<List<Int>>("days")
                        result.success(openSystemAlarm(hour, minute, message, days))
                    }
                    "getMode" -> result.success(
                        getSharedPreferences(PREFS_SETTINGS, MODE_PRIVATE)
                            .getString(KEY_ALARM_MODE, "notification"),
                    )
                    "setMode" -> {
                        val mode = call.argument<String>("mode") ?: "notification"
                        getSharedPreferences(PREFS_SETTINGS, MODE_PRIVATE)
                            .edit()
                            .putString(KEY_ALARM_MODE, mode)
                            .apply()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    /// 把提醒交给系统自带的「时钟」App 去响。
    /// 第三方应用无法静默建系统闹钟（SET_ALARM 是签名权限），
    /// 只能弹出系统的「设置闹钟」界面让用户确认；好处是它由系统闹钟响，
    /// 且 EXTRA_DAYS 支持按周重复，正好适合课表。
    private fun openSystemAlarm(
        hour: Int,
        minute: Int,
        message: String,
        days: List<Int>?,
    ): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.KITKAT) return false
        return try {
            val intent = Intent(android.provider.AlarmClock.ACTION_SET_ALARM).apply {
                putExtra(android.provider.AlarmClock.EXTRA_HOUR, hour)
                putExtra(android.provider.AlarmClock.EXTRA_MINUTES, minute)
                putExtra(android.provider.AlarmClock.EXTRA_MESSAGE, message)
                putExtra(android.provider.AlarmClock.EXTRA_SKIP_UI, false)
                if (!days.isNullOrEmpty() && Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                    // Calendar 的星期：周一=2 ... 周日=1
                    putIntegerArrayListExtra(
                        android.provider.AlarmClock.EXTRA_DAYS,
                        ArrayList(days),
                    )
                    putExtra(android.provider.AlarmClock.EXTRA_VIBRATE, true)
                }
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            startActivity(intent)
            true
        } catch (e: Exception) {
            false
        }
    }

    private fun setupSettingsChannel(flutterEngine: FlutterEngine) {
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "openNotificationSettings" -> {
                        val intent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
                                .putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
                        } else {
                            Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS)
                                .setData(Uri.parse("package:$packageName"))
                        }
                        safeStart(intent)
                        result.success(null)
                    }
                    "openChannelSettings" -> {
                        val channelId = call.argument<String>("channelId")
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && channelId != null) {
                            val intent = Intent(Settings.ACTION_CHANNEL_NOTIFICATION_SETTINGS)
                                .putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
                                .putExtra(Settings.EXTRA_CHANNEL_ID, channelId)
                            safeStart(intent)
                        }
                        result.success(null)
                    }
                    "openAlarmSettings" -> {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                            val intent = Intent(Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM)
                                .setData(Uri.parse("package:$packageName"))
                            safeStart(intent)
                        }
                        result.success(null)
                    }
                    "openAppDetails" -> {
                        val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS)
                            .setData(Uri.parse("package:$packageName"))
                        safeStart(intent)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun safeStart(intent: Intent) {
        try {
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            startActivity(intent)
        } catch (e: Exception) {
            // 该 ROM 没有对应的设置页，静默忽略，不影响 App
        }
    }
}
