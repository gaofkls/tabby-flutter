import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tabby/app/router.dart';
import 'package:tabby/data/app_database.dart';
import 'package:tabby/data/occurrence.dart';
import 'package:tabby/data/reminder.dart';
import 'package:tabby/data/reminder_providers.dart';
import 'package:tabby/features/timetable/course_editor.dart';

Future<void> _openEditor(WidgetTester tester, Term? term) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(AppDatabase(NativeDatabase.memory())),
        // 直接给确定的学期 / 默认提醒，不走真实数据库流
        // （drift 的流在 ProviderContainer 销毁时会留 Timer，测试会挂）
        activeTermProvider.overrideWith((ref) => Stream.value(term)),
        defaultReminderProvider.overrideWith(
          (ref) => Stream.value(ReminderSpec.defaultValue),
        ),
      ],
      child: MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showCourseEditor(context),
              child: const Text('打开'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('打开'));
  // 底部面板是异步打开的，用定长 pump 推进动画（pumpAndSettle 会一直等）
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Term _term({DateTime? startDate}) => Term(
      id: 'term-test',
      name: '测试学期',
      startDate: startDate,
      weekCount: 20,
      isActive: true,
      updatedAt: DateTime(2026, 9, 7),
    );

void main() {
  setUpAll(() {
    // 每个用例都建一个内存库，drift 会警告「创建了多个 database」，这里不需要
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });

  testWidgets('有学期起始日时，周次能换算成日期', (tester) async {
    await _openEditor(tester, _term(startDate: DateTime(2026, 9, 7)));

    expect(find.textContaining('第 1 周从 2026-09-07 开始'), findsOneWidget);
    // 默认每周
    expect(find.textContaining('本课程的周次：每周'), findsOneWidget);
    expect(find.text('按日期选'), findsOneWidget);

    // 周次填「1-3」，下面立刻显示对应的日期区间
    // （第 4 个输入框：课程名 / 教师 / 教室 / 周次）
    await tester.enterText(find.byType(TextField).at(3), '1-3');
    await tester.pump();
    expect(find.textContaining('第1-3周（9/7–9/27）'), findsOneWidget);
  });

  testWidgets('没有学期起始日时，提示先设置', (tester) async {
    await _openEditor(tester, _term());

    expect(find.text('还没设置学期起始日'), findsOneWidget);
    expect(find.text('设置起始日'), findsOneWidget);
    expect(find.text('按日期选'), findsNothing);
  });
}
