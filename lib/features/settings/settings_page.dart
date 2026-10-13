import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/router.dart';
import '../../data/occurrence.dart';
import '../../data/reminder.dart';
import '../../data/reminder_providers.dart';
import '../../data/week_helpers.dart';
import '../../services/notification_service.dart';
import '../reminder/reminder_picker.dart';

class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  static String _date(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  int _pending = 0;
  bool? _permission;
  bool? _exactAlarm;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _refreshNotificationState();
  }

  Future<void> _refreshNotificationState() async {
    _pending = await NotificationService.instance.pendingCount();
    _permission = NotificationService.instance.permissionGranted;
    _exactAlarm = NotificationService.instance.exactAlarmGranted;
    if (mounted) setState(() {});
  }

  Future<void> _reschedule() async {
    setState(() => _busy = true);
    await ref.read(reminderSchedulerProvider).reschedule();
    await _refreshNotificationState();
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _applyTo({required bool courses, required bool items}) async {
    final spec = await ref.read(databaseProvider).defaultReminder();
    final count = await ref
        .read(databaseProvider)
        .applyReminder(toCourses: courses, toItems: items, spec: spec);
    await _reschedule();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已给 $count 条记录应用「${spec.label}」')),
    );
  }

  Future<void> _clearOverrides() async {
    final count = await ref
        .read(databaseProvider)
        .applyReminder(toCourses: true, toItems: true, spec: null);
    await _reschedule();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已把 $count 条记录改回跟随默认')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final db = ref.watch(databaseProvider);
    final theme = Theme.of(context);
    final term = ref.watch(activeTermProvider).value;
    final termStart = term?.startDate;
    final defaultSpec = ref.watch(defaultReminderProvider).value ??
        ReminderSpec.defaultValue;

    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: ListView(
          children: [
            Text(
              '数据完全存在本机 SQLite 里，离线可用。'
              '每条记录已带 id / updatedAt / deletedAt，将来接同步不用重改表。',
            ),
            const SizedBox(height: 20),
            Text('学期', style: theme.textTheme.titleSmall),
            const SizedBox(height: 4),
            Card(
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.event_outlined),
                    title: const Text('学期起始日（第 1 周的周一）'),
                    subtitle: Text(
                      termStart == null
                          ? '未设置 —— 单双周和第几周无法换算'
                          : '${_date(termStart)} · '
                              '现在第 ${weekNumberFor(DateTime.now(), termStart)} 周'
                              '（${WeekHelpers.describeWeeks(
                                '${weekNumberFor(DateTime.now(), termStart)}',
                                termStart,
                              )}）',
                    ),
                    trailing: TextButton(
                      onPressed: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: termStart ?? DateTime.now(),
                          firstDate: DateTime(2015),
                          lastDate: DateTime(2035),
                          helpText: '学期第 1 周的开始',
                        );
                        if (picked == null) return;
                        await db.setActiveTermStart(startOfWeek(picked));
                      },
                      child: const Text('修改'),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    child: Text(
                      '导入教务系统课表时会自动从页面里反推这个值；'
                      '手动加课时也可以在这里先设好。',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Text('提醒', style: theme.textTheme.titleSmall),
            const SizedBox(height: 4),
            Card(
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.notifications_outlined),
                    title: const Text('默认提醒'),
                    subtitle: Text('新建的课程和备忘默认用这一条：${defaultSpec.label}'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () async {
                      final picked = await showReminderPicker(
                        context,
                        current: defaultSpec,
                        fallback: defaultSpec,
                      );
                      final spec = picked ?? ReminderSpec.defaultValue;
                      await db.setDefaultReminder(spec);
                      await _reschedule();
                    },
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.alarm_on_outlined),
                    title: const Text('系统通知'),
                    subtitle: Text(
                      _permission == null
                          ? '还没请求权限'
                          : (_permission! ? '已授权' : '未授权 —— 通知发不出来'),
                    ),
                    trailing: TextButton(
                      onPressed: () async {
                        await NotificationService.instance.requestPermission();
                        await _refreshNotificationState();
                      },
                      child: const Text('请求权限'),
                    ),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.alarm_outlined),
                    title: const Text('精确闹钟权限'),
                    subtitle: Text(
                      _exactAlarm == null
                          ? '无法判断（当前平台）'
                          : (_exactAlarm!
                              ? '已授权 —— 定时提醒会精确响铃'
                              : '未授权 —— 定时提醒可能不响，请在系统里允许「闹钟与提醒」'),
                    ),
                    trailing: _exactAlarm == true
                        ? null
                        : TextButton(
                            onPressed: () async {
                              await NotificationService.instance
                                  .requestExactAlarmsPermission();
                              await _refreshNotificationState();
                              await _reschedule();
                            },
                            child: const Text('去授予'),
                          ),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.schedule_send_outlined),
                    title: const Text('已排定的提醒'),
                    subtitle: Text(
                      _busy ? '正在重排…' : '系统里现在有 $_pending 条待发通知',
                    ),
                    trailing: TextButton(
                      onPressed: _busy ? null : _reschedule,
                      child: const Text('立即重排'),
                    ),
                  ),
                  const Divider(height: 1),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '批量设置',
                          style: theme.textTheme.labelLarge,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '想把已有的课程 / 备忘一次性设成同一条提醒，'
                          '比如全部「前一天晚上」提醒，用下面两个按钮。',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            FilledButton.tonalIcon(
                              onPressed: () =>
                                  _applyTo(courses: true, items: false),
                              icon: const Icon(Icons.menu_book_outlined,
                                  size: 18),
                              label: const Text('应用到全部课程'),
                            ),
                            FilledButton.tonalIcon(
                              onPressed: () =>
                                  _applyTo(courses: false, items: true),
                              icon: const Icon(Icons.checklist_outlined,
                                  size: 18),
                              label: const Text('应用到全部备忘'),
                            ),
                            OutlinedButton.icon(
                              onPressed: _clearOverrides,
                              icon: const Icon(Icons.undo_outlined, size: 18),
                              label: const Text('清除单独设置'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '单条记录的提醒可以在备忘 / 课表的编辑器里单独改，'
                          '条目右侧的「⋮」菜单也能快速设。',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Text('示例数据', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            Wrap(
              spacing: 12,
              children: [
                FilledButton.tonal(
                  onPressed: () async {
                    await db.seedDemoData();
                  },
                  child: const Text('写入示例备忘'),
                ),
                FilledButton.tonal(
                  onPressed: () async {
                    await db.seedDemoCourses();
                  },
                  child: const Text('写入示例课表'),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Text(
              '同步、导入导出、主题、语言、节次作息表 —— 待实现',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
