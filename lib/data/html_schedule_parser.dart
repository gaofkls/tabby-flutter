import 'course_repository.dart';
import 'schedule_parser.dart';

/// 解析教务系统课表**页面源码**（HTML 表格）。
///
/// 比纯文本可靠得多，因为表格里有三样纯文本没有的信息：
///   1. 单元格 class="节次_星期"  —— 直接给出星期几和第几节；
///   2. rowspan                    —— 连堂几节一目了然；
///   3. 表头「星期一…星期日」+ 隐藏字段 —— 星期与列的对应关系不用猜。
///
/// 处理方式：先把 HTML 摊成一张「行 × 列」的网格（正确处理 rowspan/colspan），
/// 再从表头认出星期列、从节次列认出每行的时间，最后合并 rowspan 得到起止时间。
class HtmlScheduleParser {
  HtmlScheduleParser._();

  static final _tableRe =
      RegExp(r'<table[^>]*>(.*?)</table>', dotAll: true, caseSensitive: false);
  static final _trRe =
      RegExp(r'<tr[^>]*>(.*?)</tr>', dotAll: true, caseSensitive: false);
  static final _cellRe =
      RegExp(r'<(td|th)([^>]*)>(.*?)</\1>', dotAll: true, caseSensitive: false);
  static final _boldRe =
      RegExp(r'<b[^>]*>(.*?)</b>', dotAll: true, caseSensitive: false);
  static final _brRe = RegExp(r'<br\s*/?>', caseSensitive: false);
  static final _tagRe = RegExp(r'<[^>]*>');

  static final _timeRangeRe = RegExp(
      r'(\d{1,2})\s*[:：]\s*(\d{2})(?:\s*[:：]\s*\d{2})?'
      r'\s*[-–—~至到]\s*'
      r'(\d{1,2})\s*[:：]\s*(\d{2})(?:\s*[:：]\s*\d{2})?');

  static final _weekdayRe =
      RegExp(r'(?:星期|周)\s*([一二三四五六日天1-7１-７])');
  static final _teacherRe = RegExp(r'【([^】]*)】|\[([^\]]*)\]');
  static final _parenRe = RegExp(r'[（(]([^）()]*)[）)]');
  static final _weeksInGroupRe = RegExp(
      r'第?\s*(\d{1,2}(?:\s*[-–—~]\s*\d{1,2})?'
      r'(?:\s*[,，]\s*\d{1,2}(?:\s*[-–—~]\s*\d{1,2})?)*)\s*周');

  /// 判断这段文本是不是网页源码（而不是一行行的纯文本课表）。
  static bool looksLikeHtml(String source) {
    final s = source.toLowerCase();
    return s.contains('<table') || s.contains('<tr') || s.contains('<td');
  }

