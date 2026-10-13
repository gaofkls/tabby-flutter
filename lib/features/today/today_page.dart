import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/app_database.dart';
import '../memo/item_providers.dart';
import '../memo/item_tile.dart';
import '../memo/memo_editor.dart';

class TodayPage extends ConsumerWidget {
  const TodayPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(itemsProvider);
    final now = DateTime.now();
    final today = dateKey(now);

    return Scaffold(
      appBar: AppBar(title: const Text('今日')),
      floatingActionButton: FloatingActionButton(
        onPressed: () => showMemoEditor(context),
        child: const Icon(Icons.add),
      ),
      body: items.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(child: Text('出错了：$err')),
        data: (list) {
          final overdue = list
              .where((e) =>
                  e.dueDate != null &&
                  dateKey(e.dueDate!).isBefore(today) &&
                  !e.done)
              .toList()
            ..sort((a, b) => a.dueDate!.compareTo(b.dueDate!));

          final hourPrecision = list
              .where((e) =>
                  e.dueDate != null &&
                  isSameDay(e.dueDate!, today) &&
                  e.dueMinute != null)
              .toList()
            ..sort((a, b) => a.dueMinute!.compareTo(b.dueMinute!));

          final dayPrecision = list
              .where((e) =>
                  e.dueDate != null &&
                  isSameDay(e.dueDate!, today) &&
                  e.dueMinute == null)
              .toList();

          final anytime = list
              .where((e) => e.dueDate == null && e.dueMinute == null)
              .toList();

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                '${now.year} 年 ${now.month} 月 ${now.day} 日',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 16),
              if (overdue.isNotEmpty)
                _Section(
                  title: '已过期',
                  subtitle: '日期已过，还没完成',
                  children: overdue,
                ),
              _Section(
                title: '今天 · 精确到小时',
                subtitle: '按时间排进时间轴',
                children: hourPrecision,
              ),
              _Section(
                title: '今天 · 精确到天',
                subtitle: '只占当天，不进时间轴',
                children: dayPrecision,
              ),
              _Section(
                title: '不限时间',
                subtitle: '没写日期，一直留在待办里',
                children: anytime,
              ),
              const SizedBox(height: 24),
              Text(
                '其他日期的备忘在「备忘」页。',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.subtitle,
    required this.children,
  });

  final String title;
  final String subtitle;
  final List<Item> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: theme.textTheme.titleSmall),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          if (children.isEmpty)
            const Text('—')
          else
            ...children.map((item) => ItemTile(item: item)),
        ],
      ),
    );
  }
}
