import 'package:flutter_test/flutter_test.dart';
import 'package:tabby/data/occurrence.dart';
import 'package:tabby/data/week_helpers.dart';

void main() {
  // 2026-09-07 是周一，作为学期第 1 周
  final termStart = DateTime(2026, 9, 7);

  group('WeekHelpers', () {
    test('第 n 周的周一 / 周日', () {
      expect(WeekHelpers.weekStart(1, termStart), DateTime(2026, 9, 7));
      expect(WeekHelpers.weekEnd(1, termStart), DateTime(2026, 9, 13));
      expect(WeekHelpers.weekStart(6, termStart), DateTime(2026, 10, 12));
    });

    test('日期区间 → 周次', () {
      expect(
        WeekHelpers.weeksFromDateRange(
          DateTime(2026, 10, 12),
          DateTime(2026, 11, 22),
          termStart,
        ),
        '6-11',
      );
      // 同一周内
      expect(
        WeekHelpers.weeksFromDateRange(
          DateTime(2026, 10, 12),
          DateTime(2026, 10, 18),
          termStart,
        ),
        '6',
      );
      // 开学之前
      expect(
        WeekHelpers.weeksFromDateRange(
          DateTime(2026, 8, 1),
          DateTime(2026, 8, 20),
          termStart,
        ),
        isNull,
      );
    });

    test('周次 → 日期区间描述', () {
      expect(WeekHelpers.describeWeeks('*', termStart), '每周');
      expect(
        WeekHelpers.describeWeeks('1-3,5-9', termStart),
        '第1-3周（9/7–9/27）、第5-9周（10/5–11/8）',
      );
      expect(
        WeekHelpers.describeWeeks('6', termStart),
        '第6周（10/12–10/18）',
      );
    });

    test('单周 / 双周展开成隔周', () {
      expect(
        WeekHelpers.describeWeeks('单', termStart, weekCount: 4),
        '第1周（9/7–9/13）、第3周（9/21–9/27）',
      );
      expect(
        WeekHelpers.describeWeeks('双', termStart, weekCount: 4),
        '第2周（9/14–9/20）、第4周（9/28–10/4）',
      );
    });

    test('没有学期起始日时原样返回', () {
      expect(WeekHelpers.describeWeeks('1-16', null), '1-16');
    });

    test('与 weekNumberFor 对得上', () {
      expect(weekNumberFor(DateTime(2026, 10, 12), termStart), 6);
      expect(weekNumberFor(DateTime(2026, 9, 7), termStart), 1);
    });
  });
}
