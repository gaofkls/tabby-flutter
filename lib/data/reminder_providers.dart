import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/router.dart';
import 'reminder.dart';
import 'reminder_scheduler.dart';

/// 全局默认提醒（设置页可改）。新建课程/备忘默认跟随它。
final defaultReminderProvider = StreamProvider<ReminderSpec>((ref) {
  return ref.watch(databaseProvider).watchDefaultReminder();
});

/// 全局默认提醒的同步读法（编辑器里要用当前值，但不想包一层 when）。
final defaultReminderNowProvider = FutureProvider<ReminderSpec>((ref) {
  return ref.watch(databaseProvider).defaultReminder();
});

/// 提醒调度器：数据一变就重排系统闹钟。
final reminderSchedulerProvider = Provider<ReminderScheduler>((ref) {
  return ReminderScheduler(ref.watch(databaseProvider));
});
