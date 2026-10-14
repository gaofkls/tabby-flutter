package com.tabby.tabby

import android.content.Context
import es.antonborri.home_widget.HomeWidgetPlugin
import org.json.JSONObject

/// 小组件快照里的一条。kind 为 "course" / "memo"。
///
/// date 为 null 只会出现在「不限时间」的备忘上，由小组件归入今天。
data class WidgetEntry(
    val kind: String,
    val title: String,
    val date: String?,
    val minute: Int?,
    val endMinute: Int?,
    val subtitle: String?,
    val color: Int?,
)

/// 读 Flutter 侧（WidgetDataService）写进 SharedPreferences 的那份快照。
object TabbyWidgetData {
    const val DATA_KEY = "widget_memos"

    /// 数据坏了就当空的，绝不让异常冒出去——
    /// 一旦冒出去，系统会把整个小组件画成「加载失败」。
    fun load(context: Context): List<WidgetEntry> {
        val raw = HomeWidgetPlugin.getData(context).getString(DATA_KEY, null)
            ?: return emptyList()
        return try {
            val array = JSONObject(raw).optJSONArray("items") ?: return emptyList()
            val result = mutableListOf<WidgetEntry>()
            for (i in 0 until array.length()) {
                val o = array.optJSONObject(i) ?: continue
                val title = o.optString("title", "").trim()
                if (title.isEmpty()) continue
                result.add(
                    WidgetEntry(
                        kind = o.optString("kind", "memo"),
                        title = title,
                        date = if (o.isNull("date")) null else o.optString("date"),
                        minute = if (o.isNull("minute")) null else o.optInt("minute"),
                        endMinute = if (o.isNull("endMinute")) null else o.optInt("endMinute"),
                        subtitle = if (o.isNull("subtitle")) null else o.optString("subtitle"),
                        color = if (o.isNull("color")) null else o.optInt("color"),
                    ),
                )
            }
            result
        } catch (e: Exception) {
            emptyList()
        }
    }
}
