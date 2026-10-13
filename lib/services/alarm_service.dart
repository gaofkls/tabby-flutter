import 'package:flutter/services.dart';

import '../data/alarm_mode.dart';
import 'notification_service.dart';

/// 跟原生闹钟层打交道的入口（仅 Android 有效，其它平台全部降级为通知）。
///
/// 两块能力：
/// 1. App 自带闹钟 —— 用系统 AlarmManager 的 setAlarmClock 排程，
///    到点拉起全屏响铃页面（铃声 + 震动，直到手动关闭）。
/// 2. 系统时钟闹钟 —— 打开系统「设置闹钟」界面，交给手机自带的时钟去响。
class AlarmService {
  AlarmService._();

  static final AlarmService instance = AlarmService._();

  static const MethodChannel _channel = MethodChannel('tabby/alarm');

  bool _supported = false;
  bool _checked = false;

  /// 当前平台是否支持原生闹钟（Android）。
  Future<bool> isSupported() async {
    if (_checked) return _supported;
    try {
      await _channel.invokeMethod<String>('getMode');
      _supported = true;
    } on MissingPluginException {
      _supported = false;
    } on PlatformException {
      _supported = false;
    }
    _checked = true;
    return _supported;
  }

  Future<ReminderDelivery> loadMode() async {
    try {
      final raw = await _channel.invokeMethod<String>('getMode');
      return ReminderDeliveryX.fromKey(raw);
    } catch (_) {
      return ReminderDelivery.notification;
    }
  }

  Future<void> saveMode(ReminderDelivery mode) async {
    try {
      await _channel
          .invokeMethod<void>('setMode', <String, Object?>{'mode': mode.key});
    } catch (_) {
      // 平台不支持就当没设置过
    }
  }

  /// 用一批任务整体替换系统闹钟。返回实际排了几条。
  Future<int> scheduleAll(List<ReminderTask> tasks) async {
    try {
      final alarms = <Map<String, Object?>>[
        for (var i = 0; i < tasks.length; i++)
          {
            'id': i + 1,
            'at': tasks[i].scheduledAt.millisecondsSinceEpoch,
            'title': tasks[i].title,
            'body': tasks[i].body,
          },
      ];
      final count = await _channel.invokeMethod<int>(
        'scheduleAll',
        <String, Object?>{'alarms': alarms},
      );
      return count ?? 0;
    } catch (_) {
      return 0;
    }
  }

  Future<void> cancelAll() async {
    try {
      await _channel.invokeMethod<void>('cancelAll');
    } catch (_) {
      // 平台不支持，忽略
    }
  }

  Future<int> pendingCount() async {
    try {
      return await _channel.invokeMethod<int>('pendingCount') ?? 0;
    } catch (_) {
      return 0;
    }
  }

  /// 打开系统「设置闹钟」界面，让用户把这条提醒交给系统时钟。
  ///
  /// [days] 传 null 表示单次；传 1..7 表示每周哪几天重复
  /// （用 Calendar 的编码：周日=1，周一=2 … 周六=7）。
  /// 返回是否成功打开。
  Future<bool> openSystemAlarm({
    required int hour,
    required int minute,
    required String message,
    List<int>? days,
  }) async {
    try {
      final ok = await _channel.invokeMethod<bool>(
        'openSystemAlarm',
        <String, Object?>{
          'hour': hour,
          'minute': minute,
          'message': message,
          'days': days,
        },
      );
      return ok ?? false;
    } catch (_) {
      return false;
    }
  }

  /// 星期几 → Calendar 编码（周一=2 … 周日=1）。
  static int calendarDay(int weekday) => weekday == 7 ? 1 : weekday + 1;
}
