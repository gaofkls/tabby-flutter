import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/app_database.dart';
import '../../data/occurrence.dart';
import '../memo/memo_editor.dart';
import 'course_editor.dart';

const _startHour = 7;
const _endHour = 22;
const _hourHeight = 58.0;
const _gutter = 52.0;

const _weekdayLabels = ['一', '二', '三', '四', '五', '六', '日'];

/// 周课表：时间轴网格。课程和「精确到小时」的备忘都画进格子，
/// 「精确到天 / 不限时间」的备忘放在顶部条带里。
class WeekTimetable extends StatelessWidget {
  const WeekTimetable({
    super.key,
    required this.weekStart,
    required this.occurrences,
  });

  final DateTime weekStart;
  final OccurrenceSet occurrences;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final today = DateTime.now();
    final days = List<DateTime>.generate(
      7,
      (i) => weekStart.add(Duration(days: i)),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final colWidth = (constraints.maxWidth - _gutter) / 7;

        final byDay = List.generate(7, (_) => <Occurrence>[]);
        for (final o in occurrences.timed) {
          final index = o.date.weekday - 1;
          if (index >= 0 && index < 7) byDay[index].add(o);
        }

        // 同一天里时间段重叠的并排显示
        final laneOf = <Occurrence, int>{};
        final laneCount = List<int>.filled(7, 1);
        for (var d = 0; d < 7; d++) {
          final list = byDay[d]
            ..sort((a, b) => a.startMinute!.compareTo(b.startMinute!));
          final laneEnd = <int>[];
          for (final o in list) {
            final end = o.endMinute ?? (o.startMinute! + 60);
            var lane = laneEnd.indexWhere((e) => e <= o.startMinute!);
            if (lane == -1) {
              laneEnd.add(end);
              lane = laneEnd.length - 1;
            } else {
              laneEnd[lane] = end;
            }
            laneOf[o] = lane;
          }
          laneCount[d] = laneEnd.isEmpty ? 1 : laneEnd.length;
        }

        final blocks = <Widget>[];
        for (var d = 0; d < 7; d++) {
          final width = colWidth / laneCount[d];
          for (final o in byDay[d]) {
            final start = o.startMinute! / 60;
            final end = (o.endMinute ?? o.startMinute! + 60) / 60;
            final top = (start - _startHour) * _hourHeight;
            final height = (end - start) * _hourHeight;
            if (top > (_endHour - _startHour) * _hourHeight) continue;
            blocks.add(
              Positioned(
                left: _gutter + d * colWidth + laneOf[o]! * width + 1,
                top: top + 1,
                width: width - 2,
                height: height < 18 ? 18 : height - 2,
                child: _Block(occurrence: o),
              ),
            );
          }
        }

        return SingleChildScrollView(
          child: Column(
            children: [
              Row(
                children: [
                  const SizedBox(width: _gutter),
                  ...List.generate(7, (i) {
                    final day = days[i];
                    final isToday = day.year == today.year &&
                        day.month == today.month &&
                        day.day == today.day;
                    return SizedBox(
                      width: colWidth,
                      child: Column(
                        children: [
                          Text(
                            '周${_weekdayLabels[i]}',
                            style: theme.textTheme.bodySmall,
                          ),
                          const SizedBox(height: 2),
                          Container(
                            width: 26,
                            height: 26,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: isToday ? theme.colorScheme.primary : null,
                            ),
                            child: Text(
                              '${day.day}',
                              style: TextStyle(
                                color: isToday
                                    ? theme.colorScheme.onPrimary
                                    : null,
                                fontWeight: isToday ? FontWeight.bold : null,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                ],
              ),
              const Divider(height: 1),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: _gutter,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        '全天',
                        style: theme.textTheme.bodySmall,
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                  ...List.generate(7, (i) {
                    final list = occurrences.allDay
                        .where((o) => o.date.weekday - 1 == i)
                        .toList();
                    return SizedBox(
                      width: colWidth,
                      child: Padding(
                        padding: const EdgeInsets.all(2),
                        child: Column(
                          children: [
                            ...list.take(2).map((o) => _Chip(occurrence: o)),
                            if (list.length > 2)
                              Padding(
                                padding: const EdgeInsets.only(top: 2),
                                child: Text(
                                  '+${list.length - 2}',
                                  style: theme.textTheme.bodySmall,
                                ),
                              ),
                          ],
                        ),
                      ),
                    );
                  }),
                ],
              ),
              const Divider(height: 1),
              SizedBox(
                height: (_endHour - _startHour) * _hourHeight,
                child: Stack(
                  children: [
                    for (var h = _startHour; h <= _endHour; h++)
                      Positioned(
                        left: 0,
                        right: 0,
                        top: (h - _startHour) * _hourHeight,
                        child: Divider(
                          height: 1,
                          color: theme.dividerColor.withValues(alpha: 0.35),
                        ),
                      ),
                    for (var i = 0; i <= 7; i++)
                      Positioned(
                        left: _gutter + i * colWidth,
                        top: 0,
                        bottom: 0,
                        child: VerticalDivider(
                          width: 1,
                          color: theme.dividerColor.withValues(alpha: 0.35),
                        ),
                      ),
                    for (var h = _startHour; h < _endHour; h++)
                      Positioned(
                        left: 0,
                        width: _gutter - 8,
                        top: (h - _startHour) * _hourHeight - 7,
                        child: Text(
                          '$h:00',
                          textAlign: TextAlign.right,
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontSize: 11,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ...blocks,
                  ],
                ),
              ),
              if (occurrences.untimed.isNotEmpty) ...[
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '不限时间的备忘',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: occurrences.untimed
                            .map((item) => _ItemChip(item: item))
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
}

class _Block extends StatelessWidget {
  const _Block({required this.occurrence});

  final Occurrence occurrence;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isCourse = occurrence.isCourse;

    final Color background;
    final Color foreground;
    if (isCourse) {
      final value = occurrence.colorValue;
      if (value != null) {
        background = Color(value).withValues(alpha: 0.28);
        foreground = theme.colorScheme.onSurface;
      } else {
        background = theme.colorScheme.primaryContainer;
        foreground = theme.colorScheme.onPrimaryContainer;
      }
    } else {
      background = theme.colorScheme.tertiaryContainer;
      foreground = theme.colorScheme.onTertiaryContainer;
    }

    final start = occurrence.startMinute!;

    return GestureDetector(
      onTap: () {
        if (occurrence.item != null) {
          showMemoEditor(context, item: occurrence.item!);
        } else if (occurrence.courseId != null) {
          showCourseEditor(context, courseId: occurrence.courseId!);
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
        decoration: BoxDecoration(
          color: occurrence.done
              ? background.withValues(alpha: 0.45)
              : background,
          borderRadius: BorderRadius.circular(5),
          border: Border.all(
            color: (isCourse ? foreground : theme.colorScheme.tertiary)
                .withValues(alpha: 0.35),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              occurrence.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: foreground,
                decoration:
                    occurrence.done ? TextDecoration.lineThrough : null,
              ),
            ),
            if (occurrence.subtitle != null)
              Text(
                occurrence.subtitle!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 10, color: foreground),
              ),
            Text(
              formatMinute(start),
              style: TextStyle(fontSize: 10, color: foreground),
            ),
          ],
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.occurrence});

  final Occurrence occurrence;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: occurrence.item == null
          ? null
          : () => showMemoEditor(context, item: occurrence.item!),
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 3),
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        decoration: BoxDecoration(
          color: theme.colorScheme.tertiaryContainer,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          occurrence.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 10,
            color: theme.colorScheme.onTertiaryContainer,
            decoration: occurrence.done ? TextDecoration.lineThrough : null,
          ),
        ),
      ),
    );
  }
}

class _ItemChip extends ConsumerWidget {
  const _ItemChip({required this.item});

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
