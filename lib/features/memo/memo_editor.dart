import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/router.dart';
import '../../data/app_database.dart';
import '../../data/conflict_queries.dart';
import '../../data/conflicts.dart';
import '../../data/item_repository.dart';
import '../../data/reminder.dart';
import '../../data/reminder_providers.dart';
import '../reminder/conflict_dialog.dart';
import '../reminder/reminder_picker.dart';

/// 备忘的三种时间粒度，对应数据库里 dueDate / dueMinute 两个可空字段：
///   anytime -> 两个都 null
///   day     -> dueDate 有值，dueMinute 为 null
///   hour    -> 两个都有值
enum MemoGranularity { anytime, day, hour }

/// 弹出新建 / 编辑备忘的底部面板。返回 true 表示数据有变动。
Future<bool?> showMemoEditor(BuildContext context, {Item? item}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) {
      return Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: _MemoEditorSheet(item: item),
      );
    },
  );
}

class _MemoEditorSheet extends ConsumerStatefulWidget {
  const _MemoEditorSheet({this.item});

  final Item? item;

  @override
  ConsumerState<_MemoEditorSheet> createState() => _MemoEditorSheetState();
}

class _MemoEditorSheetState extends ConsumerState<_MemoEditorSheet> {
  late final TextEditingController _titleController;
  late final TextEditingController _noteController;
  late MemoGranularity _granularity;
  late DateTime _date;
  late TimeOfDay _time;
  ReminderSpec? _reminder;

  bool get _isEditing => widget.item != null;

