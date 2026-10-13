import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/app_database.dart';
import '../../data/item_repository.dart';
import '../../data/reminder.dart';
import '../../data/reminder_providers.dart';
import '../../services/alarm_service.dart';
import '../reminder/reminder_picker.dart';
import 'memo_editor.dart';

/// 一条备忘。今日页和备忘页共用同一份渲染与操作逻辑。
class ItemTile extends ConsumerWidget {
  const ItemTile({
    super.key,
    required this.item,
    this.showDate = false,
  });

  final Item item;

  /// 分组视图里日期已经在标题上了，条目的副标题就只显示时间。
  final bool showDate;

  String get _timing {
    final minute = item.dueMinute;
    if (minute != null) {
      return showDate ? formatMinute(minute) : '${_datePrefix()}${formatMinute(minute)}';
    }
    if (item.dueDate == null) return '不限时间';
    return showDate ? '全天' : '${_datePrefix()}全天';
  }

  String get _reminderLabel {
    final spec = ReminderSpec.fromDb(item.reminderMode, item.reminderValue);
    if (spec == null) return '';
    return spec.isNone ? '' : ' · 提醒：${spec.label}';
  }

  String _datePrefix() {
    final d = item.dueDate!;
    return '${d.month}/${d.day} ';
  }

  Future<void> _pickReminder(BuildContext context, WidgetRef ref) async {
    final fallback = ref.read(defaultReminderProvider).value ??
        ReminderSpec.defaultValue;
    final picked = await showReminderPicker(
      context,
      current: ReminderSpec.fromDb(item.reminderMode, item.reminderValue),
      fallback: fallback,
    );
    await ref.read(itemRepositoryProvider).setReminder(item.id, picked);
  }

  /// 把这条备忘交给手机自带的「时钟」去响。
  /// 系统不允许第三方静默建闹钟，所以只能打开系统的设置闹钟界面让人确认一次。
  Future<void> _openSystemAlarm(BuildContext context, WidgetRef ref) async {
    final due = item.dueDate;
    if (due == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('这条没写日期，先给它定个日期')),
      );
      return;
    }
    final fallback = ref.read(defaultReminderProvider).value ??
        ReminderSpec.defaultValue;
    final spec = ReminderSpec.fromDb(item.reminderMode, item.reminderValue) ??
        fallback;
    final start = DateTime(
      due.year,
      due.month,
      due.day,
    ).add(Duration(minutes: item.dueMinute ?? 0));
    final at = spec.resolve(start) ?? start;

    final ok = await AlarmService.instance.openSystemAlarm(
      hour: at.hour,
      minute: at.minute,
      message: item.title,
    );
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(ok
            ? '已打开系统闹钟界面，确认后由系统时钟在 ${at.hour}:'
                '${at.minute.toString().padLeft(2, '0')} 响铃'
            : '打不开系统闹钟界面'),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: ListTile(
        dense: true,
        leading: Checkbox(
          value: item.done,
          onChanged: (value) {
            ref.read(itemRepositoryProvider).setDone(item.id, value ?? false);
          },
        ),
        title: Text(
          item.title,
          style: item.done
              ? TextStyle(
                  decoration: TextDecoration.lineThrough,
                  color: theme.colorScheme.onSurfaceVariant,
                )
              : null,
        ),
        subtitle: Text('$_timing$_reminderLabel'),
        trailing: PopupMenuButton<String>(
          icon: const Icon(Icons.more_horiz),
          onSelected: (value) async {
            if (value == 'edit') {
              await showMemoEditor(context, item: item);
            } else if (value == 'reminder') {
              await _pickReminder(context, ref);
            } else if (value == 'systemAlarm') {
              await _openSystemAlarm(context, ref);
            } else if (value == 'delete') {
              await _confirmDelete(context, ref);
            }
          },
          itemBuilder: (context) => [
            const PopupMenuItem(value: 'edit', child: Text('编辑')),
            const PopupMenuItem(value: 'reminder', child: Text('设置提醒')),
            const PopupMenuItem(
              value: 'systemAlarm',
              child: Text('用系统闹钟提醒'),
            ),
            const PopupMenuItem(value: 'delete', child: Text('删除')),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除备忘'),
        content: Text('确定删除「${item.title}」？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    await ref.read(itemRepositoryProvider).softDelete(item.id);

    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: const Text('已删除'),
          action: SnackBarAction(
            label: '撤销',
            onPressed: () {
              ref.read(itemRepositoryProvider).restore(item.id);
            },
          ),
        ),
      );
  }
}
