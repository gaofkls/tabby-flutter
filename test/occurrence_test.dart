import 'package:flutter_test/flutter_test.dart';

import 'package:tabby/data/app_database.dart';
import 'package:tabby/data/occurrence.dart';

void main() {
  final now = DateTime.now();

  Course course(String id, String name, {int? color}) => Course(
        id: id,
        name: name,
        color: color,
        updatedAt: now,
      );

  CourseSession session(
    String id,
    String courseId,
    int weekday,
    int start,
    int end, {
    String weeks = '*',
  }) =>
      CourseSession(
        id: id,
        courseId: courseId,
        weekday: weekday,
        startMinute: start,
        endMinute: end,
        weeks: weeks,
        updatedAt: now,
      );

  Item item(
    String id,
    String title, {
    DateTime? dueDate,
    int? dueMinute,
  }) =>
      Item(
        id: id,
        title: title,
        dueDate: dueDate,
        dueMinute: dueMinute,
        done: false,
        updatedAt: now,
      );

  test('周次规则匹配', () {
    expect(weeksMatch('*', 3), isTrue);
    expect(weeksMatch('1-16', 5), isTrue);
    expect(weeksMatch('1-16', 17), isFalse);
    expect(weeksMatch('单', 3), isTrue);
    expect(weeksMatch('单', 4), isFalse);
    expect(weeksMatch('双', 4), isTrue);
    expect(weeksMatch('1,3,5', 3), isTrue);
    expect(weeksMatch('1,3,5', 2), isFalse);
    // 没有学期起始日时不做过滤
    expect(weeksMatch('1-2', null), isTrue);
  });

  test('周次展开：课程落到对应星期，周次不符的不出现', () {
    final monday = DateTime(2026, 10, 12); // 周一
    final sunday = monday.add(const Duration(days: 6));

    final set = buildOccurrences(
      from: monday,
      to: sunday,
      sessions: [
        SessionWithCourse(
          session: session('s1', 'c1', 1, 8 * 60, 9 * 60 + 40),
          course: course('c1', '高等数学'),
        ),
        SessionWithCourse(
          session: session('s2', 'c2', 3, 14 * 60, 15 * 60 + 40,
              weeks: '1-2'),
          course: course('c2', '只在两周内'),
        ),
      ],
      items: const [],
      termStart: monday, // 本周 = 第 1 周
    );

    final titles = set.timed.map((o) => o.title).toList();
    expect(titles, contains('高等数学'));

    // 第 1 周，'1-2' 应该还在
    expect(titles, contains('只在两周内'));

    // 换成第 5 周就不该出现了
    final week5 = buildOccurrences(
      from: monday.add(const Duration(days: 28)),
      to: monday.add(const Duration(days: 34)),
      sessions: [
        SessionWithCourse(
          session: session('s2', 'c2', 3, 14 * 60, 15 * 60 + 40,
              weeks: '1-2'),
          course: course('c2', '只在两周内'),
        ),
      ],
      items: const [],
      termStart: monday,
    );
    expect(week5.timed, isEmpty);
  });

  test('三种粒度的备忘分别落到时间轴 / 全天 / 不限时间', () {
    final day = DateTime(2026, 10, 13);
    final set = buildOccurrences(
      from: DateTime(2026, 10, 12),
      to: DateTime(2026, 10, 18),
      sessions: const [],
      items: [
        item('i1', '不限时间'),
        item('i2', '精确到天', dueDate: day),
        item('i3', '精确到小时', dueDate: day, dueMinute: 9 * 60),
      ],
    );

    expect(set.untimed.map((e) => e.title), ['不限时间']);
    expect(set.allDay.map((e) => e.title), ['精确到天']);

    final timed = set.timed.single;
    expect(timed.title, '精确到小时');
    expect(timed.startMinute, 9 * 60);
    expect(timed.endMinute, 10 * 60);
    expect(timed.item?.id, 'i3');
  });

  test('区间外的备忘不会被展开出来', () {
    final set = buildOccurrences(
      from: DateTime(2026, 10, 12),
      to: DateTime(2026, 10, 18),
      sessions: const [],
      items: [
        item('i1', '下个月的', dueDate: DateTime(2026, 11, 20)),
      ],
    );
    expect(set.timed, isEmpty);
    expect(set.allDay, isEmpty);
  });
}
