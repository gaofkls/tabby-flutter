import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;

/// 一条要交给系统的定时提醒。
class ReminderTask {
  const ReminderTask({
    required this.title,
    required this.body,
    required this.scheduledAt,
    this.payload,
  });

  final String title;
  final String body;
  final DateTime scheduledAt;
  final String? payload;
}

/// 系统通知的封装。只在 macOS / Android / iOS 上真的发通知，
/// 其余平台（比如跑单测时）调用会直接跳过。
class NotificationService {
  NotificationService._();

  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;
  bool? _permissionGranted;
  bool? _exactAlarmGranted;
  AndroidScheduleMode? _scheduleMode;
  String? _lastError;

  bool get isInitialized => _initialized;

  /// null 表示还没请求过 / 平台不支持
  bool? get permissionGranted => _permissionGranted;

  /// 精确闹钟权限（Android 12+ 的 SCHEDULE_EXACT_ALARM）。
  /// null 表示平台不支持 / 还没查过。
  bool? get exactAlarmGranted => _exactAlarmGranted;

  /// 最近一次排程实际用上的模式。null 表示还没排过。
  AndroidScheduleMode? get scheduleModeUsed => _scheduleMode;

  /// 是否因为缺少「闹钟和提醒」权限而降级成了不精确的提醒。
  /// 降级后提醒仍会响，但可能被系统延后几分钟。
  bool get isDegraded =>
      _scheduleMode == AndroidScheduleMode.inexactAllowWhileIdle ||
      _scheduleMode == AndroidScheduleMode.inexact;

  String? get lastError => _lastError;

  /// 排障用通知的 id，避开正式提醒占用的 1..N。
  static const int _testNowId = 900001;
  static const int _testScheduleId = 900002;

  static const AndroidNotificationDetails _androidDetails =
      AndroidNotificationDetails(
    'tabby_reminders',
    '课程与备忘提醒',
    channelDescription: '上课和备忘到点前提醒',
    importance: Importance.max,
    priority: Priority.high,
  );

  static const NotificationDetails _details = NotificationDetails(
    android: _androidDetails,
    iOS: DarwinNotificationDetails(),
    macOS: DarwinNotificationDetails(),
  );

