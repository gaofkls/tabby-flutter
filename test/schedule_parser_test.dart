import 'package:flutter_test/flutter_test.dart';

import 'package:tabby/data/schedule_parser.dart';

void main() {
  group('课表文本解析', () {
    test('节次格式：周一第1-2节 + 周次范围', () {
      final result = ScheduleParser.parse(
        '高等数学 周一 第1-2节 教三-201 张老师 1-16周',
      );

      expect(result.entries.length, 1);
      final e = result.entries.single;
      expect(e.name, '高等数学');
      expect(e.weekday, 1);
      expect(e.startMinute, 8 * 60);
      expect(e.endMinute, 9 * 60 + 40);
      expect(e.location, '教三-201');
      expect(e.teacher, '张老师');
      expect(e.weeks, '1-16');
      expect(result.skipped, isEmpty);
    });

    test('时分格式：08:00-09:40', () {
      final result = ScheduleParser.parse(
        '周一 08:00-09:40 大学英语 教二-305',
      );
      final e = result.entries.single;
      expect(e.name, '大学英语');
      expect(e.startMinute, 8 * 60);
      expect(e.endMinute, 9 * 60 + 40);
      expect(e.location, '教二-305');
    });

    test('星期三 + 单周 + 字母教室号', () {
      final result = ScheduleParser.parse(
        '数据结构 星期三 14:00-15:40 实验楼A402 王老师 单周',
      );
      final e = result.entries.single;
      expect(e.name, '数据结构');
      expect(e.weekday, 3);
      expect(e.weeks, '单');
      expect(e.teacher, '王老师');
    });

    test('星期用数字 + 双周', () {
      final result = ScheduleParser.parse('体育 周5 16:00-17:40 操场 双周');
      final e = result.entries.single;
      expect(e.weekday, 5);
      expect(e.weeks, '双');
    });

    test('没有周次时默认每周', () {
      final result = ScheduleParser.parse('线性代数 周四 08:00-09:40 教三-208');
      expect(result.entries.single.weeks, '*');
    });

    test('缺教室会给出 warning，但不丢这条', () {
      final result = ScheduleParser.parse('概率论 周五 10:00-11:40');
      final e = result.entries.single;
      expect(e.name, '概率论');
      expect(e.location, isNull);
      expect(e.warning, isNotNull);
    });

    test('认不出来的行进 skipped，不会静默丢掉', () {
      final result = ScheduleParser.parse(
        '高等数学 周一 08:00-09:40\n这是一句说明文字\n\n大学英语 周二 10:00-11:40',
      );
      expect(result.entries.length, 2);
      expect(result.skipped, ['这是一句说明文字']);
    });

    test('一次解析多门课', () {
      const text = '''
高等数学 周一 第1-2节 教三-201 张老师 1-16周
大学英语 周二 10:00-11:40 教二-305 李老师 1-16周
数据结构 周三 第5-6节 实验楼A402 王老师 单周
线性代数 周四 08:00-09:40 教三-208 赵老师
体育 周五 16:00-17:40 操场 陈老师
''';
      final result = ScheduleParser.parse(text);
      expect(result.entries.length, 5);
      expect(result.entries.map((e) => e.weekday).toList(), [1, 2, 3, 4, 5]);
    });
  });
}
