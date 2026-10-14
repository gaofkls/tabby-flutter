package com.tabby.tabby

import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent

/// 主动让桌面小组件重绘。
///
/// 系统自己最多半小时刷一次（updatePeriodMillis 下限），太慢；
/// 数据变了、或者用户切了显示模式，就靠这里立刻推一次。
object WidgetRefresher {

    fun update(context: Context) {
        val manager = AppWidgetManager.getInstance(context)
        val ids = manager.getAppWidgetIds(
            ComponentName(context, TabbyWidget::class.java),
        )
        if (ids.isEmpty()) return // 没添加到桌面，不用白忙

        // 让 ListView 重新取数据
        manager.notifyAppWidgetViewDataChanged(ids, R.id.widget_list)

        // 让头部（模式选中态、范围文案）也跟着重画
        context.sendBroadcast(
            Intent(context, TabbyWidget::class.java).apply {
                action = AppWidgetManager.ACTION_APPWIDGET_UPDATE
                putExtra(AppWidgetManager.EXTRA_APPWIDGET_IDS, ids)
            },
        )
    }
}
