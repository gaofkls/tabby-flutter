import 'package:drift/drift.dart' hide Column;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../app/router.dart';
import 'app_database.dart';
import 'reminder.dart';
import 'session_input.dart';

/// 课程的读写入口。一门课可以带多个上课时段。
/// 删除一律走软删除（写 deletedAt），将来同步时删除才能作为事件传出去。
class CourseRepository {
  const CourseRepository(this._db);

  final AppDatabase _db;

  Future<String?> _activeTermId() async {
    final term = await (_db.select(_db.terms)
          ..where((t) => t.isActive.equals(true))
          ..limit(1))
        .getSingleOrNull();
    return term?.id;
  }

  Future<String> create({
    required String name,
    String? teacher,
    String? location,
    int? color,
    required List<SessionInput> sessions,
    ReminderSpec? reminder,
  }) async {
    final id = const Uuid().v4();
    final now = DateTime.now();
    final termId = await _activeTermId();

    await _db.transaction(() async {
      await _db.into(_db.courses).insert(
            CoursesCompanion.insert(
              id: id,
              termId: Value(termId),
              name: name,
              teacher: Value(teacher),
              location: Value(location),
              color: Value(color),
              reminderMode: Value(reminder?.mode.index),
              reminderValue: Value(reminder?.value),
              updatedAt: now,
            ),
          );
      await _insertSessions(id, sessions, now);
    });
    return id;
  }

  Future<void> update(
    String id, {
    required String name,
    String? teacher,
    String? location,
    int? color,
    required List<SessionInput> sessions,
    ReminderSpec? reminder,
  }) async {
    final now = DateTime.now();
    await _db.transaction(() async {
      await (_db.update(_db.courses)..where((t) => t.id.equals(id))).write(
        CoursesCompanion(
          name: Value(name),
          teacher: Value(teacher),
          location: Value(location),
          color: Value(color),
          reminderMode: Value(reminder?.mode.index),
          reminderValue: Value(reminder?.value),
          updatedAt: Value(now),
        ),
      );

      // 旧时段打墓碑，再写新的（保留删除事件，便于将来同步）
      await (_db.update(_db.courseSessions)
            ..where((t) => t.courseId.equals(id)))
          .write(
        CourseSessionsCompanion(
          deletedAt: Value(now),
          updatedAt: Value(now),
        ),
      );
      await _insertSessions(id, sessions, now);
    });
  }

  Future<void> _insertSessions(
    String courseId,
    List<SessionInput> sessions,
    DateTime now,
  ) async {
    for (final s in sessions) {
      await _db.into(_db.courseSessions).insert(
            CourseSessionsCompanion.insert(
              id: const Uuid().v4(),
              courseId: courseId,
              weekday: s.weekday,
              startMinute: s.startMinute,
              endMinute: s.endMinute,
              weeks: Value(s.weeks),
              updatedAt: now,
            ),
          );
    }
  }

  /// 只改提醒规则（课表上快速设置用）。
  Future<void> setReminder(String id, ReminderSpec? spec) async {
    await (_db.update(_db.courses)..where((t) => t.id.equals(id))).write(
      CoursesCompanion(
        reminderMode: Value(spec?.mode.index),
        reminderValue: Value(spec?.value),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  Future<void> softDelete(String id) async {
    final now = DateTime.now();
    await _db.transaction(() async {
      await (_db.update(_db.courses)..where((t) => t.id.equals(id))).write(
        CoursesCompanion(deletedAt: Value(now), updatedAt: Value(now)),
      );
      await (_db.update(_db.courseSessions)
            ..where((t) => t.courseId.equals(id)))
          .write(
        CourseSessionsCompanion(
          deletedAt: Value(now),
          updatedAt: Value(now),
        ),
      );
    });
  }

  Future<void> restore(String id) async {
    final now = DateTime.now();
    await _db.transaction(() async {
      await (_db.update(_db.courses)..where((t) => t.id.equals(id))).write(
        CoursesCompanion(
          deletedAt: const Value(null),
          updatedAt: Value(now),
        ),
      );
      await (_db.update(_db.courseSessions)
            ..where((t) => t.courseId.equals(id)))
          .write(
        CourseSessionsCompanion(
          deletedAt: const Value(null),
          updatedAt: Value(now),
        ),
      );
    });
  }

  /// 导入：同名课程合并成一门，多个时段挂在它下面。
  Future<int> importEntries(List<ImportEntry> entries) async {
    final grouped = <String, List<ImportEntry>>{};
    for (final e in entries) {
      grouped.putIfAbsent(e.name.trim(), () => []).add(e);
    }

    var count = 0;
    for (final entry in grouped.entries) {
      final sessions = <SessionInput>[];
      final seen = <String>{};
      for (final e in entry.value) {
        final key = '${e.weekday}-${e.startMinute}-${e.endMinute}-${e.weeks}';
        if (!seen.add(key)) continue;
        sessions.add(
          SessionInput(
            weekday: e.weekday,
            startMinute: e.startMinute,
            endMinute: e.endMinute,
            weeks: e.weeks,
          ),
        );
      }
      final first = entry.value.first;
      await create(
        name: entry.key,
        teacher: first.teacher,
        location: first.location,
        sessions: sessions,
      );
      count++;
    }
    return count;
  }
}

/// 导入解析出来的一条上课安排。
class ImportEntry {
  const ImportEntry({
    required this.name,
    required this.weekday,
    required this.startMinute,
    required this.endMinute,
    this.teacher,
    this.location,
    this.weeks = '*',
    this.raw = '',
    this.warning,
  });

  final String name;
  final int weekday;
  final int startMinute;
  final int endMinute;
  final String? teacher;
  final String? location;
  final String weeks;
  final String raw;

  /// 解析时拿不准的地方（比如没识别出教室），导入预览里会标出来
  final String? warning;
}

final courseRepositoryProvider = Provider<CourseRepository>((ref) {
  return CourseRepository(ref.watch(databaseProvider));
});
