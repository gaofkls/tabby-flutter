import 'package:drift/drift.dart' hide Column;

import 'app_database.dart';
import 'occurrence.dart';
import 'reminder.dart';
import '../services/notification_service.dart';

/// 把未来的课程和备忘展开成一批系统提醒。
///
/// 课程按「星期 + 周次」规则展开成具体日期，备忘直接用 dueDate。
/// 每条记录各自的提醒规则优先，没有单独设置的用全局默认。
class ReminderScheduler {
  const ReminderScheduler(this._db);

  final AppDatabase _db;

  /// 排接下来 [days] 天的提醒，最多 [limit] 条（系统闹钟太多会拖慢）。
  List<ReminderTask> buildTasks({
    required DateTime now,
    required DateTime? termStart,
    required ReminderSpec defaultSpec,
    required List<Course> courses,
    required List<CourseSession> sessions,
    required List<Item> items,
    int days = 30,
    int limit = 400,
  }) {
    final courseById = {for (final c in courses) c.id: c};
    final from = DateTime(now.year, now.month, now.day);
    final tasks = <ReminderTask>[];

    for (var d = 0; d < days; d++) {
      final day = from.add(Duration(days: d));
      final week = weekNumberFor(day, termStart);

      for (final s in sessions) {
        if (s.weekday != day.weekday) continue;
        if (!weeksMatch(s.weeks, week)) continue;
        final course = courseById[s.courseId];
        if (course == null) continue;

        final spec =
            ReminderSpec.fromDb(course.reminderMode, course.reminderValue) ??
                defaultSpec;
        final start = day.add(Duration(minutes: s.startMinute));
        final at = spec.resolve(start);
        if (at == null || !at.isAfter(now)) continue;

        tasks.add(
          ReminderTask(
            title: course.name,
            body: _courseBody(course, s),
            scheduledAt: at,
            payload: 'course:${course.id}',
          ),
        );
      }

      for (final item in items) {
        final due = item.dueDate;
        if (due == null) continue;
        if (item.done) continue;
        if (!isSameDay(due, day)) continue;

        final spec =
            ReminderSpec.fromDb(item.reminderMode, item.reminderValue) ??
                defaultSpec;
        final start = day.add(Duration(minutes: item.dueMinute ?? 0));
        final at = spec.resolve(start);
        if (at == null || !at.isAfter(now)) continue;

        tasks.add(
          ReminderTask(
            title: item.title,
            body: _itemBody(item),
            scheduledAt: at,
            payload: 'item:${item.id}',
          ),
        );
      }
    }

    tasks.sort((a, b) => a.scheduledAt.compareTo(b.scheduledAt));
    return tasks.length > limit ? tasks.sublist(0, limit) : tasks;
  }

  /// 读库 + 展开 + 写系统闹钟。返回实际排了几条。
  Future<int> reschedule({DateTime? now, int days = 30}) async {
    final moment = now ?? DateTime.now();

    final term = await (_db.select(_db.terms)
          ..where((t) => t.isActive.equals(true))
          ..limit(1))
        .getSingleOrNull();

    final defaultSpec = await _db.defaultReminder();
    final courses =
        await (_db.select(_db.courses)..where((t) => t.deletedAt.isNull()))
            .get();
    final sessions = await (_db.select(_db.courseSessions)
          ..where((t) => t.deletedAt.isNull()))
        .get();
    final items = await (_db.select(_db.items)
          ..where((t) => t.deletedAt.isNull() & t.done.equals(false)))
        .get();

    final tasks = buildTasks(
      now: moment,
      termStart: term?.startDate,
      defaultSpec: defaultSpec,
      courses: courses,
      sessions: sessions,
      items: items,
      days: days,
    );

    return applyPlan(tasks);
  }

  /// 展开后的任务交给系统。
  Future<int> applyPlan(List<ReminderTask> tasks) =>
      NotificationService.instance.applyPlan(tasks);

  static String _courseBody(Course course, CourseSession s) {
    final when = _hm(s.startMinute);
    final where = (s.locationOverride ?? course.location ?? '').trim();
    if (where.isEmpty) return '今天 $when';
    return '今天 $when · $where';
  }

  static String _itemBody(Item item) {
    final minute = item.dueMinute;
    if (minute == null) return '今天';
    return '今天 ${_hm(minute)}';
  }

  static String _hm(int minute) {
    final m = minute % (24 * 60);
    return '${(m ~/ 60).toString().padLeft(2, '0')}:'
        '${(m % 60).toString().padLeft(2, '0')}';
  }
}
