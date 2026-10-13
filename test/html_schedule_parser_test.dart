import 'package:flutter_test/flutter_test.dart';
import 'package:tabby/data/html_schedule_parser.dart';
import 'package:tabby/data/sample_schedule_html.dart';

void main() {
  group('HtmlScheduleParser', () {
    test('识别网页源码', () {
      expect(HtmlScheduleParser.looksLikeHtml(sampleScheduleHtml), isTrue);
      expect(HtmlScheduleParser.looksLikeHtml('高等数学 周一 第1-2节'), isFalse);
    });

    test('解析出 6 门课', () {
      final result = HtmlScheduleParser.parse(sampleScheduleHtml);
      expect(result.skipped, isEmpty);
      expect(result.entries.length, 6);
    });

    test('连堂课：周三第 1-4 节合并成 08:00–11:25', () {
      final result = HtmlScheduleParser.parse(sampleScheduleHtml);
      final e = result.entries
          .firstWhere((e) => e.name.contains('现代图像处理'));
      expect(e.weekday, 3);
      expect(e.startMinute, 8 * 60);
      expect(e.endMinute, 11 * 60 + 25);
      expect(e.teacher, '邢素霞');
      expect(e.location, '工2-302-1');
      expect(e.weeks, '1-3,5-9');
    });

    test('跨两节课：周一第 3-4 节 09:50–11:25', () {
      final result = HtmlScheduleParser.parse(sampleScheduleHtml);
      final e = result.entries.firstWhere((e) => e.name.contains('硕士生英语'));
      expect(e.weekday, 1);
      expect(e.startMinute, 9 * 60 + 50);
      expect(e.endMinute, 11 * 60 + 25);
      expect(e.weeks, '1-18');
    });

    test('下午连堂：周一 13:40–17:05', () {
      final result = HtmlScheduleParser.parse(sampleScheduleHtml);
      final e =
          result.entries.firstWhere((e) => e.name.contains('现代控制'));
      expect(e.weekday, 1);
      expect(e.startMinute, 13 * 60 + 40);
      expect(e.endMinute, 17 * 60 + 5);
      expect(e.weeks, '1-9');
    });

    test('周五第 2-5 节：08:50–12:15', () {
      final result = HtmlScheduleParser.parse(sampleScheduleHtml);
      final e = result.entries.firstWhere((e) => e.name.contains('新时代'));
      expect(e.weekday, 5);
      expect(e.startMinute, 8 * 60 + 50);
      expect(e.endMinute, 12 * 60 + 15);
      expect(e.location, '良乡B报告厅');
    });

    test('从隐藏字段反推学期起始日：第6周 2026-10-12 → 2026-09-07', () {
      final result = HtmlScheduleParser.parse(sampleScheduleHtml);
      expect(result.termWeek, 6);
      expect(result.termStart, DateTime(2026, 9, 7));
    });

    test('只有 tbody 没有表头时，按节次列右侧 7 列兜底', () {
      final bodyOnly = sampleScheduleHtml.substring(
        sampleScheduleHtml.indexOf('<tbody>'),
      );
      final result = HtmlScheduleParser.parse(bodyOnly);
      expect(result.entries.length, 6);
      expect(result.entries.firstWhere((e) => e.name.contains('随机过程')).weekday,
          4);
    });
  });
}
