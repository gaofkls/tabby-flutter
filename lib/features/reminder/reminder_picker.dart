import 'package:flutter/material.dart';

import '../../data/reminder.dart';

/// 选择一条记录的提醒规则。返回 null 表示「跟随默认」。
Future<ReminderSpec?> showReminderPicker(
  BuildContext context, {
  required ReminderSpec? current,
  required ReminderSpec fallback,
}) {
  return showModalBottomSheet<ReminderSpec>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => _ReminderPickerSheet(
      current: current,
      fallback: fallback,
    ),
  );
}

class _ReminderPickerSheet extends StatefulWidget {
  const _ReminderPickerSheet({required this.current, required this.fallback});

  final ReminderSpec? current;
  final ReminderSpec fallback;

  @override
  State<_ReminderPickerSheet> createState() => _ReminderPickerSheetState();
}

class _ReminderPickerSheetState extends State<_ReminderPickerSheet> {
  /// null = 跟随默认
  ReminderSpec? _value;
  int _beforeMinutes = 30;
  int _previousDayMinute = 21 * 60;

  @override
  void initState() {
    super.initState();
    final current = widget.current;
    _value = current;
    if (current == null) {
      _beforeMinutes = 30;
      _previousDayMinute = 21 * 60;
    } else {
      switch (current.mode) {
        case ReminderMode.none:
          break;
        case ReminderMode.before:
          _beforeMinutes = current.value ?? 30;
        case ReminderMode.previousDay:
          _previousDayMinute = current.value ?? 21 * 60;
      }
    }
  }

  bool get _isBefore =>
      _value != null && _value!.mode == ReminderMode.before;

  bool get _isPreviousDay =>
      _value != null && _value!.mode == ReminderMode.previousDay;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('提醒', style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              '到点前会发系统通知，离线也能用。',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            RadioGroup<ReminderSpec?>(
              groupValue: _value,
              onChanged: (v) => setState(() => _value = v),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  RadioListTile<ReminderSpec?>(
                    value: null,
                    title: const Text('跟随默认'),
                    subtitle: Text(widget.fallback.label),
                  ),
                  RadioListTile<ReminderSpec?>(
                    value: const ReminderSpec.none(),
                    title: const Text('不提醒'),
                  ),
                  RadioListTile<ReminderSpec?>(
                    value: ReminderSpec.before(_beforeMinutes),
                    title: const Text('提前'),
                    subtitle: Text(_beforeLabel(_beforeMinutes)),
                  ),
                  if (_isBefore)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                      child: Wrap(
                        spacing: 8,
                        children: [
                          ...ReminderSpec.beforePresets.map(
                            (m) => ChoiceChip(
                              label: Text(_beforeShort(m)),
                              selected: _beforeMinutes == m,
                              onSelected: (_) => setState(() {
                                _beforeMinutes = m;
                                _value = ReminderSpec.before(m);
                              }),
                            ),
                          ),
                          ActionChip(
                            avatar: const Icon(Icons.more_time, size: 16),
                            label: const Text('自定义'),
                            onPressed: _pickBeforeMinutes,
                          ),
                        ],
                      ),
                    ),
                  RadioListTile<ReminderSpec?>(
                    value: ReminderSpec.previousDay(_previousDayMinute),
                    title: const Text('前一天晚上'),
                    subtitle: Text(formatReminderMinute(_previousDayMinute)),
                  ),
                  if (_isPreviousDay)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: OutlinedButton.icon(
                          onPressed: _pickPreviousDayMinute,
                          icon: const Icon(Icons.access_time, size: 18),
                          label: Text(
                            '选时间 · ${formatReminderMinute(_previousDayMinute)}',
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(_value),
              child: const Text('确定'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickBeforeMinutes() async {
    final picked = await _pickMinutesDialog(
      context,
      title: '提前多久',
      minutes: _beforeMinutes,
    );
    if (picked == null) return;
    setState(() {
      _beforeMinutes = picked;
      _value = ReminderSpec.before(picked);
    });
  }

  Future<void> _pickPreviousDayMinute() async {
    final picked = await _pickMinutesDialog(
      context,
      title: '前一天几点',
      minutes: _previousDayMinute,
    );
    if (picked == null) return;
    setState(() {
      _previousDayMinute = picked;
      _value = ReminderSpec.previousDay(picked);
    });
  }

  Future<int?> _pickMinutesDialog(
    BuildContext context, {
    required String title,
    required int minutes,
  }) async {
    final controller = TextEditingController(text: '$minutes');
    return showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: '分钟数（0 点起算）',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              final value = int.tryParse(controller.text.trim());
              if (value == null) return;
              Navigator.of(context).pop(value.clamp(0, 24 * 60 - 1));
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }
}

String _beforeLabel(int minutes) {
  if (minutes >= 1440 && minutes % 1440 == 0) {
    return '开始前 ${minutes ~/ 1440} 天';
  }
  if (minutes >= 60 && minutes % 60 == 0) {
    return '开始前 ${minutes ~/ 60} 小时';
  }
  return '开始前 $minutes 分钟';
}

String _beforeShort(int minutes) {
  if (minutes >= 1440 && minutes % 1440 == 0) return '${minutes ~/ 1440} 天';
  if (minutes >= 60 && minutes % 60 == 0) return '${minutes ~/ 60} 小时';
  return '$minutes 分钟';
}

/// 编辑器 / 列表里的一行提醒设置。
class ReminderPickerTile extends StatelessWidget {
  const ReminderPickerTile({
    super.key,
    required this.spec,
    required this.fallback,
    required this.onChanged,
    this.enabled = true,
  });

  final ReminderSpec? spec;
  final ReminderSpec fallback;
  final ValueChanged<ReminderSpec?> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final text = spec == null ? '跟随默认（${fallback.label}）' : spec!.label;

    return ListTile(
      enabled: enabled,
      leading: const Icon(Icons.notifications_outlined),
      title: const Text('提醒'),
      subtitle: Text(text),
      trailing: const Icon(Icons.chevron_right),
      onTap: enabled
          ? () async {
              final picked = await showReminderPicker(
                context,
                current: spec,
                fallback: fallback,
              );
              onChanged(picked);
            }
          : null,
    );
  }
}

/// 某个事件的提醒时刻说明，例如「10 月 12 日 21:00 提醒」。
String describeReminderTime(ReminderSpec spec, DateTime start) {
  final at = spec.resolve(start);
  if (at == null) return '不提醒';
  return '${at.month} 月 ${at.day} 日 '
      '${_hm(at.hour * 60 + at.minute)} 提醒';
}

String _hm(int minute) {
  final m = minute % (24 * 60);
  return '${(m ~/ 60).toString().padLeft(2, '0')}:'
      '${(m % 60).toString().padLeft(2, '0')}';
}
