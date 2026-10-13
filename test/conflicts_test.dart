import 'package:flutter_test/flutter_test.dart';
import 'package:tabby/data/app_database.dart';
import 'package:tabby/data/conflicts.dart';
import 'package:tabby/data/occurrence.dart';
import 'package:tabby/data/session_input.dart';

SessionWithCourse _course({
  required String id,
  required String name,
  required int weekday,
  required int start,
  required int end,
  String weeks = '*',
}) {
  return SessionWithCourse(
    session: CourseSession(
      id: '$id-session',
      courseId: id,
      weekday: weekday,
      startMinute: start,
      endMinute: end,
      weeks: weeks,
      updatedAt: DateTime(2026, 10, 1),
    ),
    course: Course(
      id: id,
      name: name,
      updatedAt: DateTime(2026, 10, 1),
    ),
  );
}

Item _item({
  required String id,
  required String title,
  required DateTime due,
  int? minute,
  bool done = false,
}) {
  return Item(
    id: id,
    title: title,
    dueDate: due,
    dueMinute: minute,
    done: done,
    updatedAt: DateTime(2026, 10, 1),
  );
}

void main() {
  group('findCourseConflicts', () {
    // 学期第 1 周从 2026-09-07（周一）开始，2026-10-12 是第 6 周周一
    final termStart = DateTime(2026, 9, 7);

    test('同一天时间重叠才报冲突', () {
      final existing = [
        _course(id: 'math', name: '高等数学', weekday: 1, start: 480, end: 580),
      ];

      final conflicts = findCourseConflicts(
        sessions: [
          const SessionInput(weekday: 1, startMinute: 540, endMinute: 620),
        ],
        existingSessions: existing,
        existingItems: const [],
        termStart: termStart,
      );

      expect(conflicts, hasLength(1));
      expect(conflicts.single.title, '高等数学');
      expect(conflicts.single.kind, '课程');
      expect(conflicts.single.detail, contains('08:00'));
    });

    test('不同星期不冲突', () {
      final existing = [
        _course(id: 'math', name: '高等数学', weekday: 1, start: 480, end: 580),
      ];

      final conflicts = findCourseConflicts(
        sessions: [
          const SessionInput(weekday: 3, startMinute: 480, endMinute: 580),
        ],
        existingSessions: existing,
        existingItems: const [],
        termStart: termStart,
      );

      expect(conflicts, isEmpty);
    });

    test('首尾相接不算冲突', () {
      final existing = [
        _course(id: 'math', name: '高等数学', weekday: 1, start: 480, end: 580),
      ];

      final conflicts = findCourseConflicts(
        sessions: [
          const SessionInput(weekday: 1, startMinute: 580, endMinute: 660),
        ],
        existingSessions: existing,
        existingItems: const [],
        termStart: termStart,
      );

      expect(conflicts, isEmpty);
    });

    test('周次没有交集就不算冲突', () {
      final existing = [
        _course(
          id: 'math',
          name: '高等数学',
          weekday: 1,
          start: 480,
          end: 580,
          weeks: '1-4',
        ),
      ];

      final conflicts = findCourseConflicts(
        sessions: [
          const SessionInput(
            weekday: 1,
            startMinute: 540,
            endMinute: 620,
            weeks: '5-8',
          ),
        ],
        existingSessions: existing,
        existingItems: const [],
        termStart: termStart,
      );

      expect(conflicts, isEmpty);
    });

    test('周次有交集就报冲突', () {
      final existing = [
        _course(
          id: 'math',
          name: '高等数学',
          weekday: 1,
          start: 480,
          end: 580,
          weeks: '1-8',
        ),
      ];

      final conflicts = findCourseConflicts(
        sessions: [
          const SessionInput(
            weekday: 1,
            startMinute: 540,
            endMinute: 620,
            weeks: '5-8',
          ),
        ],
        existingSessions: existing,
        existingItems: const [],
        termStart: termStart,
      );

      expect(conflicts, hasLength(1));
    });

    test('编辑自己时不跟自己冲突', () {
      final existing = [
        _course(id: 'math', name: '高等数学', weekday: 1, start: 480, end: 580),
      ];

      final conflicts = findCourseConflicts(
        sessions: [
          const SessionInput(weekday: 1, startMinute: 480, endMinute: 580),
        ],
        existingSessions: existing,
        existingItems: const [],
        termStart: termStart,
        ignoreCourseId: 'math',
      );

      expect(conflicts, isEmpty);
    });

    test('同一门课自己的两个时段重叠', () {
      final conflicts = findCourseConflicts(
        sessions: const [
          SessionInput(weekday: 1, startMinute: 480, endMinute: 580),
          SessionInput(weekday: 1, startMinute: 540, endMinute: 620),
        ],
        existingSessions: const [],
        existingItems: const [],
        termStart: termStart,
      );

      expect(conflicts, hasLength(1));
      expect(conflicts.single.kind, '本课程');
    });

    test('跟精确到小时的备忘撞', () {
      final existing = [
        _course(id: 'math', name: '高等数学', weekday: 1, start: 480, end: 580),
      ];
      final items = [
        // 2026-10-12 是周一，第 6 周，14:00 的备忘
        _item(
          id: 'item-1',
          title: '交作业',
          due: DateTime(2026, 10, 12),
          minute: 14 * 60,
        ),
      ];

      final conflicts = findCourseConflicts(
        sessions: [
          const SessionInput(weekday: 1, startMinute: 830, endMinute: 920),
        ],
        existingSessions: existing,
        existingItems: items,
        termStart: termStart,
      );

      expect(conflicts, hasLength(1));
      expect(conflicts.single.kind, '备忘');
      expect(conflicts.single.title, '交作业');
    });

    test('跟精确到天的备忘不撞', () {
      final items = [
        _item(id: 'item-1', title: '交作业', due: DateTime(2026, 10, 12)),
      ];

      final conflicts = findCourseConflicts(
        sessions: [
          const SessionInput(weekday: 1, startMinute: 830, endMinute: 920),
        ],
        existingSessions: const [],
        existingItems: items,
        termStart: termStart,
      );

      expect(conflicts, isEmpty);
    });
  });

  group('findItemConflicts', () {
    final termStart = DateTime(2026, 9, 7);

    test('跟课程撞', () {
      final sessions = [
        _course(id: 'math', name: '高等数学', weekday: 1, start: 480, end: 580),
      ];

      final conflicts = findItemConflicts(
        candidate: _item(
          id: 'new',
          title: '写报告',
          due: DateTime(2026, 10, 12),
          minute: 500,
        ),
        existingSessions: sessions,
        existingItems: const [],
        termStart: termStart,
      );

      expect(conflicts, hasLength(1));
      expect(conflicts.single.kind, '课程');
      expect(conflicts.single.title, '高等数学');
    });

    test('跟别的备忘撞', () {
      final conflicts = findItemConflicts(
        candidate: _item(
          id: 'new',
          title: '写报告',
          due: DateTime(2026, 10, 12),
          minute: 14 * 60,
        ),
        existingSessions: const [],
        existingItems: [
          _item(
            id: 'other',
            title: '开会',
            due: DateTime(2026, 10, 12),
            minute: 14 * 60 + 30,
          ),
        ],
        termStart: termStart,
      );

      expect(conflicts, hasLength(1));
      expect(conflicts.single.kind, '备忘');
      expect(conflicts.single.title, '开会');
    });

    test('编辑自己时不算跟自己撞', () {
      final candidate = _item(
        id: 'me',
        title: '写报告',
        due: DateTime(2026, 10, 12),
        minute: 14 * 60,
      );

      final conflicts = findItemConflicts(
        candidate: candidate,
        existingSessions: const [],
        existingItems: [candidate],
        termStart: termStart,
      );

      expect(conflicts, isEmpty);
    });

    test('不限时间 / 精确到天的备忘没有冲突', () {
      final conflicts = findItemConflicts(
        candidate: _item(
          id: 'new',
          title: '不限时间',
          due: DateTime(2026, 10, 12),
        ),
        existingSessions: const [],
        existingItems: const [],
        termStart: termStart,
      );
      expect(conflicts, isEmpty);

      final noDate = findItemConflicts(
        candidate: Item(
          id: 'new',
          title: '没日期',
          done: false,
          updatedAt: DateTime(2026, 10, 1),
        ),
        existingSessions: const [],
        existingItems: const [],
        termStart: termStart,
      );
      expect(noDate, isEmpty);
    });
  });
}
