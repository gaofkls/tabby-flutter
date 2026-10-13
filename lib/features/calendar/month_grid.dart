import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/app_database.dart';
import '../../data/occurrence.dart';
import '../memo/memo_editor.dart';

const _weekdayLabels = ['一', '二', '三', '四', '五', '六', '日'];

/// 月日历：粗略视图。每格只给日期 + 当天要做的事的缩略条，
/// 点一下弹出这一天的完整清单。课程和备忘混排。
class MonthCalendar extends StatelessWidget {
  const MonthCalendar({
    super.key,
    required this.month,
    required this.occurrences,
  });

  final DateTime month;
  final OccurrenceSet occurrences;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final today = DateTime.now();
    final first = DateTime(month.year, month.month, 1);
    final offset = first.weekday - 1;
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    final cellCount = ((offset + daysInMonth) / 7).ceil() * 7;
    final gridStart = first.subtract(Duration(days: offset));

    final byDay = <DateTime, List<Occurrence>>{};
    for (final o in [...occurrences.timed, ...occurrences.allDay]) {
      byDay.putIfAbsent(dateOnly(o.date), () => []).add(o);
    }
    for (final list in byDay.values) {
      list.sort((a, b) {
        final am = a.startMinute;
        final bm = b.startMinute;
        if (am == null && bm == null) return 0;
        if (am == null) return -1;
        if (bm == null) return 1;
        return am.compareTo(bm);
      });
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final cellWidth = constraints.maxWidth / 7;

        return SingleChildScrollView(
          child: Column(
            children: [
              Row(
                children: _weekdayLabels
                    .map(
                      (d) => SizedBox(
                        width: cellWidth,
                        child: Center(
                          child: Text(d, style: theme.textTheme.bodySmall),
                        ),
                      ),
                    )
                    .toList(),
              ),
              const Divider(height: 1),
              for (var row = 0; row < cellCount ~/ 7; row++)
                Row(
                  children: List.generate(7, (col) {
                    final date = gridStart.add(
                      Duration(days: row * 7 + col),
                    );
                    final inMonth = date.month == month.month;
                    final isToday = date.year == today.year &&
                        date.month == today.month &&
                        date.day == today.day;
                    final list = byDay[dateOnly(date)] ?? const <Occurrence>[];

                    return GestureDetector(
                      onTap: () => _openDay(context, date, list),
                      child: SizedBox(
                        width: cellWidth,
                        height: 92,
                        child: Container(
                          decoration: BoxDecoration(
                            border: Border(
                              right: BorderSide(
                                color: theme.dividerColor.withValues(alpha: 0.2),
                              ),
                              bottom: BorderSide(
                                color: theme.dividerColor.withValues(alpha: 0.2),
                              ),
                            ),
                            color: isToday
                                ? theme.colorScheme.primaryContainer
                                    .withValues(alpha: 0.35)
                                : null,
                          ),
                          padding: const EdgeInsets.all(3),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${date.day}',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: isToday
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                  color: inMonth
                                      ? null
                                      : theme.colorScheme.onSurfaceVariant
                                          .withValues(alpha: 0.5),
                                ),
                              ),
                              const SizedBox(height: 2),
                              ...list.take(3).map(
                                    (o) => _MiniBar(occurrence: o),
                                  ),
                              if (list.length > 3)
                                Text(
                                  '+${list.length - 3}',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    fontSize: 10,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }),
                ),
              if (occurrences.untimed.isNotEmpty) ...[
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '不限时间的备忘（未指定日期）',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: occurrences.untimed
                            .map((item) => _UntimedChip(item: item))
                            .toList(),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Future<void> _openDay(
    BuildContext context,
    DateTime date,
    List<Occurrence> list,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) {
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.7,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                  child: Row(
                    children: [
                      Text(
                        formatDateLabel(date),
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const Spacer(),
                      Text(
                        '共 ${list.length} 项',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                if (list.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Text('这一天没有安排'),
                  )
                else
                  Flexible(
                    child: ListView.separated(
                      itemCount: list.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final o = list[index];
                        return ListTile(
                          dense: true,
                          leading: SizedBox(
                            width: 44,
                            child: Text(
                              o.startMinute == null
                                  ? '全天'
                                  : formatMinute(o.startMinute!),
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ),
                          title: Text(
                            o.title,
                            style: o.done
                                ? const TextStyle(
                                    decoration: TextDecoration.lineThrough,
                                  )
                                : null,
                          ),
                          subtitle: Text(
                            o.isCourse ? '课程' : '备忘',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          trailing: o.item == null
                              ? null
                              : const Icon(Icons.edit_outlined, size: 18),
                          onTap: o.item == null
                              ? null
                              : () {
                                  Navigator.of(context).pop();
                                  showMemoEditor(context, item: o.item!);
                                },
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _MiniBar extends StatelessWidget {
  const _MiniBar({required this.occurrence});

  final Occurrence occurrence;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isCourse = occurrence.isCourse;
    final background = isCourse
        ? (occurrence.colorValue != null
            ? Color(occurrence.colorValue!).withValues(alpha: 0.28)
            : theme.colorScheme.primaryContainer)
        : theme.colorScheme.tertiaryContainer;
    final foreground = isCourse
        ? (occurrence.colorValue != null
            ? theme.colorScheme.onSurface
            : theme.colorScheme.onPrimaryContainer)
        : theme.colorScheme.onTertiaryContainer;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 2),
      padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(
        occurrence.startMinute == null
            ? occurrence.title
            : '${formatMinute(occurrence.startMinute!)} ${occurrence.title}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 10,
          color: foreground,
          decoration: occurrence.done ? TextDecoration.lineThrough : null,
        ),
      ),
    );
  }
}

class _UntimedChip extends ConsumerWidget {
  const _UntimedChip({required this.item});

  final Item item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: () => showMemoEditor(context, item: item),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: theme.colorScheme.tertiaryContainer,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          item.title,
          style: TextStyle(
            fontSize: 12,
            color: theme.colorScheme.onTertiaryContainer,
          ),
        ),
      ),
    );
  }
}
