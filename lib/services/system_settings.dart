import 'package:flutter/services.dart';

/// 跳到系统设置页的入口。
///
/// 小米 / Redmi（MIUI / HyperOS）会把第三方 App 的通知默认降级成静默通知，
/// 代码里怎么配渠道都改不动系统侧的开关，只能让用户在系统设置里放行：
/// 通知管理 → Tabby → 通知类别 → 打开「铃声 / 悬浮通知 / 锁屏」。
/// 这里提供直接跳过去的按钮，省得用户自己找。
class SystemSettings {
  SystemSettings._();

  static const MethodChannel _channel =
      MethodChannel('tabby/system_settings');

  /// 本应用的通知总开关页。
  static Future<void> openNotificationSettings() =>
      _invoke('openNotificationSettings');

  /// 某个通知渠道的设置页（Android 8+）。绝大多数 ROM 的铃声开关在这一层。
  static Future<void> openChannelSettings(String channelId) =>
      _invoke('openChannelSettings', <String, Object?>{'channelId': channelId});

  /// 「闹钟与提醒」授权页（Android 12+）。授予后定时提醒才能精确触发。
  static Future<void> openAlarmAndRemindersSettings() =>
      _invoke('openAlarmSettings');

  /// 本应用的应用信息页。自启动、电池无限制这些厂商设置在里面。
  static Future<void> openAppDetails() => _invoke('openAppDetails');

  static Future<void> _invoke(String method, [Map<String, Object?>? args]) async {
    try {
      await _channel.invokeMethod<void>(method, args);
    } on MissingPluginException {
      // 非 Android / 原生侧没注册，忽略
    } on PlatformException {
      // 系统没有对应的设置页，忽略
    }
  }
}
