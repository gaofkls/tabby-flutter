/// 桌面小组件显示什么内容。
///
/// - memo：只显示备忘
/// - course：只显示课表（当天 / 明天，按时间排序）
/// - all：备忘和课程混在一起，统一按时间排序
enum WidgetDisplayMode { memo, course, all }

extension WidgetDisplayModeX on WidgetDisplayMode {
  String get key => switch (this) {
        WidgetDisplayMode.memo => 'memo',
        WidgetDisplayMode.course => 'course',
        WidgetDisplayMode.all => 'all',
      };

  String get label => switch (this) {
        WidgetDisplayMode.memo => '备忘',
        WidgetDisplayMode.course => '课表',
        WidgetDisplayMode.all => '备忘 + 课表',
      };

  String get description => switch (this) {
        WidgetDisplayMode.memo => '只显示今天和明天的备忘',
        WidgetDisplayMode.course => '只显示今天和明天的课，按时间先后排列',
        WidgetDisplayMode.all => '备忘和课混在一起，统一按时间先后排列',
      };

  static WidgetDisplayMode fromKey(String? key) => switch (key) {
        'memo' => WidgetDisplayMode.memo,
        'course' => WidgetDisplayMode.course,
        _ => WidgetDisplayMode.all,
      };
}
