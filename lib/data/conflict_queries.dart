import 'package:drift/drift.dart' hide Column;

import 'app_database.dart';
import 'occurrence.dart';

/// 冲突检测要用的现成数据。界面层不必自己拼 SQL。

Future<List<SessionWithCourse>> loadLiveSessions(AppDatabase db) async {
  final rows = await (db.select(db.courseSessions).join([
    innerJoin(db.courses, db.courses.id.equalsExp(db.courseSessions.courseId)),
  ])
        ..where(db.courseSessions.deletedAt.isNull()))
      .get();
  return rows
      .map(
        (row) => SessionWithCourse(
          session: row.readTable(db.courseSessions),
          course: row.readTable(db.courses),
        ),
      )
      .toList();
}

Future<List<Item>> loadLiveItems(AppDatabase db) async {
  return (db.select(db.items)
        ..where((t) => t.deletedAt.isNull()))
      .get();
}

Future<DateTime?> loadActiveTermStart(AppDatabase db) async {
  final term = await (db.select(db.terms)
        ..where((t) => t.isActive.equals(true))
        ..limit(1))
      .getSingleOrNull();
  return term?.startDate;
}