  static ImportResult parse(String source) {
    final table = _pickTable(source);
    if (table == null) {
      return const ImportResult(entries: [], skipped: []);
    }

    final rows = _trRe
        .allMatches(table)
        .map((m) => _parseRow(m.group(1)!))
        .where((r) => r.isNotEmpty)
        .toList();
    if (rows.isEmpty) {
      return const ImportResult(entries: [], skipped: []);
    }

    // 摊平成网格：grid[row][col]，同时记下哪些单元格是在这一行「新出现」的
    final grid = <Map<int, _Cell>>[];
    final fresh = <Set<int>>[];
    final pending = <_Pending>[];

    for (final cells in rows) {
      final rowMap = <int, _Cell>{};
      final rowFresh = <int>{};
      for (final p in pending) {
        rowMap[p.col] = p.cell;
        p.remaining -= 1;
      }
      pending.removeWhere((p) => p.remaining <= 0);

      var col = 0;
      for (final cell in cells) {
        while (rowMap.containsKey(col)) {
          col++;
        }
        rowMap[col] = cell;
        rowFresh.add(col);
        for (var k = 1; k < cell.colspan; k++) {
          rowMap[col + k] = cell;
        }
        if (cell.rowspan > 1) {
          pending.add(_Pending(col, cell, cell.rowspan - 1));
        }
        col += cell.colspan;
      }
      grid.add(rowMap);
      fresh.add(rowFresh);
    }

    // 节次列：哪一列的文字里有时间区间
    final timeCol = _detectTimeColumn(grid);
    if (timeCol == null) {
      return const ImportResult(entries: [], skipped: []);
    }

    // 星期列：优先用表头；只复制到 tbody 没有表头时，
    // 退化为「节次列右边连续 7 列 = 周一…周日」。
    var weekdayByCol = _detectWeekdayColumns(grid, rows);
    if (weekdayByCol.isEmpty) {
      weekdayByCol = {for (var i = 0; i < 7; i++) timeCol + 1 + i: i + 1};
    }

    // 每一行的起止时间
    final rowTime = List<(int, int)?>.filled(grid.length, null);
    for (var r = 0; r < grid.length; r++) {
      final cell = grid[r][timeCol];
      if (cell == null) continue;
      rowTime[r] = _parseTimeRange(cell.text);
    }

    final entries = <ImportEntry>[];
    final skipped = <String>[];
    final headerRow = _findHeaderRow(rows);

    for (var r = 0; r < grid.length; r++) {
      if (r == headerRow) continue;
      final start = rowTime[r];
      if (start == null) continue;

      for (final col in fresh[r]) {
        final weekday = weekdayByCol[col];
        if (weekday == null) continue;
        final cell = grid[r][col]!;
        if (cell.text.isEmpty) continue;

        // rowspan 跨了几行，结束时间取最后一行的结束时间
        var endRow = r;
        for (var k = r + 1; k < r + cell.rowspan && k < grid.length; k++) {
          if (rowTime[k] != null) endRow = k;
        }
        final endTime = rowTime[endRow] ?? start;

        final entry = _entryFromCell(
          cell: cell,
          weekday: weekday,
          startMinute: start.$1,
          endMinute: endTime.$2,
        );
        if (entry == null) {
          skipped.add(cell.text.replaceAll('\n', ' / '));
        } else {
          entries.add(entry);
        }
      }
    }

    entries.sort((a, b) {
      final byDay = a.weekday.compareTo(b.weekday);
      if (byDay != 0) return byDay;
      return a.startMinute.compareTo(b.startMinute);
    });

    return ImportResult(
      entries: entries,
      skipped: skipped,
      termStart: _detectTermStart(source),
      termWeek: _detectWeekNumber(source),
    );
  }

  /// 优先挑带「星期」的那个表（课表页往往还有别的表格）。
  /// 只粘到 tbody、没有 <table> 包裹时，整段当表格处理。
  static String? _pickTable(String source) {
    final matches = _tableRe.allMatches(source).toList();
    if (matches.isEmpty) {
      return source.contains('<tr') ? source : null;
    }
    for (final m in matches) {
      final body = m.group(1)!;
      if (body.contains('星期') || body.contains('节') && body.contains('<td')) {
        return body;
      }
    }
    return matches.first.group(1);
  }

  static List<_Cell> _parseRow(String rowHtml) {
    final cells = <_Cell>[];
    for (final m in _cellRe.allMatches(rowHtml)) {
      final attrs = m.group(2) ?? '';
      final inner = m.group(3) ?? '';
      final boldMatch = _boldRe.firstMatch(inner);
      cells.add(
        _Cell(
          text: _cellText(inner),
          bold: boldMatch == null ? null : _stripTags(boldMatch.group(1)!),
          rowspan: _intAttr(attrs, 'rowspan') ?? 1,
          colspan: _intAttr(attrs, 'colspan') ?? 1,
        ),
      );
    }
    return cells;
  }

  static String _cellText(String inner) {
    final withBreaks = inner.replaceAllMapped(_brRe, (_) => '\n');
    final plain = _decodeEntities(_stripTags(withBreaks));
    return plain
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .join('\n');
  }

  static String _stripTags(String s) => s.replaceAll(_tagRe, '');

  static String _decodeEntities(String s) => s
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll('&middot;', '·');

  static int? _intAttr(String attrs, String name) {
    final m = RegExp(
      '$name\\s*=\\s*(?:"([^"]*)"|\'([^\']*)\'|([^\\s>]+))',
      caseSensitive: false,
    ).firstMatch(attrs);
    if (m == null) return null;
    final raw = (m.group(1) ?? m.group(2) ?? m.group(3) ?? '').trim();
    return int.tryParse(raw);
  }

  /// 从表头行认「列 → 星期几」。
  static Map<int, int> _detectWeekdayColumns(
      List<Map<int, _Cell>> grid, List<List<_Cell>> rows) {
    for (var r = 0; r < rows.length; r++) {
      final map = <int, int>{};
      var col = 0;
      var hits = 0;
      for (final cell in rows[r]) {
        final wd = _weekdayFromCell(cell.text);
        if (wd != null) {
          map[col] = wd;
          hits++;
        }
        col += cell.colspan;
      }
      if (hits >= 3) return map;
    }
    return const {};
  }

