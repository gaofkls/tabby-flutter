import 'package:drift/drift.dart' as drift;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tabby/data/app_database.dart';
import 'package:tabby/data/course_repository.dart';
import 'package:tabby/data/html_schedule_parser.dart';
import 'package:tabby/data/occurrence.dart';
import 'package:tabby/data/sample_schedule_html.dart';
import 'package:tabby/data/session_input.dart';

void main() {
  late AppDatabase db;
  late CourseRepository repo;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repo = CourseRepository(db);
  });

  tearDown(() async {
    await db.close();
  });

  Future<int> liveSessions(String courseId) async {
    final rows = await (db.select(db.courseSessions)
          ..where((t) => t.courseId.equals(courseId))
          ..where((t) => t.deletedAt.isNull()))
        .get();
    return rows.length;
  }

  test('创建课程带多个时段', () async {
    final id = await repo.create(
      name: '高等数学',
      teacher: '张老师',
      location: '教三-201',
      color: 0xFF4C8BF5,
      sessions: [
        const SessionInput(weekday: 1, startMinute: 480, endMinute: 580),
        const SessionInput(weekday: 3, startMinute: 840, endMinute: 940),
      ],
    );

    final course = await (db.select(db.courses)
          ..where((t) => t.id.equals(id)))
        .getSingle();
    expect(course.name, '高等数学');
    expect(course.location, '教三-201');
    expect(await liveSessions(id), 2);
  });

  test('改课程会换掉时段（旧的打墓碑）', () async {
    final id = await repo.create(
      name: '大学英语',
      sessions: [
        const SessionInput(weekday: 2, startMinute: 600, endMinute: 700),
      ],
    );
    expect(await liveSessions(id), 1);

    await repo.update(
      id,
      name: '大学英语（二）',
      location: '教二-305',
      sessions: [
        const SessionInput(weekday: 4, startMinute: 480, endMinute: 580),
      ],
    );

    final course = await (db.select(db.courses)
          ..where((t) => t.id.equals(id)))
        .getSingle();
    expect(course.name, '大学英语（二）');
    expect(await liveSessions(id), 1);

    final live = await (db.select(db.courseSessions)
          ..where((t) => t.courseId.equals(id))
          ..where((t) => t.deletedAt.isNull()))
        .getSingle();
    expect(live.weekday, 4);
  });

  test('删除课程是软删除，restore 能恢复', () async {
    final id = await repo.create(
      name: '体育',
      sessions: [
        const SessionInput(weekday: 5, startMinute: 960, endMinute: 1060),
      ],
    );

    await repo.softDelete(id);
    var course = await (db.select(db.courses)..where((t) => t.id.equals(id)))
        .getSingle();
    expect(course.deletedAt, isNotNull);
    expect(await liveSessions(id), 0);

    await repo.restore(id);
    course = await (db.select(db.courses)..where((t) => t.id.equals(id)))
        .getSingle();
    expect(course.deletedAt, isNull);
    expect(await liveSessions(id), 1);
  });

  test('导入：同名合并成一门课，多条时段挂上去', () async {
    final count = await repo.importEntries([
      const ImportEntry(
        name: '数据结构',
        weekday: 1,
        startMinute: 480,
        endMinute: 580,
        location: '实验楼-A402',
      ),
      const ImportEntry(
        name: '数据结构',
        weekday: 3,
        startMinute: 840,
        endMinute: 940,
        location: '实验楼-A402',
      ),
      const ImportEntry(
        name: '线性代数',
        weekday: 2,
        startMinute: 600,
        endMinute: 700,
      ),
    ]);

    expect(count, 2); // 两门课

    final courses = await db.select(db.courses).get();
    expect(courses.length, 2);

    final ds = courses.firstWhere((c) => c.name == '数据结构');
    expect(await liveSessions(ds.id), 2);

    final linear = courses.firstWhere((c) => c.name == '线性代数');
    expect(await liveSessions(linear.id), 1);
  });

  test('导入：完全重复的时段会去重', () async {
    await repo.importEntries([
      const ImportEntry(
        name: '概率论',
        weekday: 1,
        startMinute: 480,
        endMinute: 580,
      ),
      const ImportEntry(
        name: '概率论',
        weekday: 1,
        startMinute: 480,
        endMinute: 580,
      ),
    ]);

    final courses = await db.select(db.courses).get();
    expect(courses.length, 1);
    expect(await liveSessions(courses.single.id), 1);
  });

  test('端到端：解析真实网页课表 → 入库 → 学期起始日', () async {
    final parsed = HtmlScheduleParser.parse(sampleScheduleHtml);
    final count = await repo.importEntries(parsed.entries);
    expect(count, 6);

    await db.setActiveTermStart(parsed.termStart!);
    final term = await (db.select(db.terms)
          ..where((t) => t.isActive.equals(true)))
        .getSingle();
    expect(term.startDate, DateTime(2026, 9, 7));

    // 现代图像处理：周三 08:00–11:25，第 1-3、5-9 周
    final course = (await db.select(db.courses).get())
        .firstWhere((c) => c.name.contains('现代图像处理'));
    expect(course.teacher, '邢素霞');
    expect(course.location, '工2-302-1');

    final sessions = await (db.select(db.courseSessions)
          ..where((t) => t.courseId.equals(course.id)))
        .get();
    expect(sessions.length, 1);
    expect(sessions.single.weekday, 3);
    expect(sessions.single.startMinute, 8 * 60);
    expect(sessions.single.endMinute, 11 * 60 + 25);
    expect(sessions.single.weeks, '1-3,5-9');

    // 展开第 6 周（2026-10-12 起）：6 门课都在周次范围内
    final joined = db.select(db.courseSessions).join([
      drift.innerJoin(
        db.courses,
        db.courses.id.equalsExp(db.courseSessions.courseId),
      ),
    ]);
    final allSessions = (await joined.get())
        .map(
          (r) => SessionWithCourse(
            session: r.readTable(db.courseSessions),
            course: r.readTable(db.courses),
          ),
        )
        .toList();

    final week6 = buildOccurrences(
      from: DateTime(2026, 10, 12),
      to: DateTime(2026, 10, 18),
      sessions: allSessions,
      items: const [],
      termStart: DateTime(2026, 9, 7),
    );
    expect(week6.timed.length, 6);

    // 第 4 周：现代图像处理是「1-3,5-9 周」，第 4 周不上
    final week4 = buildOccurrences(
      from: DateTime(2026, 9, 28),
      to: DateTime(2026, 10, 4),
      sessions: allSessions,
      items: const [],
      termStart: DateTime(2026, 9, 7),
    );
    expect(week4.timed.length, 5);
    expect(
      week4.timed.any((o) => o.title.contains('现代图像处理')),
      isFalse,
    );
  });
}
