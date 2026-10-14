/// 提醒「怎么响」。
///
/// - notification：只发系统通知（叮一声就结束，声音由通知渠道决定）
/// - appAlarm：到点弹出 App 自带的响铃页面，循环播放闹钟铃声 + 震动，直到手动关闭
/// - systemClock：交给系统自带的「时钟」App 去响（能按周重复，但每条都要在系统
///   弹窗里手动确认一次，且之后 App 无法自动修改/删除这些闹钟）
enum ReminderDelivery { notification, appAlarm, systemClock }

extension ReminderDeliveryX on ReminderDelivery {
  String get key => switch (this) {
        ReminderDelivery.notification => 'notification',
        ReminderDelivery.appAlarm => 'appAlarm',
        ReminderDelivery.systemClock => 'systemClock',
      };

  String get label => switch (this) {
        ReminderDelivery.notification => '系统通知',
        ReminderDelivery.appAlarm => 'App 闹钟响铃',
        ReminderDelivery.systemClock => '系统时钟闹钟',
      };

  String get description => switch (this) {
        ReminderDelivery.notification =>
          '到点发一条通知。最省电，但只会「叮」一声，声音长度由系统通知决定。',
        ReminderDelivery.appAlarm =>
          '到点弹出全屏响铃页面（锁屏也能显示），播放系统闹钟铃声并震动。'
              '响多久、要不要隔几分钟再响一次，都可以在下面的「响铃方式」里调。',
        ReminderDelivery.systemClock =>
          '把提醒交给手机自带的「时钟」App 去响，支持每周重复，适合固定课表。'
              '注意：每设一条都要在系统弹窗里点一次确认，App 之后无法自动改或删。',
      };

  static ReminderDelivery fromKey(String? key) => switch (key) {
        'appAlarm' => ReminderDelivery.appAlarm,
        'systemClock' => ReminderDelivery.systemClock,
        _ => ReminderDelivery.notification,
      };
}

/// App 闹钟「怎么响」的配置。
///
/// 存在原生侧（SharedPreferences）而不是 Dart 内存里：闹钟到点时 App 通常没在运行，
/// 响铃服务必须自己知道该响多久、隔多久再来一次、一共几次。
class AlarmRingProfile {
  /// repeatTimes 取这个值表示一直重复，直到手动关闭。
  static const int repeatUntilDismissed = 0;

  static const List<int> ringOptions = [1, 2, 3, 5, 10];
  static const List<int> snoozeOptions = [3, 5, 10, 15];

  /// 每次响多久（分钟）。
  final int ringMinutes;

  /// 两轮之间隔多久（分钟）。
  final int snoozeMinutes;

  /// 一共响几次；[repeatUntilDismissed] 表示一直响到手动关闭。
  final int repeatTimes;

  const AlarmRingProfile({
    this.ringMinutes = 1,
    this.snoozeMinutes = 5,
    this.repeatTimes = 3,
  });

  bool get onceOnly => repeatTimes <= 1;

  String get summary => switch (repeatTimes) {
        repeatUntilDismissed =>
          '每次响 $ringMinutes 分钟，隔 $snoozeMinutes 分钟再响，直到手动关闭',
        1 => '只响一次，$ringMinutes 分钟后自动停',
        _ =>
          '每次响 $ringMinutes 分钟，隔 $snoozeMinutes 分钟再响，最多 $repeatTimes 次',
      };

  AlarmRingProfile copyWith({
    int? ringMinutes,
    int? snoozeMinutes,
    int? repeatTimes,
  }) =>
      AlarmRingProfile(
        ringMinutes: ringMinutes ?? this.ringMinutes,
        snoozeMinutes: snoozeMinutes ?? this.snoozeMinutes,
        repeatTimes: repeatTimes ?? this.repeatTimes,
      );

  factory AlarmRingProfile.fromMap(Map<dynamic, dynamic>? raw) {
    if (raw == null) return const AlarmRingProfile();
    int pick(Object? v, int fallback) => switch (v) {
          final int n => n,
          final num n => n.toInt(),
          _ => fallback,
        };
    final repeat = pick(raw['repeatTimes'], 3);
    return AlarmRingProfile(
      ringMinutes: pick(raw['ringMinutes'], 1).clamp(1, 60).toInt(),
      snoozeMinutes: pick(raw['snoozeMinutes'], 5).clamp(1, 120).toInt(),
      repeatTimes: repeat < 0 ? 0 : repeat,
    );
  }

  Map<String, int> toMap() => {
        'ringMinutes': ringMinutes,
        'snoozeMinutes': snoozeMinutes,
        'repeatTimes': repeatTimes,
      };
}