  static int? _findHeaderRow(List<List<_Cell>> rows) {
    for (var r = 0; r < rows.length; r++) {
      var hits = 0;
      for (final cell in rows[r]) {
        if (_weekdayFromCell(cell.text) != null) hits++;
      }
      if (hits >= 3) return r;
    }
    return null;
  }

  static int? _weekdayFromCell(String text) {
    final m = _weekdayRe.firstMatch(text);
    if (m == null) return null;
    return _weekdayFrom(m.group(1)!);
  }

  static int? _weekdayFrom(String value) {
    const map = {
      '一': 1, '二': 2, '三': 3, '四': 4, '五': 5, '六': 6, '日': 7, '天': 7,
      '1': 1, '2': 2, '3': 3, '4': 4, '5': 5, '6': 6, '7': 7,
      '１': 1, '２': 2, '３': 3, '４': 4, '５': 5, '６': 6, '７': 7,
    };
    return map[value];
  }

  /// 出现次数最多的「含时间区间」的那一列，就是节次列。
  static int? _detectTimeColumn(List<Map<int, _Cell>> grid) {
    final counts = <int, int>{};
    for (final row in grid) {
      for (final entry in row.entries) {
        if (_parseTimeRange(entry.value.text) != null) {
          counts[entry.key] = (counts[entry.key] ?? 0) + 1;
        }
      }
    }
    if (counts.isEmpty) return null;
    var best = counts.keys.first;
    for (final entry in counts.entries) {
      if (entry.value > (counts[best] ?? 0)) best = entry.key;
    }
    return best;
  }

  static (int, int)? _parseTimeRange(String text) {
    final m = _timeRangeRe.firstMatch(text);
    if (m == null) return null;
    final start = int.parse(m.group(1)!) * 60 + int.parse(m.group(2)!);
    final end = int.parse(m.group(3)!) * 60 + int.parse(m.group(4)!);
    if (end <= start) return null;
    return (start, end);
  }

  static ImportEntry? _entryFromCell({
    required _Cell cell,
    required int weekday,
    required int startMinute,
    required int endMinute,
  }) {
    final bold = cell.bold?.trim();
    final lines = cell.text.split('\n').map((l) => l.trim()).toList();

    String? name;
    if (bold != null && bold.isNotEmpty) {
      name = bold;
    } else if (lines.isNotEmpty) {
      name = lines.firstWhere(
        (l) => l.isNotEmpty && _parseTimeRange(l) == null,
        orElse: () => '',
      );
    }
    if (name == null || name.isEmpty) return null;

    String? teacher;
    final locations = <String>[];
    final weekTokens = <String>[];
    final warnings = <String>[];

    var rest = cell.text.replaceAll(bold ?? '', '');

    final teacherMatch = _teacherRe.firstMatch(rest);
    if (teacherMatch != null) {
      final found = (teacherMatch.group(1) ?? teacherMatch.group(2) ?? '').trim();
      if (found.isNotEmpty) teacher = found;
      rest = rest.replaceFirst(teacherMatch.group(0)!, ' ');
    }

    for (final group in _parenRe.allMatches(rest)) {
      final content = group.group(1) ?? '';
      for (final chunk in content.split(RegExp(r'[;；]'))) {
        var piece = chunk.trim();
        if (piece.isEmpty) continue;

        if (piece.contains('单周')) {
          weekTokens.add('单');
        } else if (piece.contains('双周')) {
          weekTokens.add('双');
        }
        final weeksMatch = _weeksInGroupRe.firstMatch(piece);
        if (weeksMatch != null) {
          weekTokens.add(
            weeksMatch.group(1)!.replaceAll(RegExp(r'\s'), ''),
          );
          piece = piece.replaceFirst(weeksMatch.group(0)!, ' ');
        }
        for (final part in piece.split(RegExp(r'[,，]'))) {
          final v = part.trim();
          if (v.isNotEmpty) locations.add(v);
        }
      }
    }

    // 括号外面也可能直接写了地点（例如「工2-302-1」没包在括号里）
    if (locations.isEmpty) {
      for (final line in lines) {
        if (line == name) continue;
        final candidate = line.replaceAll(RegExp(r'[（(].*?[）)]'), '').trim();
        if (candidate.isNotEmpty &&
            _parseTimeRange(candidate) == null &&
            !candidate.contains('周')) {
          locations.add(candidate);
        }
      }
    }

    final weeks = weekTokens.isEmpty
        ? '*'
        : weekTokens.join(',').replaceAll(RegExp(r'\s'), '');
    final location = locations.isEmpty ? null : locations.join(' / ');
    if (location == null) warnings.add('没认出教室');

    return ImportEntry(
      name: name,
      weekday: weekday,
      startMinute: startMinute,
      endMinute: endMinute,
      teacher: teacher,
      location: location,
      weeks: weeks,
      raw: cell.text.replaceAll('\n', ' / '),
      warning: warnings.isEmpty ? null : warnings.join('；'),
    );
  }

