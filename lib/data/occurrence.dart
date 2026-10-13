import 'package:drift/drift.dart' hide Column;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/router.dart';
import 'app_database.dart';

/// 课程时段 + 它所属的课程，渲染课表时两者都要用。
class SessionWithCourse {
  const SessionWithCourse({required this.session, required this.course});

  final CourseSession session;
  final Course course;
}

final sessionsWithCourseProvider = StreamProvider<List<SessionWithCourse>>((ref) {
  final db = ref.watch(databaseProvider);
  final query = db.select(db.courseSessions).join([
    innerJoin(db.courses, db.courses.id.equalsExp(db.courseSessions.courseId)),
  ])
    ..where(db.courseSessions.deletedAt.isNull())
    ..orderBy([OrderingTerm.asc(db.courseSessions.startMinute)]);

  return query.watch().map((rows) {
    return rows
        .map(
          (row) => SessionWithCourse(
            session: row.readTable(db.courseSessions),
            course: row.readTable(db.courses),
          ),
        )
        .toList();
  });
});

final activeTermProvider = StreamProvider<Term?>((ref) {
  final db = ref.watch(databaseProvider);
  return (db.select(db.terms)
        ..where((t) => t.isActive.equals(true))
        ..limit(1))
      .watchSingleOrNull();
});

enum OccurrenceKind { course, memo }

/// 视图层统一的一条「发生实例」。
/// 课程按星期规则展开成多个实例，备忘按 dueDate 落成单个实例。
/// startMinute 为 null 表示它是「当天但不占时间轴」的条目。
class Occurrence {
  const Occurrence({
    required this.key,
    required this.title,
    required this.date,
    required this.kind,
    this.subtitle,
    this.startMinute,
    this.endMinute,
    this.colorValue,
    this.courseId,
    this.item,
    this.done = false,
  });

  final String key;
  final String title;
  final String? subtitle;
  final DateTime date;
  final int? startMinute;
  final int? endMinute;
  final OccurrenceKind kind;
  final int? colorValue;

  /// 来源是课程时带上 course id，方便点格子直接打开课程编辑
  final String? courseId;

  /// 来源是备忘时带上原始记录，方便直接调起编辑面板。
  final Item? item;
  final bool done;

  bool get isTimed => startMinute != null;

  bool get isCourse => kind == OccurrenceKind.course;
}

class OccurrenceSet {
  const OccurrenceSet({
    required this.timed,
    required this.allDay,
    required this.untimed,
  });

  /// 有具体时间段，画进时间轴格子
  final List<Occurrence> timed;

  /// 落在某一天，但不占时间轴（精确到天的备忘）
  final List<Occurrence> allDay;

  /// 连日期都没有的备忘（不限时间）
  final List<Item> untimed;

  bool get isEmpty => timed.isEmpty && allDay.isEmpty && untimed.isEmpty;
}

/// 把课程规则 + 备忘展开成某个日期区间内的实例集合。
OccurrenceSet buildOccurrences({
  required DateTime from,
  required DateTime to,
  required List<SessionWithCourse> sessions,
  required List<Item> items,
  DateTime? termStart,
}) {
  final dayFrom = DateTime(from.year, from.month, from.day);
  final dayTo = DateTime(to.year, to.month, to.day);

  final timed = <Occurrence>[];
  final allDay = <Occurrence>[];
  final untimed = <Item>[];

  // 课程：按 weekday 落进区间内的每一天，再用周次规则过滤
  var cursor = dayFrom;
  while (!cursor.isAfter(dayTo)) {
    final weekday = cursor.weekday; // 1=周一 … 7=周日
    final week = weekNumberFor(cursor, termStart);

    for (final entry in sessions) {
      final s = entry.session;
      if (s.weekday != weekday) continue;
      if (!weeksMatch(s.weeks, week)) continue;

      timed.add(
        Occurrence(
          key: 'session:${s.id}:${cursor.millisecondsSinceEpoch}',
          title: entry.course.name,
          subtitle: s.locationOverride ?? entry.course.location,
          date: cursor,
          startMinute: s.startMinute,
          endMinute: s.endMinute,
          kind: OccurrenceKind.course,
          colorValue: entry.course.color,
          courseId: entry.course.id,
        ),
      );
    }
    cursor = cursor.add(const Duration(days: 1));
  }

  // 备忘：按 dueDate 落进区间
  for (final item in items) {
    final due = item.dueDate;
    if (due == null) {
      if (item.dueMinute == null) {
        untimed.add(item);
      }
      continue;
    }
    final day = DateTime(due.year, due.month, due.day);
    if (day.isBefore(dayFrom) || day.isAfter(dayTo)) continue;

    final occurrence = Occurrence(
      key: 'item:${item.id}',
      title: item.title,
      subtitle: item.note,
      date: day,
      startMinute: item.dueMinute,
      endMinute: item.dueMinute == null ? null : item.dueMinute! + 60,
      kind: OccurrenceKind.memo,
      item: item,
      done: item.done,
    );
    if (item.dueMinute == null) {
      allDay.add(occurrence);
    } else {
      timed.add(occurrence);
    }
  }

  timed.sort((a, b) {
    final byMinute = (a.startMinute ?? 0).compareTo(b.startMinute ?? 0);
    if (byMinute != 0) return byMinute;
    return a.date.compareTo(b.date);
  });

  return OccurrenceSet(timed: timed, allDay: allDay, untimed: untimed);
}

/// 第几教学周。没有学期起始日就返回 null（不做周次过滤）。
int? weekNumberFor(DateTime date, DateTime? termStart) {
  if (termStart == null) return null;
  final start = DateTime(termStart.year, termStart.month, termStart.day);
  final day = DateTime(date.year, date.month, date.day);
  final diff = day.difference(start).inDays;
  if (diff < 0) return null;
  return diff ~/ 7 + 1;
}

/// 周次规则匹配：支持 '*'、'1-16'、'单'、'双'、'1,3,5'。
bool weeksMatch(String spec, int? week) {
  final s = spec.trim();
  if (s.isEmpty || s == '*') return true;
  if (week == null) return true;

  for (final token in s.split(',')) {
    final t = token.trim();
    if (t.isEmpty) continue;
    if (t == '单') {
      if (week.isOdd) return true;
      continue;
    }
    if (t == '双') {
      if (week.isEven) return true;
      continue;
    }
    if (t.contains('-')) {
      final parts = t.split('-');
      if (parts.length == 2) {
        final a = int.tryParse(parts[0].trim());
        final b = int.tryParse(parts[1].trim());
        if (a != null && b != null && week >= a && week <= b) return true;
      }
      continue;
    }
    final n = int.tryParse(t);
    if (n != null && n == week) return true;
  }
  return false;
}

/// 取所在周的周一。
DateTime startOfWeek(DateTime date) {
  final day = DateTime(date.year, date.month, date.day);
  return day.subtract(Duration(days: day.weekday - 1));
}

/// 取所在月的 1 号。
DateTime startOfMonth(DateTime date) => DateTime(date.year, date.month, 1);

DateTime dateOnly(DateTime date) => DateTime(date.year, date.month, date.day);

bool isSameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;