  Future<void> init() async {
    if (_initialized) return;
    try {
      await _plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
          iOS: DarwinInitializationSettings(),
          macOS: DarwinInitializationSettings(),
        ),
      );
      _initialized = true;
      await requestPermission();
    } catch (e) {
      // 平台不支持（比如 Linux / 单测环境）时不影响 app 其它功能
      _lastError = '$e';
      _initialized = false;
    }
  }

  Future<bool?> requestPermission() async {
    if (!_initialized) return null;
    try {
      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      final granted = await android?.requestNotificationsPermission();

      await _plugin
          .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin>()
          ?.requestPermissions(alert: true, badge: true, sound: true);
      await _plugin
          .resolvePlatformSpecificImplementation<
              MacOSFlutterLocalNotificationsPlugin>()
          ?.requestPermissions(alert: true, badge: true, sound: true);

      final iosMac = await _plugin
          .resolvePlatformSpecificImplementation<
              MacOSFlutterLocalNotificationsPlugin>()
          ?.checkPermissions();
      _permissionGranted = granted ?? (iosMac?.isEnabled ?? true);
      return _permissionGranted;
    } catch (e) {
      _lastError = '$e';
      return null;
    }
  }

  /// 请求「精确闹钟」权限。Android 12+ 上授予后 zonedSchedule 才能用精确模式；
  /// 没授予时我们会自动退回 alarmClock 模式（同样可靠，且不依赖该权限）。
  /// 该方法会跳转到系统设置页让用户开启，因此只在用户主动点「去授予」时调用，
  /// 不在启动时自动弹，避免首启就跳系统界面。
  Future<bool?> requestExactAlarmsPermission() async {
    if (!_initialized) return null;
    try {
      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      final granted = await android?.requestExactAlarmsPermission();
      _exactAlarmGranted = granted;
      return granted;
    } catch (e) {
      _lastError = '$e';
      return null;
    }
  }

  /// 排程模式从优到劣的候选。
  ///
  /// Android 12+ 没授予「闹钟和提醒」（SCHEDULE_EXACT_ALARM）时，
  /// 插件原生侧对 exact 和 alarmClock 两种模式都会抛
  /// ExactAlarmPermissionException，于是整批提醒一条都排不上——
  /// 表现就是「设了提醒但闹钟不响」。所以这里按候选顺序探测，
  /// 最差也要落到不精确模式（不要求该权限），保证提醒真的会来。
  static const List<AndroidScheduleMode> _scheduleModeCandidates = [
    AndroidScheduleMode.exactAllowWhileIdle,
    AndroidScheduleMode.alarmClock,
    AndroidScheduleMode.inexactAllowWhileIdle,
  ];

  /// 用一批提醒任务整体替换系统里已排的通知。
  /// 先清空再排，因为课程改了以后旧的定时就没意义了。
  Future<int> applyPlan(List<ReminderTask> tasks) async {
    if (!_initialized) return 0;
    try {
      await _plugin.cancelAll();
      _scheduleMode = null;
      if (tasks.isEmpty) {
        _lastError = null;
        return 0;
      }

      // 用第一条探测当前设备能用哪种模式，之后整批复用。
      AndroidScheduleMode? mode;
      for (final candidate in _scheduleModeCandidates) {
        try {
          await _scheduleOne(1, tasks.first, candidate);
          mode = candidate;
          break;
        } catch (e) {
          _lastError = '$e';
        }
      }
      if (mode == null) {
        _exactAlarmGranted = false;
        return 0;
      }

      _scheduleMode = mode;
      _exactAlarmGranted =
          mode == AndroidScheduleMode.exactAllowWhileIdle ||
          mode == AndroidScheduleMode.alarmClock;

      var count = 1;
      for (var i = 1; i < tasks.length; i++) {
        try {
          await _scheduleOne(i + 1, tasks[i], mode);
          count++;
        } catch (_) {
          // 单条失败不该拖垮整批提醒
        }
      }
      _lastError = null;
      return count;
    } catch (e) {
      _lastError = '$e';
      return 0;
    }
  }

  Future<void> _scheduleOne(
    int id,
    ReminderTask task,
    AndroidScheduleMode mode,
  ) {
    // 插件原生侧拿的是「墙上时钟 + 时区名」，再把它们合成瞬时。
    // 用 UTC 承载本地 DateTime：瞬时不变，墙上时钟会被换算成 UTC 表示，
    // 原生用 ZoneId=UTC 反解回来正好是同一个瞬时，因此不需要 tz 数据库。
    return _plugin.zonedSchedule(
      id: id,
      title: task.title,
      body: task.body,
      scheduledDate: tz.TZDateTime.from(task.scheduledAt, tz.UTC),
      notificationDetails: _details,
      androidScheduleMode: mode,
      payload: task.payload,
    );
  }

  /// 排障用：立刻发一条通知。
  /// 用来验证「系统通知通道」本身通不通（权限 + 渠道）。
  Future<bool> showNow() async {
    if (!_initialized) return false;
    try {
      await _plugin.show(
        id: _testNowId,
        title: 'Tabby 测试通知',
        body: '看到这条说明通知权限和渠道都正常',
        notificationDetails: _details,
      );
      return true;
    } catch (e) {
      _lastError = '$e';
      return false;
    }
  }

  /// 排障用：[seconds] 秒后排一条提醒。
  /// 用来验证「定时排程」到底会不会触发。返回给人看的结论（含实际用上的模式）。
  Future<String> scheduleTestAfter(int seconds) async {
    if (!_initialized) return '通知还没初始化';
    final at = DateTime.now().add(Duration(seconds: seconds));
    for (final candidate in _scheduleModeCandidates) {
      try {
        await _scheduleOne(
          _testScheduleId,
          ReminderTask(
            title: 'Tabby 定时测试',
            body: '排程正常的话，这条会在设定时间出现',
            scheduledAt: at,
          ),
          candidate,
        );
        return '已用 ${candidate.name} 排好，$seconds 秒后应该会响';
      } catch (e) {
        _lastError = '$e';
      }
    }
    return '三种模式都排不上：$_lastError';
  }

  Future<int> pendingCount() async {
    if (!_initialized) return 0;
    try {
      final pending = await _plugin.pendingNotificationRequests();
      return pending.length;
    } catch (e) {
      return 0;
    }
  }

  Future<void> cancelAll() async {
    if (!_initialized) return;
    try {
      await _plugin.cancelAll();
    } catch (e) {
      _lastError = '$e';
    }
  }
}
