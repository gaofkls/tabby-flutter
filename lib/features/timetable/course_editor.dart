import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/router.dart';
import '../../data/conflict_queries.dart';
import '../../data/conflicts.dart';
import '../../data/course_repository.dart';
import '../../data/occurrence.dart';
import '../../data/reminder.dart';
import '../../data/reminder_providers.dart';
import '../../data/session_input.dart';
import '../../data/week_helpers.dart';
import '../memo/memo_editor.dart';
import '../reminder/conflict_dialog.dart';
import '../reminder/reminder_picker.dart';

const courseColors = [
  0xFF4C8BF5,
  0xFFE8618C,
  0xFF34A853,
  0xFFF9AB00,
  0xFF8E24AA,
  0xFF00ACC1,
  0xFFFB8C00,
  0xFF5E6C84,
];

const _weekdayLabels = ['一', '二', '三', '四', '五', '六', '日'];

/// 新建 / 编辑课程。一门课可以挂多个上课时段。
Future<bool?> showCourseEditor(BuildContext context, {String? courseId}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) {
      return Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: _CourseEditorSheet(courseId: courseId),
      );
    },
  );
}

class _CourseEditorSheet extends ConsumerStatefulWidget {
  const _CourseEditorSheet({this.courseId});

  final String? courseId;

  @override
  ConsumerState<_CourseEditorSheet> createState() => _CourseEditorSheetState();
}

class _CourseEditorSheetState extends ConsumerState<_CourseEditorSheet> {
  late final TextEditingController _name;
  late final TextEditingController _teacher;
  late final TextEditingController _location;
  late final TextEditingController _weeks;

  int _color = courseColors.first;
  List<SessionInput> _sessions = [];
  ReminderSpec? _reminder;
  bool _loaded = false;

