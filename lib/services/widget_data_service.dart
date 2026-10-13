import 'dart:convert';

import 'package:drift/drift.dart' hide Column;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:home_widget/home_widget.dart';

import '../app/router.dart';
import '../data/app_database.dart';

/// 桌面小组件的数据源。
///
/// 小组件由系统进程渲染，读不到 Flutter 的内存，所以这里把备忘序列化成
/// JSON 存进 SharedPreferences，再通知系统重绘（原生侧 TabbyWidget.kt 读它）。
///
/// 存的是**未来 14 天这个窗口**而不是算好的「今天 / 明天」：日期判断放在
/// 原生侧每次重绘时按当前时间做，这样即使好几天没开 App，小组件也不会
/// 停在过期的旧内容上。
class WidgetDataService {
  const WidgetDataService(this._db);

  final AppDatabase _db;

  static const String dataKey = 'widget_memos';
  static const String androidProviderName = 'TabbyWidget';
  static const int windowDays = 14;

  /// 重新算一份快照并让小组件重绘。失败静默返回 false（小组件不是核心功能）。
  Future<bool> refresh() async {
    try {
      final payload = await buildPayload();
      await HomeWidget.saveWidgetData<String>(dataKey, payload);
      await HomeWidget.updateWidget(androidName: androidProviderName);
      return true;
    } catch (_) {
      // 平台不支持 / 小组件没添加 / 插件没注册，都不该影响 App 本身
      return false;
    }
  }

  /// 生成给原生侧读的 JSON：{"items":[{"title":..,"date":..,"minute":..}]}
  /// date 为 null 表示「不限时间」的备忘，由小组件归入今天。
  Future<String> buildPayload() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final end = today.add(const Duration(days: windowDays));

    final rows = await (_db.select(_db.items)
          ..where((t) => t.deletedAt.isNull() & t.done.equals(false)))
        .get();

    final entries = <Map<String, dynamic>>[];
    for (final item in rows) {
      final due = item.dueDate;
      if (due == null) {
        entries.add(<String, dynamic>{
          'title': item.title,
          'date': null,
          'minute': null,
        });
        continue;
      }
      final day = DateTime(due.year, due.month, due.day);
      // 过去的（已过期）和窗口外的都不写进小组件
      if (day.isBefore(today) || day.isAfter(end)) continue;
      entries.add(<String, dynamic>{
        'title': item.title,
        'date': _formatDate(day),
        'minute': item.dueMinute,
      });
    }

    return jsonEncode(<String, dynamic>{'items': entries});
  }

  static String _formatDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}

final widgetDataServiceProvider = Provider<WidgetDataService>((ref) {
  return WidgetDataService(ref.watch(databaseProvider));
});
