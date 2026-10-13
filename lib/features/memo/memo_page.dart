import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/app_database.dart';
import 'item_providers.dart';
import 'item_tile.dart';
import 'memo_editor.dart';

/// 全部备忘，按日期分组的时间轴视图。
class MemoPage extends ConsumerWidget {
  const MemoPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(itemsProvider);
    final today = dateKey(DateTime.now());

    return Scaffold(
      appBar: AppBar(title: const Text('备忘')),
      floatingActionButton: FloatingActionButton(
        onPressed: () => showMemoEditor(context),
        child: const Icon(Icons.add),
      ),
      body: items.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(child: Text('出错了：$err')),
        data: (list) {
          if (list.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  '还没有备忘。点右下角 + 添加一条，\n'
                  '可以不限时间，也可以精确到天或小时。',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          final anytime = list
              .where(
                  (e) => e.dueDate == null && e.dueMinute == null && !e.done)
              .toList();
          final overdue = list
              .where((e) =>
                  e.dueDate != null &&
                  dateKey(e.dueDate!).isBefore(today) &&
                  !e.done)
              .toList()
            ..sort((a, b) => a.dueDate!.compareTo(b.dueDate!));
          final done = list.where((e) => e.done).toList();

          // 今天及以后，按日期分组
          final groups = <DateTime, List<Item>>{};
          for (final item in list) {
            if (item.dueDate == null || item.done) continue;
            final key = dateKey(item.dueDate!);
            if (key.isBefore(today)) continue;
            groups.putIfAbsent(key, () => []).add(item);
          }
          final dates = groups.keys.toList()..sort();
          for (final itemsInDay in groups.values) {
            itemsInDay.sort((a, b) {
              final am = a.dueMinute;
              final bm = b.dueMinute;
              if (am == null && bm == null) return 0;
              if (am == null) return -1;
              if (bm == null) return 1;
              return am.compareTo(bm);
            });
          }

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
            children: [
              if (anytime.isNotEmpty)
                _Group(title: '不限时间', children: anytime),
              if (overdue.isNotEmpty)
                _Group(title: '已过期', children: overdue),
              ...dates.map(
                (date) => _Group(
                  title: _dateTitle(date, today),
                  children: groups[date]!,
                  inDayGroup: true,
                ),
              ),
              if (done.isNotEmpty) _Group(title: '已完成', children: done),
            ],
          );
        },
      ),
    );
  }

  static String _dateTitle(DateTime date, DateTime today) {
    final label = formatDateLabel(date);
    return switch (date.difference(today).inDays) {
      0 => '$label · 今天',
      1 => '$label · 明天',
      2 => '$label · 后天',
      _ => label,
    };
  }
}

class _Group extends StatelessWidget {
  const _Group({
    required this.title,
    required this.children,
    this.inDayGroup = false,
  });

  final String title;
  final List<Item> children;
  final bool inDayGroup;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.titleSmall?.copyWith(
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(height: 8),
          if (children.isEmpty)
            Text(
              '—',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            )
          else
            ...children.map(
              (item) => ItemTile(item: item, showDate: inDayGroup),
            ),
        ],
      ),
    );
  }
}
