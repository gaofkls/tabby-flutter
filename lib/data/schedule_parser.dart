import 'course_repository.dart';

/// 把教务系统里复制出来的课表文本，解析成结构化的上课安排。
///
/// 设计原则：尽量宽容。先把一行里的「星期 / 时间 / 周次 / 教师 / 教室」
/// 这些有明确样式的片段挑走，剩下的那个中文词就是课程名。
/// 解析不出来的整行会原样进 skipped，让用户在预览里自己看，
/// 不会悄悄丢数据。
class ScheduleParser {
  ScheduleParser._();

  /// 默认节次时间表（第 1 节 … 第 12 节），各校不同，够用即可。
  static const periods = <(int, int)>[
    (8 * 60, 8 * 60 + 45),
    (8 * 60 + 55, 9 * 60 + 40),
    (10 * 60, 10 * 60 + 45),
    (10 * 60 + 55, 11 * 60 + 40),
    (14 * 60, 14 * 60 + 45),
    (14 * 60 + 55, 15 * 60 + 40),
    (16 * 60, 16 * 60 + 45),
    (16 * 60 + 55, 17 * 60 + 40),
    (19 * 60, 19 * 60 + 45),
    (19 * 60 + 55, 20 * 60 + 40),
    (20 * 60 + 50, 21 * 60 + 35),
    (21 * 60 + 45, 22 * 60 + 30),
  ];

  static final _weekdayRe =
      RegExp(r'(?:星期|周)\s*([一二三四五六日天1-7１-７])');
  static final _timeRe = RegExp(
      r'(\d{1,2})\s*[:：]\s*(\d{2})\s*[-–—~至到]\s*(\d{1,2})\s*[:：]\s*(\d{2})');
  static final _periodRe =
      RegExp(r'(?:第)?\s*(\d{1,2})\s*[-–—~至]\s*(\d{1,2})\s*节');
  // 前面紧跟数字或连字符时不要匹配，否则「第1-2节」会被拆成「2节」
  static final _singlePeriodRe =
      RegExp(r'(?<![\d\-–—~至])(?:第)?\s*(\d{1,2})\s*节');
  static final _weekRangeRe =
      RegExp(r'(\d{1,2})\s*[-–—~]\s*(\d{1,2})\s*周');
  static final _weekListRe =
      RegExp(r'(\d{1,2}(?:\s*[,，、]\s*\d{1,2})+)\s*周');
  // 同理，避免把「1-16周」拆成「16周」
  static final _singleWeekRe =
      RegExp(r'(?<![\d\-–—~至,，、])(?:第)?\s*(\d{1,2})\s*周');
  static final _teacherRe = RegExp(r'([\u4e00-\u9fa5]{1,6}老师)');
  static final _locationRe = RegExp(
      r'^[\u4e00-\u9fa5]{0,4}(?:教|楼|室|馆|场|中心|区)[\u4e00-\u9fa5A-Za-z0-9\-—]{0,8}$');
  static final _roomCodeRe = RegExp(r'^[A-Za-z]{0,3}-?\d{3,4}$');
  static final _chineseRe = RegExp(r'[\u4e00-\u9fa5]');

  static const _noiseWords = {
    '课程', '课程名', '节次', '时间', '地点', '教师', '教室', '上课',
    '备注', '上午', '下午', '晚上', '序号', '学分', '周次', '星期',
  };

  static ImportResult parse(String text) {
    final entries = <ImportEntry>[];
    final skipped = <String>[];

    for (final rawLine in text.split('\n')) {
      final line = rawLine.trim();
      if (line.isEmpty) continue;

      final entry = _parseLine(line);
      if (entry == null) {
        skipped.add(line);
      } else {
        entries.add(entry);
      }
    }

    return ImportResult(entries: entries, skipped: skipped);
  }

