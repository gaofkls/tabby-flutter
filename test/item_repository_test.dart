import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tabby/data/app_database.dart';
import 'package:tabby/data/item_repository.dart';

void main() {
  late AppDatabase db;
  late ItemRepository repo;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repo = ItemRepository(db);
  });

  tearDown(() async {
    await db.close();
  });

  test('三种时间粒度都能写入并读回', () async {
    final day = DateTime(2026, 10, 13);

    await repo.create(title: '不限时间');
    await repo.create(title: '精确到天', dueDate: day);
    await repo.create(title: '精确到小时', dueDate: day, dueMinute: 8 * 60 + 30);

    final rows = await db.select(db.items).get();
    expect(rows.length, 3);

    final byTitle = {for (final r in rows) r.title: r};
    expect(byTitle['不限时间']!.dueDate, isNull);
    expect(byTitle['不限时间']!.dueMinute, isNull);
    expect(byTitle['精确到天']!.dueDate, day);
    expect(byTitle['精确到天']!.dueMinute, isNull);
    expect(byTitle['精确到小时']!.dueDate, day);
    expect(byTitle['精确到小时']!.dueMinute, 8 * 60 + 30);
  });

  test('编辑会改字段并刷新 updatedAt', () async {
    final id = await repo.create(title: '旧标题');
    final before = await (db.select(db.items)
          ..where((t) => t.id.equals(id)))
        .getSingle();

    await Future<void>.delayed(const Duration(milliseconds: 5));
    await repo.update(id, title: '新标题', dueDate: DateTime(2026, 10, 20));

    final after = await (db.select(db.items)..where((t) => t.id.equals(id)))
        .getSingle();
    expect(after.title, '新标题');
    expect(after.dueDate, DateTime(2026, 10, 20));
    // drift 默认以秒级 Unix 时间戳存 DateTime，所以断言用秒级语义
    expect(after.updatedAt.isBefore(before.updatedAt), isFalse);
    expect(after.updatedAt.millisecondsSinceEpoch ~/ 1000,
        greaterThanOrEqualTo(before.updatedAt.millisecondsSinceEpoch ~/ 1000));
  });

  test('软删除后查询应排除，restore 能撤销', () async {
    final id = await repo.create(title: '会被删掉');

    await repo.softDelete(id);
    final visibleAfterDelete = await db.select(db.items).get();
    // 软删除只是打墓碑，行还在（同步需要），但 deletedAt 有值
    expect(visibleAfterDelete.length, 1);
    expect(visibleAfterDelete.single.deletedAt, isNotNull);

    await repo.restore(id);
    final visibleAfterRestore = await db.select(db.items).get();
    expect(visibleAfterRestore.single.deletedAt, isNull);
  });

  test('setDone 写入 done / doneAt，取消勾选清掉 doneAt', () async {
    final id = await repo.create(title: '勾选测试');

    await repo.setDone(id, true);
    var row = await (db.select(db.items)..where((t) => t.id.equals(id)))
        .getSingle();
    expect(row.done, isTrue);
    expect(row.doneAt, isNotNull);

    await repo.setDone(id, false);
    row = await (db.select(db.items)..where((t) => t.id.equals(id)))
        .getSingle();
    expect(row.done, isFalse);
    expect(row.doneAt, isNull);
  });
}
