import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tabby/data/app_database.dart';
import 'package:tabby/data/reminder.dart';
import 'package:tabby/data/reminder_scheduler.dart';
import 'package:tabby/services/notification_service.dart';

Course _course({
  required String id,
  required String name,
  int? reminderMode,
  int? reminderValue,
}) {
  return Course(
    id: id,
    name: name,
    reminderMode: reminderMode,
    reminderValue: reminderValue,
    updatedAt: DateTime(2026, 10, 1),
  );
}

CourseSession _session({
  required String id,
  required String courseId,
  required int weekday,
  required int startMinute,
  int endMinute = 660,
  String weeks = '*',
}) {
  return CourseSession(
    id: id,
    courseId: courseId,
    weekday: weekday,
    startMinute: startMinute,
    endMinute: endMinute,
    weeks: weeks,
    updatedAt: DateTime(2026, 10, 1),
  );
}

Item _item({
  required String id,
  required String title,
  DateTime? dueDate,
  int? dueMinute,
  int? reminderMode,
  int? reminderValue,
  bool done = false,
}) {
  return Item(
    id: id,
    title: title,
    dueDate: dueDate,
    dueMinute: dueMinute,
    reminderMode: reminderMode,
    reminderValue: reminderValue,
    done: done,
    updatedAt: DateTime(2026, 10, 1),
  );
}

List<ReminderTask> _plan({
  required DateTime now,
  List<Course> courses = const [],
  List<CourseSession> sessions = const [],
  List<Item> items = const [],
  ReminderSpec defaultSpec = ReminderSpec.defaultValue,
  int days = 8,
}) {
  final scheduler = ReminderScheduler(_fakeDb);
  return scheduler.buildTasks(
    now: now,
    termStart: DateTime(2026, 9, 7), // 第 1 周周一
    defaultSpec: defaultSpec,
    courses: courses,
    sessions: sessions,
    items: items,
    days: days,
  );
}

/// buildTasks 不碰数据库，这里用内存库占个位（不会被调用）。
final AppDatabase _fakeDb = AppDatabase(NativeDatabase.memory());

