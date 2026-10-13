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
          '到点弹出全屏响铃页面（锁屏也能显示），循环播放系统闹钟铃声并震动，'
              '直到你点「关闭」或「稍后」。',
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
