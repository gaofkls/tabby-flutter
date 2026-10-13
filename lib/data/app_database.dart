import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

import 'reminder.dart';

part 'app_database.g.dart';

/// 学期。多端同步会用到 id / updatedAt / deletedAt，现在先埋好。
class Terms extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  DateTimeColumn get startDate => dateTime().nullable()();
  DateTimeColumn get endDate => dateTime().nullable()();
  IntColumn get weekCount => integer().withDefault(const Constant(20))();
  BoolColumn get isActive => boolean().withDefault(const Constant(false))();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// 课程。只存课程本身的元信息，上课时间放在 CourseSessions。
class Courses extends Table {
  TextColumn get id => text()();
  TextColumn get termId => text().nullable()();
  TextColumn get name => text()();
  TextColumn get teacher => text().nullable()();
  TextColumn get location => text().nullable()();
  IntColumn get color => integer().nullable()();
  TextColumn get note => text().nullable()();

  /// 提醒方式，null = 跟随全局默认。取值见 ReminderMode.index。
  IntColumn get reminderMode => integer().nullable()();

  /// 提醒参数：提前分钟数 / 前一天的分钟数（0 点起算）。
  IntColumn get reminderValue => integer().nullable()();

  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// 课程的一个上课时段：星期几 + 起止分钟 + 周次。
/// 起止时间用「当天 0 点起的分钟数」，方便排序和重叠计算。
class CourseSessions extends Table {
  TextColumn get id => text()();
  TextColumn get courseId => text()();
  IntColumn get weekday => integer()();
  IntColumn get startMinute => integer()();
  IntColumn get endMinute => integer()();
  TextColumn get weeks => text().withDefault(const Constant('*'))();
  TextColumn get locationOverride => text().nullable()();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// 备忘 / 待办。三种时间粒度用两个可空字段区分：
///   dueDate == null && dueMinute == null  -> 不限时间（进当天待办区）
///   dueDate != null && dueMinute == null  -> 精确到天（当天置顶，不占时间轴）
///   dueDate != null && dueMinute != null  -> 精确到小时（插入时间轴）
class Items extends Table {
  TextColumn get id => text()();
  TextColumn get title => text()();
  TextColumn get note => text().nullable()();
  DateTimeColumn get dueDate => dateTime().nullable()();
  IntColumn get dueMinute => integer().nullable()();
  TextColumn get courseId => text().nullable()();
  BoolColumn get done => boolean().withDefault(const Constant(false))();
  DateTimeColumn get doneAt => dateTime().nullable()();

  /// 提醒方式，null = 跟随全局默认。取值见 ReminderMode.index。
  IntColumn get reminderMode => integer().nullable()();

  /// 提醒参数：提前分钟数 / 前一天的分钟数（0 点起算）。
  IntColumn get reminderValue => integer().nullable()();

  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// 全局设置。只有一张表、几个 key，将来同步时也能整表搬走。
class AppSettings extends Table {
  TextColumn get key => text()();
  TextColumn get value => text().nullable()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {key};
}

@DriftDatabase(tables: [Terms, Courses, CourseSessions, Items, AppSettings])
class AppDatabase extends _$AppDatabase {
  /// 默认连本地文件；测试时可以注入内存数据库。
  AppDatabase([QueryExecutor? executor]) : super(executor ?? _openConnection());

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onUpgrade: (m, from, to) async {
          if (from < 2) {
            await m.createTable(appSettings);
            await m.addColumn(items, items.reminderMode);
            await m.addColumn(items, items.reminderValue);
            await m.addColumn(courses, courses.reminderMode);
            await m.addColumn(courses, courses.reminderValue);
          }
        },
      );

  static QueryExecutor _openConnection() {
    // drift_flutter 会按平台挑合适的应用数据目录（macOS/Android 各不相同），
    // 全部落在本地，天然离线可用。
    return driftDatabase(name: 'tabby');
  }

  // ---- 全局设置：默认提醒 ----

  static const defaultReminderModeKey = 'defaultReminderMode';
  static const defaultReminderValueKey = 'defaultReminderValue';

  Future<String?> _setting(String key) async {
    final row = await (select(appSettings)..where((t) => t.key.equals(key)))
        .getSingleOrNull();
    return row?.value;
  }

  Future<void> _writeSetting(String key, String? value) async {
    await into(appSettings).insert(
      AppSettingsCompanion.insert(
        key: key,
        value: Value(value),
        updatedAt: DateTime.now(),
      ),
      mode: InsertMode.insertOrReplace,
    );
  }

  /// 全局默认提醒。没设过就用「前一天 21:00」。
  Future<ReminderSpec> defaultReminder() async {
    final mode = int.tryParse(await _setting(defaultReminderModeKey) ?? '');
    if (mode == null) return ReminderSpec.defaultValue;
    final value = int.tryParse(await _setting(defaultReminderValueKey) ?? '');
    return ReminderSpec.fromDb(mode, value) ?? ReminderSpec.defaultValue;
  }

  Future<void> setDefaultReminder(ReminderSpec spec) async {
    await _writeSetting(defaultReminderModeKey, '${spec.mode.index}');
    await _writeSetting(defaultReminderValueKey, spec.value?.toString());
  }