void main() {
  group('ReminderScheduler.buildTasks', () {
    // 2026-10-12 是周一，第 6 周
    final now = DateTime(2026, 10, 12, 10, 0);

    test('课程按默认「前一天 21:00」展开', () {
      final tasks = _plan(
        now: now,
        courses: [_course(id: 'math', name: '高等数学')],
        sessions: [
          _session(id: 's1', courseId: 'math', weekday: 1, startMinute: 480),
        ],
      );

      expect(tasks, hasLength(1));
      expect(tasks.single.title, '高等数学');
      // 下周一（10-19）上课，提醒在 10-18 21:00
      expect(tasks.single.scheduledAt, DateTime(2026, 10, 18, 21));
      expect(tasks.single.body, contains('08:00'));
    });

    test('课程自己的「提前 30 分钟」优先于默认', () {
      final tasks = _plan(
        now: now,
        courses: [
          _course(
            id: 'math',
            name: '高等数学',
            reminderMode: 1,
            reminderValue: 30,
          ),
        ],
        sessions: [
          _session(id: 's1', courseId: 'math', weekday: 1, startMinute: 480),
        ],
      );

      expect(tasks, hasLength(1));
      expect(tasks.single.scheduledAt, DateTime(2026, 10, 19, 7, 30));
    });

    test('课程设成「不提醒」就不排', () {
      final tasks = _plan(
        now: now,
        courses: [
          _course(
            id: 'math',
            name: '高等数学',
            reminderMode: 0,
            reminderValue: null,
          ),
        ],
        sessions: [
          _session(id: 's1', courseId: 'math', weekday: 1, startMinute: 480),
        ],
      );

      expect(tasks, isEmpty);
    });

    test('周次过滤生效：第 6 周的课不再排', () {
      final tasks = _plan(
        now: now,
        courses: [_course(id: 'math', name: '高等数学')],
        sessions: [
          _session(
            id: 's1',
            courseId: 'math',
            weekday: 1,
            startMinute: 480,
            weeks: '1-5',
          ),
        ],
      );

      expect(tasks, isEmpty);
    });

    test('单双周规则生效', () {
      final tasks = _plan(
        now: now,
        courses: [_course(id: 'math', name: '高等数学')],
        sessions: [
          _session(
            id: 's1',
            courseId: 'math',
            weekday: 1,
            startMinute: 480,
            weeks: '单',
          ),
        ],
      );

      // 第 6 周之后的单周是第 7 周 → 2026-10-19 是第 7 周
      expect(tasks, hasLength(1));
      expect(tasks.single.scheduledAt, DateTime(2026, 10, 18, 21));
    });

    test('过去的提醒不排', () {
      final tasks = _plan(
        now: DateTime(2026, 10, 12, 22, 0),
        courses: [_course(id: 'math', name: '高等数学')],
        sessions: [
          _session(id: 's1', courseId: 'math', weekday: 1, startMinute: 480),
        ],
      );

      // 当天 22 点时，今天 8 点的课已经上完，它的提醒（10-11 21:00）也过了，
      // 只剩下一节课的提醒
      expect(tasks, hasLength(1));
      expect(tasks.single.scheduledAt, DateTime(2026, 10, 18, 21));
    });

    test('精确到小时的备忘', () {
      final tasks = _plan(
        now: now,
        items: [
          _item(
            id: 'i1',
            title: '交作业',
            dueDate: DateTime(2026, 10, 13),
            dueMinute: 14 * 60,
          ),
        ],
      );

      expect(tasks, hasLength(1));
      expect(tasks.single.title, '交作业');
      expect(tasks.single.scheduledAt, DateTime(2026, 10, 12, 21));
      expect(tasks.single.body, contains('14:00'));
    });

    test('精确到天的备忘也走「前一天晚上」', () {
      final tasks = _plan(
        now: now,
        items: [
          _item(id: 'i1', title: '买书', dueDate: DateTime(2026, 10, 13)),
        ],
      );

      expect(tasks, hasLength(1));
      expect(tasks.single.scheduledAt, DateTime(2026, 10, 12, 21));
      expect(tasks.single.body, '今天');
    });

    test('不限时间的备忘没有日期，排不出来', () {
      final tasks = _plan(
        now: now,
        items: [_item(id: 'i1', title: '随便')],
      );

      expect(tasks, isEmpty);
    });

    test('已完成的备忘不排', () {
      final tasks = _plan(
        now: now,
        items: [
          _item(
            id: 'i1',
            title: '交作业',
            dueDate: DateTime(2026, 10, 13),
            dueMinute: 14 * 60,
            done: true,
          ),
        ],
      );

      expect(tasks, isEmpty);
    });

    test('备忘自己的提醒规则优先', () {
      final tasks = _plan(
        now: now,
        items: [
          _item(
            id: 'i1',
            title: '交作业',
            dueDate: DateTime(2026, 10, 13),
            dueMinute: 14 * 60,
            reminderMode: 1,
            reminderValue: 60,
          ),
        ],
      );

      expect(tasks, hasLength(1));
      expect(tasks.single.scheduledAt, DateTime(2026, 10, 13, 13));
    });

    test('超过窗口天数的忽略，按时间排序', () {
      final tasks = _plan(
        now: now,
        days: 2,
        items: [
          _item(
            id: 'far',
            title: '下个月',
            dueDate: DateTime(2026, 11, 13),
            dueMinute: 600,
          ),
          _item(
            id: 'near',
            title: '明天',
            dueDate: DateTime(2026, 10, 13),
            dueMinute: 600,
          ),
        ],
      );

      expect(tasks, hasLength(1));
      expect(tasks.single.title, '明天');
    });

    test('全局默认改成「提前 15 分钟」后，没有单独设置的都跟着变', () {
      final tasks = _plan(
        now: now,
        defaultSpec: const ReminderSpec.before(15),
        courses: [_course(id: 'math', name: '高等数学')],
        sessions: [
          _session(id: 's1', courseId: 'math', weekday: 1, startMinute: 480),
        ],
      );

      expect(tasks.single.scheduledAt, DateTime(2026, 10, 19, 7, 45));
    });
  });
}
