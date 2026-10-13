import 'package:drift/drift.dart' hide Column;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../app/router.dart';
import 'app_database.dart';
import 'reminder.dart';

/// 备忘的读写入口。所有删除都是软删除（写 deletedAt），
/// 这样将来接多端同步时，「删除」也能作为一个事件同步出去。
class ItemRepository {
  const ItemRepository(this._db);

  final AppDatabase _db;

  Future<String> create({
    required String title,
    String? note,
    DateTime? dueDate,
    int? dueMinute,
    ReminderSpec? reminder,
  }) async {
    final id = const Uuid().v4();
    await _db.into(_db.items).insert(
          ItemsCompanion.insert(
            id: id,
            title: title,
            note: Value(note),
            dueDate: Value(dueDate),
            dueMinute: Value(dueMinute),
            reminderMode: Value(reminder?.mode.index),
            reminderValue: Value(reminder?.value),
            updatedAt: DateTime.now(),
          ),
        );
    return id;
  }

  Future<void> update(
    String id, {
    required String title,
    String? note,
    DateTime? dueDate,
    int? dueMinute,
    ReminderSpec? reminder,
  }) async {
    await (_db.update(_db.items)..where((t) => t.id.equals(id))).write(
      ItemsCompanion(
        title: Value(title),
        note: Value(note),
        dueDate: Value(dueDate),
        dueMinute: Value(dueMinute),
        reminderMode: Value(reminder?.mode.index),
        reminderValue: Value(reminder?.value),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  /// 只改提醒规则（列表里快速设置用）。
  Future<void> setReminder(String id, ReminderSpec? spec) async {
    await (_db.update(_db.items)..where((t) => t.id.equals(id))).write(
      ItemsCompanion(
        reminderMode: Value(spec?.mode.index),
        reminderValue: Value(spec?.value),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  Future<void> setDone(String id, bool done) async {
    await (_db.update(_db.items)..where((t) => t.id.equals(id))).write(
      ItemsCompanion(
        done: Value(done),
        doneAt: Value(done ? DateTime.now() : null),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  Future<void> softDelete(String id) async {
    await (_db.update(_db.items)..where((t) => t.id.equals(id))).write(
      ItemsCompanion(
        deletedAt: Value(DateTime.now()),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  /// 撤销删除：把墓碑清掉。
  Future<void> restore(String id) async {
    await (_db.update(_db.items)..where((t) => t.id.equals(id))).write(
      ItemsCompanion(
        deletedAt: const Value(null),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }
}

final itemRepositoryProvider = Provider<ItemRepository>((ref) {
  return ItemRepository(ref.watch(databaseProvider));
});