  bool get _isEditing => widget.courseId != null;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController();
    _teacher = TextEditingController();
    _location = TextEditingController();
    _weeks = TextEditingController(text: '*');
    _name.addListener(() => setState(() {}));
    if (widget.courseId != null) {
      _load();
    } else {
      _sessions = [
        const SessionInput(
          weekday: 1,
          startMinute: 8 * 60,
          endMinute: 9 * 60 + 40,
        ),
      ];
      _loaded = true;
    }
  }

  Future<void> _load() async {
    final db = ref.read(databaseProvider);
    final course = await (db.select(db.courses)
          ..where((t) => t.id.equals(widget.courseId!)))
        .getSingleOrNull();
    final sessions = await (db.select(db.courseSessions)
          ..where((t) => t.courseId.equals(widget.courseId!))
          ..where((t) => t.deletedAt.isNull()))
        .get();

    if (!mounted || course == null) return;
    setState(() {
      _name.text = course.name;
      _teacher.text = course.teacher ?? '';
      _location.text = course.location ?? '';
      _color = course.color ?? courseColors.first;
      _reminder = ReminderSpec.fromDb(
        course.reminderMode,
        course.reminderValue,
      );
      _sessions = sessions
          .map(
            (s) => SessionInput(
              weekday: s.weekday,
              startMinute: s.startMinute,
              endMinute: s.endMinute,
              weeks: s.weeks,
            ),
          )
          .toList();
      if (_sessions.isEmpty) {
        _sessions = [
          const SessionInput(
            weekday: 1,
            startMinute: 8 * 60,
            endMinute: 9 * 60 + 40,
          ),
        ];
      }
      _loaded = true;
    });
  }

  @override
  void dispose() {
    _name.dispose();
    _teacher.dispose();
    _location.dispose();
    _weeks.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty || _sessions.isEmpty) return;

    // 保存前查一遍有没有跟已有安排撞时间
    final db = ref.read(databaseProvider);
    final conflicts = findCourseConflicts(
      sessions: _sessions,
      existingSessions: await loadLiveSessions(db),
      existingItems: await loadLiveItems(db),
      termStart: await loadActiveTermStart(db),
      ignoreCourseId: widget.courseId,
    );
    if (conflicts.isNotEmpty && mounted) {
      final proceed = await confirmTimeConflicts(context, conflicts);
      if (!proceed) return;
    }

    final repo = ref.read(courseRepositoryProvider);
    if (_isEditing) {
      await repo.update(
        widget.courseId!,
        name: name,
        teacher: _nullIfEmpty(_teacher.text),
        location: _nullIfEmpty(_location.text),
        color: _color,
        sessions: _sessions,
        reminder: _reminder,
      );
    } else {
      await repo.create(
        name: name,
        teacher: _nullIfEmpty(_teacher.text),
        location: _nullIfEmpty(_location.text),
        color: _color,
        sessions: _sessions,
        reminder: _reminder,
      );
    }
    if (mounted) Navigator.of(context).pop(true);
  }

  String? _nullIfEmpty(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  Future<void> _delete() async {
    final id = widget.courseId;
    if (id == null) return;
    await ref.read(courseRepositoryProvider).softDelete(id);
    if (mounted) Navigator.of(context).pop(true);
  }

  Future<void> _pickTime(int index) async {
    final session = _sessions[index];
    final start = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(
        hour: session.startMinute ~/ 60,
        minute: session.startMinute % 60,
      ),
    );
    if (start == null || !mounted) return;
    final end = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(
        hour: session.endMinute ~/ 60,
        minute: session.endMinute % 60,
      ),
    );
    if (end == null) return;
    setState(() {
      _sessions[index] = session.copyWith(
        startMinute: start.hour * 60 + start.minute,
        endMinute: end.hour * 60 + end.minute,
      );
    });
  }

  /// 用日期区间反填周次：选 10/12–11/22 → 「第6-11周」→ weeks = "6-11"。
  Future<void> _pickWeeksByDate() async {
    final termStart = ref.read(activeTermProvider).value?.startDate;
    if (termStart == null) return;

    final thisMonday = startOfWeek(DateTime.now());
    final range = await showDateRangePicker(
      context: context,
      firstDate: termStart,
      lastDate: termStart.add(const Duration(days: 7 * 32)),
      initialDateRange: DateTimeRange(
        start: thisMonday,
        end: thisMonday.add(const Duration(days: 6)),
      ),
      helpText: '选择上课的日期区间',
    );
    if (range == null) return;

    final spec =
        WeekHelpers.weeksFromDateRange(range.start, range.end, termStart);
    if (spec == null || !mounted) return;

    setState(() {
      _weeks.text = spec;
      _sessions = [for (final s in _sessions) s.copyWith(weeks: spec)];
    });
  }

  /// 学期起始日缺了的话，「第几周」无从换算，就地在编辑器里补上。
  Future<void> _setTermStart() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2015),
      lastDate: DateTime(2035),
      helpText: '学期第 1 周的开始',
    );
    if (picked == null) return;
    await ref.read(databaseProvider).setActiveTermStart(startOfWeek(picked));
  }

  static String _date(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final term = ref.watch(activeTermProvider).value;
    final termStart = term?.startDate;

    if (!_loaded) {
      return const SizedBox(
        height: 200,
        child: Center(child: CircularProgressIndicator()),
      );
    }

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _name,
              autofocus: !_isEditing,
              decoration: const InputDecoration(
                labelText: '课程名',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _teacher,
                    decoration: const InputDecoration(
                      labelText: '教师（可选）',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _location,
                    decoration: const InputDecoration(
                      labelText: '教室（可选）',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text('颜色', style: theme.textTheme.labelLarge),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: courseColors.map((c) {
                final selected = c == _color;
                return GestureDetector(
                  onTap: () => setState(() => _color = c),
                  child: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: Color(c),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: selected
                            ? theme.colorScheme.onSurface
                            : Colors.transparent,
                        width: 2,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Text('上课时段', style: theme.textTheme.labelLarge),
                const Spacer(),
                TextButton.icon(
                  onPressed: () => setState(() {
                    _sessions = [
                      ..._sessions,
                      const SessionInput(
                        weekday: 1,
                        startMinute: 8 * 60,
                        endMinute: 9 * 60 + 40,
                      ),
                    ];
                  }),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('加一个时段'),
                ),
              ],
            ),
            ..._sessions.asMap().entries.map((entry) {
              final index = entry.key;
              final s = entry.value;
              return Card(
                margin: const EdgeInsets.only(bottom: 6),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  child: Row(
                    children: [
                      DropdownButton<int>(
                        value: s.weekday,
                        underline: const SizedBox.shrink(),
                        items: List.generate(
                          7,
                          (i) => DropdownMenuItem(
                            value: i + 1,
                            child: Text('周${_weekdayLabels[i]}'),
                          ),
                        ),
                        onChanged: (value) => setState(() {
                          _sessions[index] =
                              s.copyWith(weekday: value ?? s.weekday);
                        }),
                      ),
                      const SizedBox(width: 8),
                      TextButton(
                        onPressed: () => _pickTime(index),
                        child: Text(
                          '${formatMinute(s.startMinute)} – ${formatMinute(s.endMinute)}',
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.close, size: 18),
                        onPressed: _sessions.length == 1
                            ? null
                            : () => setState(() {
                                  _sessions = [..._sessions]..removeAt(index);
                                }),
                      ),
                    ],
                  ),
                ),
              );
            }),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextField(
                    controller: _weeks,
                    decoration: const InputDecoration(
                      labelText: '周次（* 每周 / 单 / 双 / 1-16 / 1,3,5）',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (value) {
                      final spec = value.trim().isEmpty ? '*' : value.trim();
                      setState(() {
                        _sessions = [
                          for (final s in _sessions) s.copyWith(weeks: spec),
                        ];
                      });
                    },
                  ),
                ),
                if (termStart != null) ...[
                  const SizedBox(width: 8),
                  OutlinedButton(
                    onPressed: _pickWeeksByDate,
                    child: const Text('按日期选'),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 6),
            if (termStart == null)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.info_outline,
                            size: 18,
                            color: theme.colorScheme.tertiary,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '还没设置学期起始日',
                            style: theme.textTheme.titleSmall,
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '不知道第 1 周是几月几日，「第 3 周」就没法换算成日期，'
                        '单双周也没法过滤。',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      TextButton.icon(
                        onPressed: _setTermStart,
                        icon: const Icon(Icons.event, size: 18),
                        label: const Text('设置起始日'),
                      ),
                    ],
                  ),
                ),
              )
            else
              Text(
                '第 1 周从 ${_date(termStart)} 开始，'
                '现在第 ${weekNumberFor(DateTime.now(), termStart)} 周 · '
                '本课程的周次：${WeekHelpers.describeWeeks(
                  _weeks.text.trim().isEmpty ? '*' : _weeks.text.trim(),
                  termStart,
                  weekCount: term?.weekCount ?? 20,
                )}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            const SizedBox(height: 12),
            Card(
              margin: EdgeInsets.zero,
              child: ReminderPickerTile(
                spec: _reminder,
                fallback: ref.watch(defaultReminderProvider).value ??
                    ReminderSpec.defaultValue,
                onChanged: (spec) => setState(() => _reminder = spec),
              ),
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _name.text.trim().isEmpty ? null : _save,
              child: Text(_isEditing ? '保存修改' : '添加课程'),
            ),
            if (_isEditing) ...[
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: _delete,
                icon: const Icon(Icons.delete_outline),
                label: const Text('删除课程'),
                style: TextButton.styleFrom(
                  foregroundColor: theme.colorScheme.error,
                ),
              ),
            ],
            const SizedBox(height: 8),
            Text(
              '提示：课表页可以粘贴教务系统的课表文本批量导入。',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
