import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/app_database.dart';
import '../../data/occurrence.dart';
import '../calendar/month_grid.dart';
import '../memo/item_providers.dart';
import '../memo/memo_editor.dart';
import '../reminder/batch_reminder_sheet.dart';
import 'course_editor.dart';
import 'course_import_page.dart';
import 'week_grid.dart';

enum TimetableViewMode { week, month }

/// 同一份数据的两种密度：周课表（详细）/ 月日历（粗略）。
/// 课程和备忘在这两个视图里都能看到。
class TimetablePage extends ConsumerStatefulWidget {
  const TimetablePage({super.key});

  @override
  ConsumerState<TimetablePage> createState() => _TimetablePageState();
}

class _TimetablePageState extends ConsumerState<TimetablePage> {
  TimetableViewMode _mode = TimetableViewMode.week;
  DateTime _focused = DateTime.now();

  DateTime get _rangeStart {
    if (_mode == TimetableViewMode.week) return startOfWeek(_focused);
    final first = startOfMonth(_focused);
    return first.subtract(Duration(days: first.weekday - 1));
  }

  DateTime get _rangeEnd {
    if (_mode == TimetableViewMode.week) {
      return startOfWeek(_focused).add(const Duration(days: 6));
    }
    final first = startOfMonth(_focused);
    final start = first.subtract(Duration(days: first.weekday - 1));
    final daysInMonth = DateTime(first.year, first.month + 1, 0).day;
    final cellCount = ((first.weekday - 1 + daysInMonth) / 7).ceil() * 7;
    return start.add(Duration(days: cellCount - 1));
  }

  void _shift(int days) {
    setState(() => _focused = _focused.add(Duration(days: days)));
  }

  void _jumpMonth(int delta) {
    setState(() => _focused = DateTime(_focused.year, _focused.month + delta, 1));
  }

  String get _title {
    if (_mode == TimetableViewMode.week) {
      final start = startOfWeek(_focused);
      final end = start.add(const Duration(days: 6));
      return '${start.month}月${start.day}日 – ${end.month}月${end.day}日';
    }
    return '${_focused.year} 年 ${_focused.month} 月';
  }

  Future<void> _openAddMenu(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.note_add_outlined),
                title: const Text('新建备忘'),
                subtitle: const Text('可以不限时间 / 精确到天 / 精确到小时'),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  showMemoEditor(context);
                },
              ),
              ListTile(
                leading: const Icon(Icons.library_add_outlined),
                title: const Text('新建课程'),
                subtitle: const Text('填课名、星期、时间、教室'),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  showCourseEditor(context);
                },
              ),
              ListTile(
                leading: const Icon(Icons.content_paste_go_outlined),
                title: const Text('粘贴导入课表'),
                subtitle: const Text('把教务系统的课表整段粘进来，自动解析'),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const CourseImportPage(),
                    ),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.notifications_active_outlined),
                title: const Text('批量设置提醒'),
                subtitle: const Text('一次给课程 / 备忘设同一条提醒'),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  showBatchReminderSheet(context);
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final sessionsAsync = ref.watch(sessionsWithCourseProvider);
    final itemsAsync = ref.watch(itemsProvider);
    final term = ref.watch(activeTermProvider).asData?.value;

    return Scaffold(
      appBar: AppBar(
        title: Text(_title),
        actions: [
          IconButton(
            tooltip: '上一个',
            icon: const Icon(Icons.chevron_left),
            onPressed: () =>
                _mode == TimetableViewMode.week ? _shift(-7) : _jumpMonth(-1),
          ),
          IconButton(
            tooltip: '回到今天',
            icon: const Icon(Icons.today_outlined),
            onPressed: () => setState(() => _focused = DateTime.now()),
          ),
          IconButton(
            tooltip: '下一个',
            icon: const Icon(Icons.chevron_right),
            onPressed: () =>
                _mode == TimetableViewMode.week ? _shift(7) : _jumpMonth(1),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _openAddMenu(context),
        child: const Icon(Icons.add),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: SegmentedButton<TimetableViewMode>(
              segments: const [
                ButtonSegment(
                  value: TimetableViewMode.week,
                  icon: Icon(Icons.view_week_outlined),
                  label: Text('周课表'),
                ),
                ButtonSegment(
                  value: TimetableViewMode.month,
                  icon: Icon(Icons.calendar_month_outlined),
                  label: Text('月日历'),
                ),
              ],
              selected: {_mode},
              onSelectionChanged: (selection) {
                setState(() => _mode = selection.first);
              },
            ),
          ),
          Expanded(
            child: sessionsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (err, _) => Center(child: Text('出错了：$err')),
              data: (sessions) => itemsAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (err, _) => Center(child: Text('出错了：$err')),
                data: (List<Item> items) {
                  final set = buildOccurrences(
                    from: _rangeStart,
                    to: _rangeEnd,
                    sessions: sessions,
                    items: items,
                    termStart: term?.startDate,
                  );

                  if (_mode == TimetableViewMode.week) {
                    return WeekTimetable(
                      weekStart: startOfWeek(_focused),
                      occurrences: set,
                    );
                  }
                  return MonthCalendar(
                    month: startOfMonth(_focused),
                    occurrences: set,
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