  static ImportEntry? _parseLine(String line) {
    var work = line
        .replaceAll('（', ' ( ')
        .replaceAll('）', ' ) ')
        .replaceAll('(', ' ( ')
        .replaceAll(')', ' ) ')
        .replaceAll(RegExp(r'[，、；;]'), ' ');

    // 给有明确样式的片段两侧加空格，后面按空格切词
    work = _isolate(work, _weekdayRe);
    work = _isolate(work, _timeRe);
    work = _isolate(work, _weekRangeRe);
    work = _isolate(work, _weekListRe);
    work = _isolate(work, _singleWeekRe);
    work = _isolate(work, _periodRe);
    work = _isolate(work, _singlePeriodRe);
    work = _isolate(work, _teacherRe);

    int? weekday;
    int? startMinute;
    int? endMinute;
    String weeks = '*';
    String? teacher;
    String? location;
    final nameCandidates = <String>[];
    final warnings = <String>[];

    for (final token in work.split(RegExp(r'\s+')).where((t) => t.isNotEmpty)) {
      if (token == '(' || token == ')') continue;

      final wd = _weekdayRe.firstMatch(token);
      if (wd != null) {
        weekday = _weekdayFrom(wd.group(1)!);
        continue;
      }

      final time = _timeRe.firstMatch(token);
      if (time != null) {
        startMinute = int.parse(time.group(1)!) * 60 + int.parse(time.group(2)!);
        endMinute = int.parse(time.group(3)!) * 60 + int.parse(time.group(4)!);
        continue;
      }

      final weekRange = _weekRangeRe.firstMatch(token);
      if (weekRange != null) {
        weeks = '${weekRange.group(1)}-${weekRange.group(2)}';
        continue;
      }
      final weekList = _weekListRe.firstMatch(token);
      if (weekList != null) {
        weeks = weekList.group(1)!.replaceAll(RegExp(r'[\s，、]'), ',');
        continue;
      }
      if (token == '单周') {
        weeks = '单';
        continue;
      }
      if (token == '双周') {
        weeks = '双';
        continue;
      }
      final singleWeek = _singleWeekRe.firstMatch(token);
      if (singleWeek != null) {
        weeks = singleWeek.group(1)!;
        continue;
      }

      final teacherMatch = _teacherRe.firstMatch(token);
      if (teacherMatch != null) {
        teacher = teacherMatch.group(1)!;
        continue;
      }

      if (startMinute == null) {
        final period = _periodRe.firstMatch(token);
        if (period != null) {
          final from = int.tryParse(period.group(1)!);
          final to = int.tryParse(period.group(2)!);
          if (from != null && to != null && _periodTime(from) != null) {
            startMinute = _periodTime(from)!.$1;
            endMinute = _periodTime(to)!.$2;
            continue;
          }
        }
        final singlePeriod = _singlePeriodRe.firstMatch(token);
        if (singlePeriod != null) {
          final p = int.tryParse(singlePeriod.group(1)!);
          if (p != null && _periodTime(p) != null) {
            startMinute = _periodTime(p)!.$1;
            endMinute = _periodTime(p)!.$2;
            continue;
          }
        }
      }

      if (_locationRe.hasMatch(token) || _roomCodeRe.hasMatch(token)) {
        location ??= token;
        continue;
      }

      if (_noiseWords.contains(token)) continue;
      if (!_chineseRe.hasMatch(token)) continue;
      nameCandidates.add(token);
    }

    // 课程名取候选里最长的那个（"高等数学" 会比 "数学" 更长更完整）
    String? name;
    if (nameCandidates.isNotEmpty) {
      nameCandidates.sort((a, b) => b.length.compareTo(a.length));
      name = nameCandidates.first;
    }

    if (weekday == null || startMinute == null || name == null) {
      return null;
    }
    if (endMinute == null || endMinute <= startMinute) {
      endMinute = startMinute + 90;
      warnings.add('结束时间没认出来，默认按 90 分钟');
    }
    if (location == null) warnings.add('没认出教室');

    return ImportEntry(
      name: name,
      weekday: weekday,
      startMinute: startMinute,
      endMinute: endMinute,
      teacher: teacher,
      location: location,
      weeks: weeks,
      raw: line,
      warning: warnings.isEmpty ? null : warnings.join('；'),
    );
  }

  /// 给匹配到的片段两侧加空格，避免「周一第1-2节」这种粘连。
  static String _isolate(String input, RegExp pattern) {
    return input.replaceAllMapped(pattern, (m) => ' ${m.group(0)} ');
  }

  static int? _weekdayFrom(String value) {
    const map = {
      '一': 1, '二': 2, '三': 3, '四': 4, '五': 5, '六': 6, '日': 7, '天': 7,
      '1': 1, '2': 2, '3': 3, '4': 4, '5': 5, '6': 6, '7': 7,
      '１': 1, '２': 2, '３': 3, '４': 4, '５': 5, '６': 6, '７': 7,
    };
    return map[value];
  }

  static (int, int)? _periodTime(int period) {
    if (period < 1 || period > periods.length) return null;
    return periods[period - 1];
  }
}

class ImportResult {
  const ImportResult({
    required this.entries,
    required this.skipped,
    this.termStart,
    this.termWeek,
  });

  final List<ImportEntry> entries;
  final List<String> skipped;

  /// 从课表页反推出来的学期第 1 周的周一（只有 HTML 解析才有）。
  /// 写进学期之后，单双周 / 周次过滤才准。
  final DateTime? termStart;

  /// 课表页显示的是第几教学周。
  final int? termWeek;

  bool get isEmpty => entries.isEmpty && skipped.isEmpty;
}
