package com.tabby.tabby

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.Build
import android.widget.RemoteViews
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Locale

/**
 * 桌面小组件：按时间顺序显示「今天 / 明天」的备忘和课表。
 *
 * 数据由 Flutter 侧（WidgetDataService）序列化成 JSON 放进 SharedPreferences，
 * 列表内容由 TabbyWidgetService（RemoteViewsService）读出来、按模式筛、排好序。
 *
 * 两个关键设计：
 * 1. 列表用集合小组件，行数不再写死 —— 组件被拉多高就显示多少行，超出的可以滑动。
 * 2. 日期判断放在原生侧、每次重绘时按当前时间做，所以即使 App 好几天没打开，
 *    小组件也不会停在过期的旧内容上。
 */
class TabbyWidget : AppWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
    ) {
        for (appWidgetId in appWidgetIds) {
            updateAppWidget(context, appWidgetManager, appWidgetId)
        }
        // 让列表重新取一次数据（数据或显示模式变了之后靠这个刷新）
        appWidgetManager.notifyAppWidgetViewDataChanged(appWidgetIds, R.id.widget_list)
    }

    /// 模式切换按钮走广播：RemoteViews 上不能直接写状态，只能让这里改完偏好再重绘。
    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        if (intent.action != ACTION_SET_MODE) return

        val mode = intent.getStringExtra(EXTRA_MODE) ?: return
        TabbyWidgetPrefs.setMode(context, mode)

        val manager = AppWidgetManager.getInstance(context)
        val ids = manager.getAppWidgetIds(
            ComponentName(context, TabbyWidget::class.java),
        )
        manager.notifyAppWidgetViewDataChanged(ids, R.id.widget_list)
    }

    private fun updateAppWidget(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetId: Int,
    ) {
        val views = RemoteViews(context.packageName, R.layout.tabby_widget)
        val mode = TabbyWidgetPrefs.mode(context)

        // 整块区域（含标题栏）点一下打开 App
        val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        } else {
            PendingIntent.FLAG_UPDATE_CURRENT
        }
        val launchIntent = Intent(context, MainActivity::class.java).apply {
            this.flags = Intent.FLAG_ACTIVITY_NEW_TASK or
                Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val launchPending = PendingIntent.getActivity(context, 0, launchIntent, flags)
        views.setOnClickPendingIntent(R.id.widget_root, launchPending)

        views.setTextViewText(R.id.text_scope, "今天 / 明天 · ${modeLabel(mode)}")
        bindChip(context, views, R.id.chip_memo, "备忘",
            mode == TabbyWidgetPrefs.MODE_MEMO)
        bindChip(context, views, R.id.chip_course, "课表",
            mode == TabbyWidgetPrefs.MODE_COURSE)
        bindChip(context, views, R.id.chip_all, "全部",
            mode == TabbyWidgetPrefs.MODE_ALL)

        views.setTextViewText(R.id.text_empty, emptyTextFor(mode))

        // 列表数据交给 RemoteViewsService
        views.setRemoteAdapter(
            R.id.widget_list,
            Intent(context, TabbyWidgetService::class.java),
        )
        views.setEmptyView(R.id.widget_list, R.id.text_empty)

        appWidgetManager.updateAppWidget(appWidgetId, views)
    }

    /// 模式按钮：选中态换底色与文字色，点击发广播切模式。
    private fun bindChip(
        context: Context,
        views: RemoteViews,
        viewId: Int,
        label: String,
        selected: Boolean,
    ) {
        views.setTextViewText(viewId, label)
        views.setInt(
            viewId,
            "setBackgroundResource",
            if (selected) R.drawable.widget_chip_bg_selected
            else R.drawable.widget_chip_bg,
        )
        val color = if (selected) 0xFFFFFFFF.toInt() else 0xFF5F5E5A.toInt()
        views.setInt(viewId, "setTextColor", color)

        val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        } else {
            PendingIntent.FLAG_UPDATE_CURRENT
        }
        val intent = Intent(context, TabbyWidget::class.java).apply {
            action = ACTION_SET_MODE
            putExtra(EXTRA_MODE, modeKeyFor(viewId))
        }
        val pending = PendingIntent.getBroadcast(
            context,
            viewId, // 用 view id 当 requestCode，三个按钮互不覆盖
            intent,
            flags,
        )
        views.setOnClickPendingIntent(viewId, pending)
    }

    private fun modeKeyFor(viewId: Int): String = when (viewId) {
        R.id.chip_memo -> TabbyWidgetPrefs.MODE_MEMO
        R.id.chip_course -> TabbyWidgetPrefs.MODE_COURSE
        else -> TabbyWidgetPrefs.MODE_ALL
    }

    private fun modeLabel(mode: String): String = when (mode) {
        TabbyWidgetPrefs.MODE_MEMO -> "只看备忘"
        TabbyWidgetPrefs.MODE_COURSE -> "只看课表"
        else -> "全部（按时间）"
    }

    private fun emptyTextFor(mode: String): String = when (mode) {
        TabbyWidgetPrefs.MODE_MEMO -> "今天和明天没有备忘"
        TabbyWidgetPrefs.MODE_COURSE -> "今天和明天没有课"
        else -> "今天和明天没有安排"
    }

    companion object {
        const val ACTION_SET_MODE = "com.tabby.tabby.WIDGET_SET_MODE"
        const val EXTRA_MODE = "widget_mode"
    }
}
