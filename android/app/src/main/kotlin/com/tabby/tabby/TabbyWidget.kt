package com.tabby.tabby

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.os.Build
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetPlugin
import org.json.JSONObject
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Date
import java.util.Locale

/**
 * 桌面小组件：显示「今天 / 明天」的备忘。
 *
 * 数据由 Flutter 侧（WidgetDataService）序列化成 JSON 放进 SharedPreferences，
 * 这里只负责读出来、筛成今天和明天、排好序填进 RemoteViews。
 *
 * 日期判断放在原生侧、每次重绘时按当前时间做，所以即使 App 好几天没打开，
 * 小组件也不会停在过期的旧内容上。
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
    }

    private fun updateAppWidget(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetId: Int,
    ) {
        val views = RemoteViews(context.packageName, R.layout.tabby_widget)

        val launchIntent = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        } else {
            PendingIntent.FLAG_UPDATE_CURRENT
        }
        val pendingIntent = PendingIntent.getActivity(context, 0, launchIntent, flags)
        views.setOnClickPendingIntent(R.id.widget_root, pendingIntent)

        val entries = loadEntries(context)

        val rowIds = intArrayOf(R.id.row_0, R.id.row_1, R.id.row_2, R.id.row_3)
        val tagIds = intArrayOf(R.id.tag_0, R.id.tag_1, R.id.tag_2, R.id.tag_3)
        val titleIds = intArrayOf(R.id.title_0, R.id.title_1, R.id.title_2, R.id.title_3)
        val timeIds = intArrayOf(R.id.time_0, R.id.time_1, R.id.time_2, R.id.time_3)

        if (entries.isEmpty()) {
            views.setViewVisibility(R.id.text_empty, View.VISIBLE)
            for (rowId in rowIds) views.setViewVisibility(rowId, View.GONE)
        } else {
            views.setViewVisibility(R.id.text_empty, View.GONE)
            for (i in rowIds.indices) {
                val entry = entries.getOrNull(i)
                if (entry == null) {
                    views.setViewVisibility(rowIds[i], View.GONE)
                    continue
                }
                views.setViewVisibility(rowIds[i], View.VISIBLE)
                views.setTextViewText(tagIds[i], entry.tag)
                views.setTextViewText(titleIds[i], entry.title)
                views.setTextViewText(timeIds[i], entry.timeText)
            }
        }

        appWidgetManager.updateAppWidget(appWidgetId, views)
    }

    private data class Entry(
        val tag: String,
        val title: String,
        val timeText: String,
        val sortKey: Int,
    )

    private fun loadEntries(context: Context): List<Entry> {
        val raw = HomeWidgetPlugin.getData(context).getString(DATA_KEY, null)
            ?: return emptyList()

        val array = JSONObject(raw).optJSONArray("items") ?: return emptyList()

        val today = dayKey(Calendar.getInstance().time)
        val tomorrow = dayKey(
            Calendar.getInstance().apply { add(Calendar.DAY_OF_YEAR, 1) }.time,
        )

        val result = mutableListOf<Entry>()
        for (i in 0 until array.length()) {
            val obj = array.optJSONObject(i) ?: continue
            val title = obj.optString("title", "").trim()
            if (title.isEmpty()) continue

            // date 为 null 代表「不限时间」的备忘，归入今天
            val date = if (!obj.isNull("date")) obj.optString("date") else null
            val minute = if (!obj.isNull("minute")) obj.optInt("minute") else null

            val dayOffset = when {
                date == null -> 0
                date == today -> 0
                date == tomorrow -> 1
                else -> continue
            }

            val tag = if (dayOffset == 0) "今天" else "明天"
            val timeText = if (minute == null) "不限时间" else formatMinute(minute)
            // 不限时间的排在同组最后
            val sortKey = dayOffset * MINUTES_PER_DAY + (minute ?: MINUTES_PER_DAY)

            result.add(Entry(tag, title, timeText, sortKey))
        }

        return result.sortedBy { it.sortKey }
    }

    private fun dayKey(date: Date): String =
        SimpleDateFormat("yyyy-MM-dd", Locale.getDefault()).format(date)

    private fun formatMinute(minute: Int): String {
        val m = ((minute % MINUTES_PER_DAY) + MINUTES_PER_DAY) % MINUTES_PER_DAY
        return String.format(Locale.getDefault(), "%02d:%02d", m / 60, m % 60)
    }

    companion object {
        private const val DATA_KEY = "widget_memos"
        private const val MINUTES_PER_DAY = 24 * 60
    }
}
