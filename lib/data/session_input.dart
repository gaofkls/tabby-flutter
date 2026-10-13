/// 一个上课时段的输入结构（课程表单和导入解析都用它）。
class SessionInput {
  const SessionInput({
    required this.weekday,
    required this.startMinute,
    required this.endMinute,
    this.weeks = '*',
  });

  final int weekday; // 1=周一 … 7=周日
  final int startMinute;
  final int endMinute;
  final String weeks;

  SessionInput copyWith({
    int? weekday,
    int? startMinute,
    int? endMinute,
    String? weeks,
  }) =>
      SessionInput(
        weekday: weekday ?? this.weekday,
        startMinute: startMinute ?? this.startMinute,
        endMinute: endMinute ?? this.endMinute,
        weeks: weeks ?? this.weeks,
      );
}