  @override
  void initState() {
    super.initState();
    final item = widget.item;
    final now = DateTime.now();

    _titleController = TextEditingController(text: item?.title ?? '');
    _noteController = TextEditingController(text: item?.note ?? '');
    _granularity = item == null ? MemoGranularity.anytime : _granularityOf(item);
    _date = item?.dueDate ?? DateTime(now.year, now.month, now.day);
    _reminder = item == null
        ? null
        : ReminderSpec.fromDb(item.reminderMode, item.reminderValue);

    final minute = item?.dueMinute;
    _time = minute == null
        ? TimeOfDay(hour: now.hour, minute: now.minute)
        : TimeOfDay(hour: minute ~/ 60, minute: minute % 60);

    _titleController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _titleController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  static MemoGranularity _granularityOf(Item item) {
    if (item.dueDate == null) return MemoGranularity.anytime;
    if (item.dueMinute == null) return MemoGranularity.day;
    return MemoGranularity.hour;
  }

  /// 下面那行小字：这条备忘到底几点会响。
  String _reminderHint() {
    final spec = _reminder ??
        (ref.read(defaultReminderProvider).value ?? ReminderSpec.defaultValue);
    if (spec.isNone) return '不会发通知';
    final start = _granularity == MemoGranularity.hour
        ? DateTime(
            _date.year,
            _date.month,
            _date.day,
            _time.hour,
            _time.minute,
          )
        : DateTime(_date.year, _date.month, _date.day);
    final at = spec.resolve(start);
    if (at == null) return '不会发通知';
    return '${at.month} 月 ${at.day} 日 ${at.hour.toString().padLeft(2, '0')}:'
        '${at.minute.toString().padLeft(2, '0')} 会响';
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(context: context, initialTime: _time);
    if (picked != null) setState(() => _time = picked);
  }

  Future<void> _save() async {
    final title = _titleController.text.trim();
    if (title.isEmpty) return;

    final note = _noteController.text.trim();
    final noteValue = note.isEmpty ? null : note;

    final dueDate = switch (_granularity) {
      MemoGranularity.anytime => null,
      MemoGranularity.day => DateTime(_date.year, _date.month, _date.day),
      MemoGranularity.hour => DateTime(_date.year, _date.month, _date.day),
    };
    final dueMinute = switch (_granularity) {
      MemoGranularity.hour => _time.hour * 60 + _time.minute,
      _ => null,
    };

    final candidate = Item(
      id: widget.item?.id ?? 'candidate',
      title: title,
      note: noteValue,
      dueDate: dueDate,
      dueMinute: dueMinute,
      done: false,
      updatedAt: DateTime.now(),
    );

    // 精确到小时的备忘会占时间轴，跟课程 / 别的备忘撞了就问一句
    if (dueMinute != null) {
      final db = ref.read(databaseProvider);
      final conflicts = findItemConflicts(
        candidate: candidate,
        existingSessions: await loadLiveSessions(db),
        existingItems: await loadLiveItems(db),
        termStart: await loadActiveTermStart(db),
      );
      if (conflicts.isNotEmpty && mounted) {
        final proceed = await confirmTimeConflicts(context, conflicts);
        if (!proceed) return;
      }
    }

    final repo = ref.read(itemRepositoryProvider);
    if (_isEditing) {
      await repo.update(
        widget.item!.id,
        title: title,
        note: noteValue,
        dueDate: dueDate,
        dueMinute: dueMinute,
        reminder: _reminder,
      );
    } else {
      await repo.create(
        title: title,
        note: noteValue,
        dueDate: dueDate,
        dueMinute: dueMinute,
        reminder: _reminder,
      );
    }

    if (mounted) Navigator.of(context).pop(true);
  }

  Future<void> _delete() async {
    final item = widget.item;
    if (item == null) return;
    await ref.read(itemRepositoryProvider).softDelete(item.id);
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _titleController,
              autofocus: !_isEditing,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: '备忘内容',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _noteController,
              minLines: 1,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: '备注（可选）',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            Text('时间精度', style: theme.textTheme.labelLarge),
            const SizedBox(height: 8),
            SegmentedButton<MemoGranularity>(
              segments: const [
                ButtonSegment(
                  value: MemoGranularity.anytime,
                  label: Text('不限时间'),
                  icon: Icon(Icons.all_inclusive),
                ),
                ButtonSegment(
                  value: MemoGranularity.day,
                  label: Text('精确到天'),
                  icon: Icon(Icons.calendar_today),
                ),
                ButtonSegment(
                  value: MemoGranularity.hour,
                  label: Text('精确到小时'),
                  icon: Icon(Icons.schedule),
                ),
              ],
              selected: {_granularity},
              onSelectionChanged: (selection) {
                setState(() => _granularity = selection.first);
              },
            ),
            if (_granularity != MemoGranularity.anytime) ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _pickDate,
                icon: const Icon(Icons.event),
                label: Text('${_date.month} 月 ${_date.day} 日（${_weekdayLabel(_date)}）'),
              ),
            ],
            if (_granularity == MemoGranularity.hour) ...[
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _pickTime,
                icon: const Icon(Icons.access_time),
                label: Text(_time.format(context)),
              ),
            ],
            const SizedBox(height: 8),
            Card(
              margin: EdgeInsets.zero,
              child: ReminderPickerTile(
                spec: _reminder,
                fallback: ref.watch(defaultReminderProvider).value ??
                    ReminderSpec.defaultValue,
                enabled: _granularity != MemoGranularity.anytime,
                onChanged: (spec) => setState(() => _reminder = spec),
              ),
            ),
            if (_granularity != MemoGranularity.anytime)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                child: Text(
                  _reminderHint(),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            if (_granularity == MemoGranularity.anytime)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                child: Text(
                  '不限时间的备忘没有日期，设不了提醒',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _titleController.text.trim().isEmpty ? null : _save,
              child: Text(_isEditing ? '保存修改' : '添加备忘'),
            ),
            if (_isEditing) ...[
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: _delete,
                icon: const Icon(Icons.delete_outline),
                label: const Text('删除'),
                style: TextButton.styleFrom(
                  foregroundColor: theme.colorScheme.error,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

const _weekdayLabels = ['一', '二', '三', '四', '五', '六', '日'];

/// DateTime.weekday 是 1=周一 … 7=周日
String _weekdayLabel(DateTime date) => '周${_weekdayLabels[date.weekday - 1]}';

/// 把「当天 0 点起的分钟数」格式化成 HH:mm
String formatMinute(int minute) {
  final h = minute ~/ 60;
  final m = minute % 60;
  return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
}

/// 日期标题，例如「10 月 13 日 周一」「10 月 12 日 今天」
String formatDateLabel(DateTime date) {
  return '${date.month} 月 ${date.day} 日 ${_weekdayLabel(date)}';
}
