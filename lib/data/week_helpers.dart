import 'occurrence.dart';

/// 周次与日期的互相换算。
///
/// 课表里写的是「第 1-3、5-9 周」，人想知道的是「9 月 7 日到 9 月 27 日」；
/// 反过来选日期时，又要把它翻译成周次。这两个方向都要有，否则填周次全靠心算。
class WeekHelpers {
  WeekHelpers._();

  /// 第 n 周的周一。
  static DateTime weekStart(int week, DateTime termStart) {
    final base = _monday(termStart);
    return base.add(Duration(days: (week - 1) * 7));
  }

  /// 第 n 周的周日。
  static DateTime weekEnd(int week, DateTime termStart) =>
      weekStart(week, termStart).add(const Duration(days: 6));

  /// 日期区间 → 周次表达式（如「3-8」）。落在开学前返回 null。
  static String? weeksFromDateRange(
    DateTime from,
    DateTime to,
    DateTime termStart,
  ) {
    final a = weekNumberFor(from, termStart);
    final b = weekNumberFor(to, termStart);
    if (a == null || b == null) return null;
    if (a == b) return '$a';
    return '$a-$b';
  }

  /// 周次表达式 → 人能看懂的日期区间（如「第1-3周（9/7–9/27）」）。
  /// 没有学期起始日时原样返回表达式。
  static String describeWeeks(
    String spec,
    DateTime? termStart, {
    int weekCount = 20,
  }) {
    final s = spec.trim();
    if (s.isEmpty || s == '*') return '每周';
    if (termStart == null) return s;

    final base = _monday(termStart);
    final weeks = <int>{};

    for (final token in s.split(',')) {
      final t = token.trim();
      if (t.isEmpty) continue;
      if (t == '单') {
        for (var w = 1; w <= weekCount; w += 2) {
          weeks.add(w);
        }
      } else if (t == '双') {
        for (var w = 2; w <= weekCount; w += 2) {
          weeks.add(w);
        }
      } else if (t.contains('-')) {
        final parts = t.split('-');
        final a = int.tryParse(parts[0].trim());
        final b = int.tryParse(parts[1].trim());
        if (a != null && b != null) {
          for (var w = a; w <= b && w <= weekCount + 8; w++) {
            weeks.add(w);
          }
        }
      } else {
        final n = int.tryParse(t);
        if (n != null) weeks.add(n);
      }
    }

    if (weeks.isEmpty) return s;
    final sorted = weeks.toList()..sort();

    // 合并连续周，读起来更像「第1-3周」而不是「第1、2、3周」
    final runs = <(int, int)>[];
    var start = sorted.first;
    var prev = sorted.first;
    for (final w in sorted.skip(1)) {
      if (w == prev + 1) {
        prev = w;
      } else {
        runs.add((start, prev));
        start = w;
        prev = w;
      }
    }
    runs.add((start, prev));

    return runs
        .map(
          (r) => '${r.$1 == r.$2 ? '第${r.$1}周' : '第${r.$1}-${r.$2}周'}'
              '（${_md(weekStart(r.$1, base))}–${_md(weekEnd(r.$2, base))}）',
        )
        .join('、');
  }

  static DateTime _monday(DateTime date) =>
      startOfWeek(date);

  static String _md(DateTime d) => '${d.month}/${d.day}';
}
