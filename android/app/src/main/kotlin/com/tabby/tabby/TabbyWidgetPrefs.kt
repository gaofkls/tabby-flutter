package com.tabby.tabby

import android.content.Context

/// 桌面小组件「显示什么」的偏好。
///
/// 存在与 MainActivity / 闹钟配置同一个 SharedPreferences 文件里，
/// 这样 Dart 侧改完设置，小组件下次重绘就能直接读到——它读不到 Dart 内存。
object TabbyWidgetPrefs {
    private const val PREFS = "tabby_settings"
    private const val KEY_MODE = "widget_mode"

    const val MODE_MEMO = "memo"
    const val MODE_COURSE = "course"
    const val MODE_ALL = "all"

    fun mode(context: Context): String =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .getString(KEY_MODE, MODE_ALL) ?: MODE_ALL

    fun setMode(context: Context, mode: String) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit()
            .putString(KEY_MODE, mode)
            .apply()
    }
}
