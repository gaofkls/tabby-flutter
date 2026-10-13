import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/router.dart';
import '../../data/reminder.dart';
import '../../data/reminder_providers.dart';
import 'reminder_picker.dart';

/// 批量给课程 / 备忘设同一条提醒。课表页和设置页共用。
Future<void> showBatchReminderSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => const _BatchReminderSheet(),
  );
}

class _BatchReminderSheet extends ConsumerStatefulWidget {
  const _BatchReminderSheet();

  @override
  ConsumerState<_BatchReminderSheet> createState() =>
      _BatchReminderSheetState();
}

class _BatchReminderSheetState extends ConsumerState<_BatchReminderSheet> {
  bool _courses = true;
  bool _items = true;
  bool _useCustom = false;
  ReminderSpec? _custom;
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final defaultSpec = ref.watch(defaultReminderProvider).value ??
        ReminderSpec.defaultValue;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('批量设置提醒', style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              '一次给很多条记录设同一条提醒。之后每条还能单独改。',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            RadioGroup<bool>(
              groupValue: _useCustom,
              onChanged: (v) => setState(() => _useCustom = v ?? false),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  RadioListTile<bool>(
                    value: false,
                    title: const Text('用默认提醒'),
                    subtitle: Text(defaultSpec.label),
                  ),
                  RadioListTile<bool>(
                    value: true,
                    title: const Text('自定义'),
                    subtitle: Text(_custom?.label ?? '点这里选一种'),
                  ),
                ],
              ),
            ),
            if (_useCustom)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () async {
                    final picked = await showReminderPicker(
                      context,
                      current: _custom,
                      fallback: defaultSpec,
                    );
                    if (picked == null) return;
                    setState(() => _custom = picked);
                  },
                  icon: const Icon(Icons.tune, size: 18),
                  label: const Text('选择提醒方式'),
                ),
              ),
            const SizedBox(height: 12),
            Text('应用到', style: theme.textTheme.labelLarge),
            CheckboxListTile(
              value: _courses,
              onChanged: (v) => setState(() => _courses = v ?? false),
              title: const Text('全部课程'),
              dense: true,
            ),
            CheckboxListTile(
              value: _items,
              onChanged: (v) => setState(() => _items = v ?? false),
              title: const Text('全部备忘'),
              dense: true,
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: _busy || (!_courses && !_items) ? null : _apply,
              icon: _busy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.check, size: 18),
              label: Text(_busy ? '正在写入…' : '开始设置'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _apply() async {
    final db = ref.read(databaseProvider);
    final spec = _useCustom
        ? (_custom ?? const ReminderSpec.none())
        : await db.defaultReminder();

    setState(() => _busy = true);
    final count = await db.applyReminder(
      toCourses: _courses,
      toItems: _items,
      spec: spec,
    );
    await ref.read(reminderSchedulerProvider).reschedule();
    if (!mounted) return;
    setState(() => _busy = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已给 $count 条记录设置「${spec.label}」')),
    );
    Navigator.of(context).pop();
  }
}
