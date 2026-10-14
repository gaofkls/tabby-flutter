import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:home_widget/home_widget.dart';

import '../../app/router.dart';
import '../../data/alarm_mode.dart';
import '../../data/occurrence.dart';
import '../../data/reminder.dart';
import '../../data/reminder_providers.dart';
import '../../data/week_helpers.dart';
import '../../services/alarm_service.dart';
import '../../services/notification_service.dart';
import '../../services/system_settings.dart';
import '../../services/widget_data_service.dart';
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

  ReminderDelivery _delivery = ReminderDelivery.notification;
  int _alarmsPending = 0;
  AlarmRingProfile _ring = const AlarmRingProfile();

  /// 桌面上已经加了的本 App 小组件数量。-1 表示查不到（平台不支持等）。
  int _installedWidgets = -1;
  String _widgetDataSummary = '未知';

  @override
  void initState() {
    super.initState();
    _refreshNotificationState();
  }

  Future<void> _refreshNotificationState() async {
    _pending = await NotificationService.instance.pendingCount();
    _permission = NotificationService.instance.permissionGranted;
    _exactAlarm = NotificationService.instance.exactAlarmGranted;
    _delivery = await AlarmService.instance.loadMode();
    _alarmsPending = await AlarmService.instance.pendingCount();
    _ring = await AlarmService.instance.loadRingProfile();
    await _refreshWidgetDiagnostics();
    if (mounted) setState(() {});
  }

  /// 排障用：10 秒后弹出 App 的响铃页面（真闹钟那条路）。
  Future<void> _testAlarmScreen() async {
    final count = await AlarmService.instance.scheduleAll([
      ReminderTask(
        title: 'Tabby 闹钟测试',
        body: _ring.summary,
        scheduledAt: DateTime.now().add(const Duration(seconds: 10)),
      ),
    ]);
    await _refreshNotificationState();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(count > 0
            ? '已排 1 条，10 秒后按「${_ring.summary}」响（测完记得点「立即重排」恢复）'
            : '排不上：当前平台不支持原生闹钟'),
      ),
    );
  }

  /// 排障用：打开系统「设置闹钟」界面，验证系统时钟那条路通不通。
  Future<void> _testSystemAlarm() async {
    final at = DateTime.now().add(const Duration(minutes: 2));
    final ok = await AlarmService.instance.openSystemAlarm(
      hour: at.hour,
      minute: at.minute,
      message: 'Tabby 提醒',
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(ok
            ? '已打开系统闹钟界面，确认后由系统时钟负责响铃'
            : '打不开：这台设备没有可用的系统闹钟界面'),
      ),
    );
  }

  Future<void> _updateRing(AlarmRingProfile next) async {
    setState(() => _ring = next);
    await AlarmService.instance.saveRingProfile(next);
  }

  /// 一行「标签 + 若干候选值」的选择器。
  Widget _chipRow(
    String label,
    List<int> values,
    int selected,
    ValueChanged<int> onPick,
    String Function(int) format,
  ) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: 84,
          child: Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        Expanded(
          child: Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              for (final v in values)
                ChoiceChip(
                  label: Text(format(v)),
                  selected: selected == v,
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  onSelected: (_) => onPick(v),
                ),
            ],
          ),
        ),
      ],
    );
  }

  /// 小组件的排障信息：系统里有没有加、数据快照写没写进去。
  /// 有了这个就能区分「没添加到桌面」和「添加了但没数据」。
  Future<void> _refreshWidgetDiagnostics() async {
    try {
      final installed = await HomeWidget.getInstalledWidgets();
      _installedWidgets = installed.length;
    } catch (_) {
      _installedWidgets = -1;
    }
    try {
      final raw =
          await HomeWidget.getWidgetData<String>(WidgetDataService.dataKey);
      if (raw == null) {
        _widgetDataSummary = '未写入';
      } else {
        final decoded = jsonDecode(raw);
        final items =
            (decoded is Map ? decoded['items'] as List<dynamic>? : null) ?? [];
        _widgetDataSummary = '已写入 ${items.length} 条';
      }
    } catch (_) {
      _widgetDataSummary = '读取失败';
    }
  }

  /// 排障用：立刻发一条通知，验证通知权限 + 渠道是否真的能显示。
  Future<void> _testNotification() async {
    final ok = await NotificationService.instance.showNow();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(ok
            ? '已发送，看看通知栏有没有出现'
            : '发送失败：${NotificationService.instance.lastError ?? '未知'}'),
      ),
    );
  }

  /// 排障用：10 秒后排一条提醒，验证定时排程能不能触发。
  Future<void> _testSchedule() async {
    final result = await NotificationService.instance.scheduleTestAfter(10);
    await _refreshNotificationState();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(result)),
    );
  }

  Future<void> _refreshWidget() async {
    final ok = await ref.read(widgetDataServiceProvider).refresh();
    await _refreshWidgetDiagnostics();
    if (!mounted) return;
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(ok ? '已刷新小组件数据' : '刷新失败（平台不支持或未添加小组件）')),
    );
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

  /// 请求把小组件钉到桌面（Android 8.0 / API 26+ 才支持）。
  /// 不支持的机型退化为「长按桌面手动添加」的提示。
  Future<void> _pinWidget() async {
    final supported = await HomeWidget.isRequestPinWidgetSupported() ?? false;
    if (!mounted) return;
    if (!supported) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('当前系统不支持一键添加，请长按桌面空白处手动添加'),
        ),
      );
      return;
    }
    await HomeWidget.requestPinWidget(name: 'TabbyWidget');
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
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.alarm, size: 20),
                            const SizedBox(width: 10),
                            Text('提醒怎么响', style: theme.textTheme.titleSmall),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '通知只会「叮」一声就结束，要真正把人叫醒得用下面两种方式之一。'
                          '切到「App 闹钟响铃」后，通知会停发，改由 App 自己的响铃页面负责。',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 4),
                        RadioGroup<ReminderDelivery>(
                          groupValue: _delivery,
                          onChanged: (v) async {
                            if (v == null) return;
                            setState(() => _delivery = v);
                            await AlarmService.instance.saveMode(v);
                            await _reschedule();
                          },
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              for (final mode in ReminderDelivery.values)
                                RadioListTile<ReminderDelivery>(
                                  value: mode,
                                  dense: true,
                                  title: Text(mode.label),
                                  subtitle: Text(
                                    mode.description,
                                    style: theme.textTheme.bodySmall,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text('响铃方式', style: theme.textTheme.titleSmall),
                        const SizedBox(height: 6),
                        _chipRow(
                          '每次响',
                          AlarmRingProfile.ringOptions,
                          _ring.ringMinutes,
                          (v) => _updateRing(_ring.copyWith(ringMinutes: v)),
                          (v) => '$v 分钟',
                        ),
                        if (!_ring.onceOnly) ...[
                          const SizedBox(height: 4),
                          _chipRow(
                            '隔多久再响',
                            AlarmRingProfile.snoozeOptions,
                            _ring.snoozeMinutes,
                            (v) => _updateRing(_ring.copyWith(snoozeMinutes: v)),
                            (v) => '$v 分钟',
                          ),
                        ],
                        const SizedBox(height: 4),
                        _chipRow(
                          '最多响几次',
                          const [
                            1,
                            3,
                            5,
                            AlarmRingProfile.repeatUntilDismissed,
                          ],
                          _ring.repeatTimes,
                          (v) => _updateRing(_ring.copyWith(repeatTimes: v)),
                          (v) => v == AlarmRingProfile.repeatUntilDismissed
                              ? '直到关闭'
                              : '$v 次',
                        ),
                        const SizedBox(height: 6),
                        Text(
                          _ring.summary,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          '小米 / Redmi 还需要在「应用信息 → 其他权限」里打开'
                          '「后台弹出界面」和「锁屏显示」，并在「省电策略」选「无限制」；'
                          '否则系统只允许 App 在前台时弹出响铃页'
                          '（但铃声仍会响，通知栏也能看到「正在响铃」）。',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            OutlinedButton.icon(
                              onPressed: _testAlarmScreen,
                              icon: const Icon(Icons.ring_volume_outlined,
                                  size: 18),
                              label: const Text('10 秒后响铃测试'),
                            ),
                            OutlinedButton.icon(
                              onPressed: _testSystemAlarm,
                              icon: const Icon(Icons.alarm_add_outlined,
                                  size: 18),
                              label: const Text('打开系统闹钟界面'),
                            ),
                            OutlinedButton.icon(
                              onPressed: () =>
                                  AlarmService.instance.stopRinging(),
                              icon: const Icon(Icons.alarm_off_outlined,
                                  size: 18),
                              label: const Text('停止响铃'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '已排定的闹钟：$_alarmsPending 条'
                          '（切到「系统时钟闹钟」时这里会是 0，'
                          '因为那些闹钟由系统时钟管）',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
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
                  if (NotificationService.instance.isDegraded)
                    Container(
                      width: double.infinity,
                      margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.errorContainer,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.report_outlined,
                                  size: 18, color: theme.colorScheme.error),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  '提醒已降级：系统没授予「闹钟与提醒」',
                                  style: TextStyle(
                                    color: theme.colorScheme.error,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            '提醒仍然会响，但系统可能把它延后几分钟。'
                            '要点开上面的「去授予」在系统里允许；'
                            '小米 / Redmi 还需要在「应用设置 → 自启动 + 电池无限制」里放行。',
                          ),
                        ],
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
                        Text('闹钟排障', style: theme.textTheme.labelLarge),
                        const SizedBox(height: 4),
                        Text(
                          '先点「发测试通知」：通知栏不出现＝通知权限或渠道被系统拦了。'
                          '出现了再点「10 秒后测试」：不响＝定时排程被系统拦了。'
                          '当前实际排程模式：${NotificationService.instance.scheduleModeUsed?.name ?? '还没排过'}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            OutlinedButton.icon(
                              onPressed: _testNotification,
                              icon: const Icon(Icons.send_outlined, size: 18),
                              label: const Text('发测试通知'),
                            ),
                            OutlinedButton.icon(
                              onPressed: _testSchedule,
                              icon: const Icon(Icons.timer_outlined, size: 18),
                              label: const Text('10 秒后测试'),
                            ),
                          ],
                        ),
                        if (NotificationService.instance.lastError != null) ...[
                          const SizedBox(height: 8),
                          Text(
                            '最近一次错误：${NotificationService.instance.lastError}',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.error,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('响铃设置', style: theme.textTheme.labelLarge),
                        const SizedBox(height: 4),
                        Text(
                          '通知能弹出来但不响铃，是因为系统把本应用的通知降级了。'
                          'Android 的通知渠道声音一旦创建就锁死，必须在系统设置里放行；'
                          '小米 / Redmi 常见于「静默通知」。'
                          '请依次打开下面两项，把「铃声 / 悬浮通知 / 锁屏通知」都打开。',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            OutlinedButton.icon(
                              onPressed: () => SystemSettings
                                  .openChannelSettings(
                                NotificationService.channelId,
                              ),
                              icon: const Icon(Icons.volume_up_outlined,
                                  size: 18),
                              label: const Text('打开通知铃声设置'),
                            ),
                            OutlinedButton.icon(
                              onPressed: SystemSettings
                                  .openNotificationSettings,
                              icon: const Icon(Icons.settings_outlined,
                                  size: 18),
                              label: const Text('应用通知设置'),
                            ),
                            OutlinedButton.icon(
                              onPressed:
                                  SystemSettings.openAlarmAndRemindersSettings,
                              icon: const Icon(Icons.alarm_outlined, size: 18),
                              label: const Text('闹钟与提醒授权'),
                            ),
                            OutlinedButton.icon(
                              onPressed: SystemSettings.openAppDetails,
                              icon: const Icon(Icons.shield_outlined,
                                  size: 18),
                              label: const Text('自启动 / 电池'),
                            ),
                          ],
                        ),
                      ],
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
            Text('桌面小组件', style: theme.textTheme.titleSmall),
            const SizedBox(height: 4),
            Card(
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.widgets_outlined),
                    title: const Text('把「今天 / 明天备忘」放到桌面'),
                    subtitle: const Text(
                      '添加后显示今天和明天的备忘；备忘一改动会自动刷新',
                    ),
                    trailing: TextButton(
                      onPressed: _pinWidget,
                      child: const Text('添加到桌面'),
                    ),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.analytics_outlined, size: 20),
                    title: const Text('排障信息'),
                    subtitle: Text(
                      '系统里已添加 ${_installedWidgets < 0 ? '未知' : '$_installedWidgets'} 个'
                      ' · 数据快照：$_widgetDataSummary',
                    ),
                    trailing: TextButton(
                      onPressed: _refreshWidget,
                      child: const Text('刷新数据'),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    child: Text(
                      '如果「已添加 0 个」：小组件还没放到桌面 —— 请长按桌面空白处，'
                      '选「添加小部件 / 小工具」，在列表里找到 Tabby 拖上去。'
                      '如果出现「已添加 1 个」但桌面还是空的，'
                      '多为小米后台限制：给本 App 开「自启动」和「电池无限制」后重启再试。',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
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
