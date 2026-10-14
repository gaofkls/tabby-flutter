package com.tabby.tabby

import android.content.Context
import android.content.Intent
import android.view.View
import android.widget.RemoteViews
import android.widget.RemoteViewsService
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Locale

/// 给桌面小组件的 ListView 供货。
///
/// 为什么从「写死 N 行」换成集合小组件：桌面组件的高度由用户拉伸决定，
/// 写死行数要么浪费空间、要么被裁掉；换成 ListView 之后内容多长都能滑，
/// 行数不再有上限。
///
/// 排序与分组都在这里按「重绘那一刻的时间」算，所以 App 几天没打开，
/// 小组件也不会停在过期的旧内容上。
class TabbyWidgetService : RemoteViewsService() {

    override fun onGetViewFactory(intent: Intent): RemoteViewsFactory =
        Factory(applicationContext)

    private class Factory(private val context: Context) : RemoteViewsFactory {

        private var rows: List<Row> = emptyList()

        override fun onCreate() {}

        /// 数据都在这里读：getViewAt 会被频繁调用，不能在这里做重活。
        override fun onDataSetChanged() {
            rows = buildRows()
        }

        override fun onDestroy() {
            rows = emptyList()
        }

        override fun getCount(): Int = rows.size

        override fun getViewAt(position: Int): RemoteViews? {
            val row = rows.getOrNull(position) ?: return null
            val views = RemoteViews(context.packageName, R.layout.tabby_widget_item)

            if (row.isHeader) {
                views.setViewVisibility(R.id.text_day, View.VISIBLE)
                views.setTextViewText(R.id.text_day, row.dayLabel)
                views.setViewVisibility(R.id.item_body, View.GONE)
            } else {
                views.setViewVisibility(R.id.text_day, View.GONE)
                views.setViewVisibility(R.id.item_body, View.VISIBLE)
                views.setTextViewText(R.id.text_title, row.title)
                views.setTextViewText(R.id.text_sub, row.subtitle)
                views.setTextViewText(R.id.text_time, row.timeText)
                views.setInt(R.id.color_bar, "setBackgroundColor", row.color)
            }

            // 点任意一行都打开 App；列表的 PendingIntent 模板由 TabbyWidget 设置。
            views.setOnClickFillInIntent(R.id.item_root, Intent())
            return views
        }

        override fun getLoadingView(): RemoteViews? = null

        override fun getViewTypeCount(): Int = 1

        override fun getItemId(position: Int): Long = position.toLong()

        override fun hasStableIds(): Boolean = true

        private fun buildRows(): List<Row> {
            val mode = TabbyWidgetPrefs.mode(context)
            val entries = TabbyWidgetData.load(context)

            val cal = Calendar.getInstance()
            val todayKey = dayKey(cal.time)
            cal.add(Calendar.DAY_OF_YEAR, 1)
            val tomorrowKey = dayKey(cal.time)

            val picked = mutableListOf<Pair<Int, WidgetEntry>>()
            for (e in entries) {
                if (mode != TabbyWidgetPrefs.MODE_ALL && mode != e.kind) continue
                val offset = when {
                    e.date == null -> 0 // 不限时间的备忘归入今天
                    e.date == todayKey -> 0
                    e.date == tomorrowKey -> 1
                    else -> -1
                }
                if (offset < 0) continue
                picked.add(offset to e)
            }

            // 先按天、再按时间；没写时间的排在同一天的最后（比较稳定，保持录入顺序）
            picked.sortWith(
                compareBy<Pair<Int, WidgetEntry>> { it.first }
                    .thenBy { it.second.minute ?: MINUTES_PER_DAY },
            )

            val out = mutableListOf<Row>()
            var lastOffset = -1
            for ((offset, e) in picked) {
                if (offset != lastOffset) {
                    out.add(
                        Row(
                            isHeader = true,
                            dayLabel = if (offset == 0) "今天" else "明天",
                        ),
                    )
                    lastOffset = offset
                }
                out.add(
                    Row(
                        isHeader = false,
                        title = e.title,
                        subtitle = subtitleFor(e),
                        timeText = timeTextFor(e),
                        color = colorFor(e),
                    ),
                )
            }
            return out
        }

        private fun timeTextFor(e: WidgetEntry): String =
            e.minute?.let(::formatMinute) ?: "不限时间"

        private fun subtitleFor(e: WidgetEntry): String {
            val parts = mutableListOf<String>()
            val end = e.endMinute
            if (end != null) parts.add("至 ${formatMinute(end)}")
            val sub = e.subtitle
            if (!sub.isNullOrBlank()) parts.add(sub)
            if (parts.isEmpty()) parts.add(if (e.kind == "course") "课程" else "备忘")
            return parts.joinToString(" · ")
        }

        private fun colorFor(e: WidgetEntry): Int =
            e.color ?: if (e.kind == "course") COURSE_COLOR else MEMO_COLOR

        private fun dayKey(date: java.util.Date): String =
            SimpleDateFormat("yyyy-MM-dd", Locale.getDefault()).format(date)

        private fun formatMinute(minute: Int): String {
            val m = ((minute % MINUTES_PER_DAY) + MINUTES_PER_DAY) % MINUTES_PER_DAY
            return String.format(Locale.getDefault(), "%02d:%02d", m / 60, m % 60)
        }

        private companion object {
            const val MINUTES_PER_DAY = 24 * 60
            const val COURSE_COLOR = 0xFF6750A4.toInt()
            const val MEMO_COLOR = 0xFF185FA5.toInt()
        }
    }

    private data class Row(
        val isHeader: Boolean,
        val dayLabel: String = "",
        val title: String = "",
        val subtitle: String = "",
        val timeText: String = "",
        val color: Int = 0xFF9A93A8.toInt(),
    )
}
