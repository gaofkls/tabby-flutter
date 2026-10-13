import 'package:drift/drift.dart' hide Column;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/router.dart';
import '../../data/app_database.dart';

/// 未删除的全部备忘。数据量小，粒度分档在 Dart 里做，
/// 避免 SQLite 处理日期边界时出岔子。
final itemsProvider = StreamProvider<List<Item>>((ref) {
  final db = ref.watch(databaseProvider);
  final query = db.select(db.items)
    ..where((t) => t.deletedAt.isNull())
    ..orderBy([
      (t) => OrderingTerm.asc(t.dueMinute),
      (t) => OrderingTerm.asc(t.dueDate),
    ]);
  return query.watch();
});

/// 去掉时分秒，只留年月日，用来做日期分组和比较。
DateTime dateKey(DateTime date) => DateTime(date.year, date.month, date.day);

bool isSameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;
