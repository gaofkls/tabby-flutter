/// 提醒规则。
///
/// 三种形态：
///   none        —— 不提醒
///   before      —— 事件开始前 N 分钟提醒（N = value）
///   previousDay —— 前一天固定时刻提醒（value = 当天 0 点起的分钟数）
///
/// 存进数据库时写 mode.index + value；两列都是 null 表示「跟随全局默认」。
enum ReminderMode { none, before, previousDay }

/// 一条提醒规则。null（而不是对象）表示跟随全局默认。
class ReminderSpec {
  const ReminderSpec.none() : mode = ReminderMode.none, value = null;

  const ReminderSpec.before(int minutes)
      : mode = ReminderMode.before,
        value = minutes;

  const ReminderSpec.previousDay(int minuteOfDay)
      : mode = ReminderMode.previousDay,
        value = minuteOfDay;

  final ReminderMode mode;
  final int? value;

  /// 应用没改过设置时的默认规则：前一天晚上 21:00。
  static const ReminderSpec defaultValue = ReminderSpec.previousDay(21 * 60);

  /// 常用的「提前多久」档位，界面上直接给按钮。
  static const List<int> beforePresets = [10, 30, 60, 120, 1440];

  /// 数据库里读出来。mode 为 null 表示跟随默认，整条返回 null。
  static ReminderSpec? fromDb(int? mode, int? value) {
    if (mode == null) return null;
    if (mode < 0 || mode >= ReminderMode.values.length) return null;
    final m = ReminderMode.values[mode];
    return switch (m) {
      ReminderMode.none => const ReminderSpec.none(),
      ReminderMode.before => ReminderSpec.before(value ?? 30),
      ReminderMode.previousDay =>
        ReminderSpec.previousDay(value ?? 21 * 60),
    };
  }

  int get dbMode => mode.index;
  int? get dbValue => value;

  bool get isNone => mode == ReminderMode.none;

  /// 人话描述，例如「提前 30 分钟」「前一天 21:00」。
  String get label => switch (mode) {
        ReminderMode.none => '不提醒',
        ReminderMode.before => _beforeLabel(value ?? 30),
        ReminderMode.previousDay =>
          '前一天 ${_minute(value ?? 21 * 60)}',
      };

  static String _beforeLabel(int minutes) {
    if (minutes >= 1440 && minutes % 1440 == 0) {
      return '提前 ${minutes ~/ 1440} 天';
    }
    if (minutes >= 60 && minutes % 60 == 0) {
      return '提前 ${minutes ~/ 60} 小时';
    }
    return '提前 $minutes 分钟';
  }

  /// 算出这条规则在某个事件上的提醒时刻。
  /// [start] 是事件的开始时间（课程是当天上课时间，备忘是 dueDate + dueMinute）。
  DateTime? resolve(DateTime start) {
    return switch (mode) {
      ReminderMode.none => null,
      ReminderMode.before => start.subtract(Duration(minutes: value ?? 30)),
      ReminderMode.previousDay => _dayOf(start)
          .subtract(const Duration(days: 1))
          .add(Duration(minutes: value ?? 21 * 60)),
    };
  }

  static DateTime _dayOf(DateTime d) => DateTime(d.year, d.month, d.day);

  @override
  bool operator ==(Object other) =>
      other is ReminderSpec && other.mode == mode && other.value == value;

  @override
  int get hashCode => Object.hash(mode, value);

  @override
  String toString() => 'ReminderSpec($label)';
}

/// 当天 0 点起的分钟数 → HH:mm
String _minute(int minute) {
  final m = minute % (24 * 60);
  final h = m ~/ 60;
  final mm = m % 60;
  return '${h.toString().padLeft(2, '0')}:${mm.toString().padLeft(2, '0')}';
}

/// 给外部（界面）用的一份分钟格式化，跟提醒文案保持一致。
String formatReminderMinute(int minute) => _minute(minute);