  /// 全局默认提醒的流，设置页改了以后界面会跟着变。
  Stream<ReminderSpec> watchDefaultReminder() {
    return (select(appSettings)
          ..where((t) => t.key.isIn([
                defaultReminderModeKey,
                defaultReminderValueKey,
              ])))
        .watch()
        .map((rows) {
      final map = {for (final r in rows) r.key: r.value};
      final mode = int.tryParse(map[defaultReminderModeKey] ?? '');
      if (mode == null) return ReminderSpec.defaultValue;
      final value = int.tryParse(map[defaultReminderValueKey] ?? '');
      return ReminderSpec.fromDb(mode, value) ?? ReminderSpec.defaultValue;
    });
  }

  /// 把提醒规则批量写进已有记录（覆盖它们各自的设置）。
  /// spec 为 null 表示「清空单独设置，改回跟随默认」。
  Future<int> applyReminder({
    required bool toCourses,
    required bool toItems,
    ReminderSpec? spec,
  }) async {
    final now = DateTime.now();
    var count = 0;
    if (toCourses) {
      count += await (update(courses)..where((t) => t.deletedAt.isNull()))
          .write(
        CoursesCompanion(
          reminderMode: Value(spec?.mode.index),
          reminderValue: Value(spec?.value),
          updatedAt: Value(now),
        ),
      );
    }
    if (toItems) {
      count += await (update(items)..where((t) => t.deletedAt.isNull())).write(
        ItemsCompanion(
          reminderMode: Value(spec?.mode.index),
          reminderValue: Value(spec?.value),
          updatedAt: Value(now),
        ),
      );
    }
    return count;
  }

  /// 设置当前学期的起始日（第 1 周的周一）。导入课表时从页面里反推出来。
  Future<DateTime> setActiveTermStart(DateTime start) async {
    final day = DateTime(start.year, start.month, start.day);
    final now = DateTime.now();
    final term = await (select(terms)
          ..where((t) => t.isActive.equals(true))
          ..limit(1))
        .getSingleOrNull();

    if (term == null) {
      await into(terms).insert(
        TermsCompanion.insert(
          id: 'term-default',
          name: '默认学期',
          startDate: Value(day),
          weekCount: const Value(20),
          isActive: const Value(true),
          updatedAt: now,
        ),
      );
    } else {
      await (update(terms)..where((t) => t.id.equals(term.id))).write(
        TermsCompanion(startDate: Value(day), updatedAt: Value(now)),
      );
    }
    return day;
  }

  Future<void> seedDemoData() async {
    final termCount = await select(terms).get();
    if (termCount.isNotEmpty) {
      return;
    }
    final now = DateTime.now();
    await batch((batch) {
      batch.insert(terms, TermsCompanion.insert(
        id: 'term-default',
        name: '默认学期',
        weekCount: const Value(20),
        isActive: const Value(true),
        updatedAt: now,
      ));
      batch.insert(items, ItemsCompanion.insert(
        id: 'item-sample-1',
        title: '这是不限时间的备忘',
        updatedAt: now,
      ));
      batch.insert(items, ItemsCompanion.insert(
        id: 'item-sample-2',
        title: '这是精确到小时的备忘',
        dueDate: Value(DateTime(now.year, now.month, now.day)),
        dueMinute: const Value(14 * 60),
        updatedAt: now,
      ));
    });
  }

  /// 示例课表：5 门课 + 上课时段，用来验证周课表 / 月日历两个视图。
  /// id 固定，重复点不会插重复数据。
  Future<void> seedDemoCourses() async {
    final now = DateTime.now();
    final termStart = DateTime(now.year, now.month, now.day)
        .subtract(Duration(days: now.weekday - 1));

    final term = await (select(terms)
          ..where((t) => t.isActive.equals(true))
          ..limit(1))
        .getSingleOrNull();

    if (term == null) {
      await into(terms).insert(
        TermsCompanion.insert(
          id: 'term-default',
          name: '默认学期',
          startDate: Value(termStart),
          weekCount: const Value(20),
          isActive: const Value(true),
          updatedAt: now,
        ),
      );
    } else if (term.startDate == null) {
      await (update(terms)..where((t) => t.id.equals(term.id))).write(
        TermsCompanion(startDate: Value(termStart), updatedAt: Value(now)),
      );
    }

    const demos = <(String, String, String, String, int, int, int, int)>[
      ('demo-math', '高等数学', '教三-201', '张老师', 1, 8 * 60, 9 * 60 + 40,
          0xFF4C8BF5),
      ('demo-english', '大学英语', '教二-305', '李老师', 2, 10 * 60,
          11 * 60 + 40, 0xFFE8618C),
      ('demo-ds', '数据结构', '实验楼-A402', '王老师', 3, 14 * 60, 15 * 60 + 40,
          0xFF34A853),
      ('demo-linear', '线性代数', '教三-208', '赵老师', 4, 8 * 60, 9 * 60 + 40,
          0xFFF9AB00),
      ('demo-pe', '体育', '操场', '陈老师', 5, 16 * 60, 17 * 60 + 40,
          0xFF8E24AA),
    ];

    for (final d in demos) {
      await into(courses).insert(
        CoursesCompanion.insert(
          id: d.$1,
          termId: const Value('term-default'),
          name: d.$2,
          teacher: Value(d.$4),
          location: Value(d.$3),
          color: Value(d.$8),
          updatedAt: now,
        ),
        mode: InsertMode.insertOrIgnore,
      );
      await into(courseSessions).insert(
        CourseSessionsCompanion.insert(
          id: '${d.$1}-session',
          courseId: d.$1,
          weekday: d.$5,
          startMinute: d.$6,
          endMinute: d.$7,
          weeks: const Value('*'),
          updatedAt: now,
        ),
        mode: InsertMode.insertOrIgnore,
      );
    }
  }
}