  /// 从隐藏字段反推学期起始日：
  ///   <input class="ksrq" value="2026-10-12">  ← 当前这一周的周一
  ///   <span class="djz">第六周</span>          ← 当前是第几教学周
  /// 两者相减就是第 1 周的周一，写进学期里，之后单双周 / 周次过滤才准。
  static DateTime? _detectTermStart(String source) {
    final weekStart = _detectWeekStartDate(source);
    final week = _detectWeekNumber(source);
    if (weekStart == null) return null;
    if (week == null || week <= 1) return _mondayOf(weekStart);
    return _mondayOf(weekStart.subtract(Duration(days: (week - 1) * 7)));
  }

  static DateTime? _detectWeekStartDate(String source) {
    final ksrq = RegExp(
      r'class="[^"]*\bksrq\b[^"]*"[^>]*value="(\d{4})-(\d{1,2})-(\d{1,2})"',
      caseSensitive: false,
    ).firstMatch(source);
    final ksrq2 = ksrq ??
        RegExp(
          r'value="(\d{4})-(\d{1,2})-(\d{1,2})"[^>]*class="[^"]*\bksrq\b[^"]*"',
          caseSensitive: false,
        ).firstMatch(source);
    if (ksrq2 != null) {
      return DateTime(
        int.parse(ksrq2.group(1)!),
        int.parse(ksrq2.group(2)!),
        int.parse(ksrq2.group(3)!),
      );
    }
    final range = RegExp(r'(\d{4})年(\d{1,2})月(\d{1,2})日')
        .firstMatch(source.replaceAll(RegExp(r'<[^>]*>'), ' '));
    if (range != null) {
      return DateTime(
        int.parse(range.group(1)!),
        int.parse(range.group(2)!),
        int.parse(range.group(3)!),
      );
    }
    return null;
  }

  static int? _detectWeekNumber(String source) {
    final m = RegExp(r'第\s*([〇零一二三四五六七八九十百\d]{1,4})\s*周')
        .firstMatch(source.replaceAll(RegExp(r'<[^>]*>'), ' '));
    if (m == null) return null;
    final raw = m.group(1)!;
    final digits = int.tryParse(raw);
    return digits ?? _chineseNumber(raw);
  }

  static int? _chineseNumber(String s) {
    const digits = {
      '〇': 0, '零': 0, '一': 1, '二': 2, '两': 2, '三': 3, '四': 4,
      '五': 5, '六': 6, '七': 7, '八': 8, '九': 9,
    };
    if (s.isEmpty) return null;
    if (s == '十') return 10;
    if (s.startsWith('十')) {
      final rest = digits[s.substring(1, 2)];
      return rest == null ? 10 : 10 + rest;
    }
    var total = 0;
    var tens = 0;
    for (var i = 0; i < s.length; i++) {
      final ch = s[i];
      if (ch == '十') {
        tens = (total == 0 ? 1 : total) * 10;
        total = 0;
        continue;
      }
      if (ch == '百') {
        tens = (total == 0 ? 1 : total) * 100;
        total = 0;
        continue;
      }
      final d = digits[ch];
      if (d == null) return null;
      total = total * 10 + d;
    }
    return tens + total;
  }

  static DateTime _mondayOf(DateTime date) {
    final d = DateTime(date.year, date.month, date.day);
    return d.subtract(Duration(days: d.weekday - 1));
  }
}

class _Cell {
  const _Cell({
    required this.text,
    this.bold,
    required this.rowspan,
    required this.colspan,
  });

  final String text;
  final String? bold;
  final int rowspan;
  final int colspan;
}

class _Pending {
  _Pending(this.col, this.cell, this.remaining);

  final int col;
  final _Cell cell;
  int remaining;
}
