import 'package:flutter/material.dart';

import '../../data/conflicts.dart';

/// 保存前撞车了：弹窗列出跟谁撞、撞在什么时候。
/// 返回 true 表示「不管了，仍然保存」。
Future<bool> confirmTimeConflicts(
  BuildContext context,
  List<Conflict> conflicts,
) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) {
      final theme = Theme.of(context);
      return AlertDialog(
        icon: const Icon(Icons.event_busy_outlined),
        title: const Text('时间冲突'),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                conflicts.length == 1
                    ? '这个时间和已有的 1 项安排撞了：'
                    : '这个时间和已有的 ${conflicts.length} 项安排撞了：',
              ),
              const SizedBox(height: 12),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: conflicts
                      .map(
                        (c) => ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(
                            c.kind == '课程'
                                ? Icons.menu_book_outlined
                                : c.kind == '备忘'
                                    ? Icons.check_box_outlined
                                    : Icons.content_copy,
                            size: 20,
                          ),
                          title: Text(c.title),
                          subtitle: Text(c.detail),
                        ),
                      )
                      .toList(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('返回修改'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(
              foregroundColor: theme.colorScheme.onErrorContainer,
              backgroundColor: theme.colorScheme.errorContainer,
            ),
            child: const Text('仍然保存'),
          ),
        ],
      );
    },
  );
  return result ?? false;
}
