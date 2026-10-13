import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tabby/app/router.dart';
import 'package:tabby/data/app_database.dart';
import 'package:tabby/data/occurrence.dart';
import 'package:tabby/features/calendar/month_grid.dart';
import 'package:tabby/features/timetable/course_import_page.dart';
import 'package:tabby/features/timetable/week_grid.dart';

void main() {
  setUpAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });

  final now = DateTime.now();
  final monday = DateTime(2026, 10, 12); // 周一

  final sessions = [
    SessionWithCourse(
      session: CourseSession(
        id: 's1',
        courseId: 'c1',
        weekday: 1,
        startMinute: 8 * 60,
        endMinute: 9 * 60 + 40,
        weeks: '*',
        updatedAt: now,
      ),
      course: Course(id: 'c1', name: '高等数学', updatedAt: now),
    ),
  ];

  final items = [
    Item(
      id: 'i1',
      title: '记得交作业',
      dueDate: monday,
      dueMinute: 14 * 60,
      done: false,
      updatedAt: now,
    ),
    Item(
      id: 'i2',
      title: '取快递',
      dueDate: monday,
      done: false,
      updatedAt: now,
    ),
  ];

  final set = buildOccurrences(
    from: monday,
    to: monday.add(const Duration(days: 6)),
    sessions: sessions,
    items: items,
    termStart: monday,
  );

  testWidgets('周课表：课程和备忘都画进网格', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 900,
            height: 1400,
            child: SingleChildScrollView(
              child: WeekTimetable(weekStart: monday, occurrences: set),
            ),
          ),
        ),
      ),
    );

    // 课程块
    expect(find.text('高等数学'), findsOneWidget);
    // 精确到小时的备忘落在时间轴里
    expect(find.text('记得交作业'), findsOneWidget);
    // 14:00 既出现在左侧时间刻度，也出现在备忘块里
    expect(find.text('14:00'), findsWidgets);
    // 精确到天的备忘进全天条带
    expect(find.text('取快递'), findsOneWidget);
  });

  testWidgets('月日历：每天缩略条 + 点开看当天清单', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 900,
            height: 1000,
            child: MonthCalendar(
              month: DateTime(2026, 10, 1),
              occurrences: set,
            ),
          ),
        ),
      ),
    );

    // 10/12 那天有课也有备忘（缩略条是「时间 + 标题」连写的）
    expect(find.textContaining('高等数学'), findsWidgets);
    expect(find.textContaining('记得交作业'), findsWidgets);

    // 点 12 号弹出当天清单
    await tester.tap(find.text('12'));
    await tester.pumpAndSettle();

    expect(find.text('这一天没有安排'), findsNothing);
    // 清单里同时列出课程和备忘
    expect(find.text('课程'), findsWidgets);
    expect(find.text('备忘'), findsWidgets);
  });

  testWidgets('导入页：填文本示例 → 解析出预览清单', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider
              .overrideWithValue(AppDatabase(NativeDatabase.memory())),
        ],
        child: const MaterialApp(home: CourseImportPage()),
      ),
    );

    await tester.tap(find.text('填文本示例'));
    await tester.pumpAndSettle();

    // 预览里出现解析出来的课
    expect(find.text('高等数学'), findsOneWidget);
    expect(find.textContaining('教三-201'), findsWidgets);
    // AppBar 上出现「导入 5 条」
    expect(find.text('导入 5 条'), findsOneWidget);
  });

  testWidgets('导入页：填网页示例 → 认出 HTML 课表与学期起始日', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider
              .overrideWithValue(AppDatabase(NativeDatabase.memory())),
        ],
        child: const MaterialApp(home: CourseImportPage()),
      ),
    );

    await tester.tap(find.text('填网页示例'));
    await tester.pumpAndSettle();

    // 6 门课，且弹出「写入学期起始日」开关
    expect(find.text('导入 6 条'), findsOneWidget);
    expect(find.text('同时写入学期起始日'), findsOneWidget);
    expect(find.textContaining('2026-09-07'), findsOneWidget);
  });
}
