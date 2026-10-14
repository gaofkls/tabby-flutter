import 'dart:convert';

import 'package:drift/drift.dart' hide Column;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:home_widget/home_widget.dart';

import '../app/router.dart';
import '../data/app_database.dart';
import '../data/occurrence.dart';
import '../data/widget_display_mode.dart';

/// 桌面小组件的数据源。
///
/// 小组件由系统进程渲染，读不到 Flutter 的内存，所以这里把备忘和课程序列化成
/// JSON 存进 SharedPreferences，再通知系统重绘（原生侧 TabbyWidget.kt 读它）。
///
/// 两个刻意的设计：
/// 1. 存的是**未来 14 天这个窗口**而不是算好的「今天 / 明天」——日期判断放在
///    原生侧每次重绘时按当前时间做，这样即使好几天没开 App，小组件也不会
///    停在过期的旧内容上。
/// 2. 课程在这里就按「星期 + 周次」展开成具体日期，跟 App 里的课表用的是
///    同一套 `weeksMatch` / `weekNumberFor`，不会两边算出不一样的课。
class WidgetDataService {
  const WidgetDataService(this._db);

  final AppDatabase _db;

  static const String dataKey = 'widget_memos';
  static const String androidProviderName = 'TabbyWidget';
  static const int windowDays = 14;

  static const MethodChannel _channel = MethodChannel('tabby/widget');

  /// 小组件当前显示什么（备忘 / 课表 / 全部）。存在原生侧，
  /// 因为小组件重绘时读不到 Dart 内存。
  Future<WidgetDisplayMode> loadDisplayMode() async {
    try {
      final raw = await _channel.invokeMethod<String>('getMode');
      return WidgetDisplayModeX.fromKey(raw);
    } catch (_) {
      return WidgetDisplayMode.all;
    }
  }

  Future<void> saveDisplayMode(WidgetDisplayMode mode) async {
    try {
      await _channel
          .invokeMethod<void>('setMode', <String, Object?>{'mode': mode.key});
    } catch (_) {
      // 平台不支持就当没设置过
    }
  }

  /// 让小组件立刻重绘（改完显示模式后调一次）。
  Future<void> updateWidget() async {
    try {
      await _channel.invokeMethod<void>('update');
    } catch (_) {
      // 平台不支持，忽略
    }
  }

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

  /// 生成给原生侧读的 JSON：
  /// {"items":[{"kind":"course","title":..,"date":..,"minute":..,"endMinute":..,
  ///            "subtitle":..,"color":..}]}
  ///
  /// kind 为 course / memo，date 为 null 表示「不限时间」的备忘。
  Future<String> buildPayload() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final end = today.add(const Duration(days: windowDays));

    final term = await (_db.select(_db.terms)
          ..where((t) => t.isActive.equals(true))
          ..limit(1))
        .getSingleOrNull();

    final entries = <Map<String, dynamic>>[];

    final courses =
        await (_db.select(_db.courses)..where((t) => t.deletedAt.isNull()))
            .get();
    final sessions = await (_db.select(_db.courseSessions)
          ..where((t) => t.deletedAt.isNull()))
        .get();
    final courseById = <String, Course>{for (final c in courses) c.id: c};

    // 课程：按 weekday 落进窗口内每一天，再用周次规则过滤
    var cursor = today;
    while (!cursor.isAfter(end)) {
      final week = weekNumberFor(cursor, term?.startDate);
      for (final s in sessions) {
        if (s.weekday != cursor.weekday) continue;
        if (!weeksMatch(s.weeks, week)) continue;
        final course = courseById[s.courseId];
        if (course == null) continue;

        entries.add(<String, dynamic>{
          'kind': 'course',
          'title': course.name,
          'date': _formatDate(cursor),
          'minute': s.startMinute,
          'endMinute': s.endMinute,
          'subtitle': (s.locationOverride ?? course.location ?? '').trim(),
          'color': course.color,
        });
      }
      cursor = cursor.add(const Duration(days: 1));
    }

    // 备忘：按 dueDate 落进窗口
    final items = await (_db.select(_db.items)
          ..where((t) => t.deletedAt.isNull() & t.done.equals(false)))
        .get();
    for (final item in items) {
      final due = item.dueDate;
      if (due == null) {
        if (item.dueMinute == null) {
          entries.add(<String, dynamic>{
            'kind': 'memo',
            'title': item.title,
            'date': null,
            'minute': null,
            'endMinute': null,
            'subtitle': (item.note ?? '').trim(),
            'color': null,
          });
        }
        continue;
      }
      final day = DateTime(due.year, due.month, due.day);
      if (day.isBefore(today) || day.isAfter(end)) continue;
      entries.add(<String, dynamic>{
        'kind': 'memo',
        'title': item.title,
        'date': _formatDate(day),
        'minute': item.dueMinute,
        'endMinute': item.dueMinute == null ? null : item.dueMinute! + 60,
        'subtitle': (item.note ?? '').trim(),
        'color': null,
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
