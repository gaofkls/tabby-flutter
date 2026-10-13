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
  String? _lastError;

  bool get isInitialized => _initialized;

  /// null 表示还没请求过 / 平台不支持
  bool? get permissionGranted => _permissionGranted;

  String? get lastError => _lastError;

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

  /// 用一批提醒任务整体替换系统里已排的通知。
  /// 先清空再排，因为课程改了以后旧的定时就没意义了。
  Future<int> applyPlan(List<ReminderTask> tasks) async {
    if (!_initialized) return 0;
    try {
      await _plugin.cancelAll();
      var count = 0;
      for (var i = 0; i < tasks.length; i++) {
        final task = tasks[i];
        final scheduled =
            tz.TZDateTime.from(task.scheduledAt, tz.UTC);
        await _plugin.zonedSchedule(
          id: i + 1,
          title: task.title,
          body: task.body,
          scheduledDate: scheduled,
          notificationDetails: _details,
          androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
          payload: task.payload,
        );
        count++;
      }
      _lastError = null;
      return count;
    } catch (e) {
      _lastError = '$e';
      return 0;
    }
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
