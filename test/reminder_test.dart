import 'package:flutter_test/flutter_test.dart';
import 'package:tabby/data/reminder.dart';

void main() {
  group('ReminderSpec', () {
    test('默认是前一天 21:00', () {
      expect(ReminderSpec.defaultValue.mode, ReminderMode.previousDay);
      expect(ReminderSpec.defaultValue.value, 21 * 60);
      expect(ReminderSpec.defaultValue.label, '前一天 21:00');
    });

    test('不提醒', () {
      const spec = ReminderSpec.none();
      expect(spec.isNone, true);
      expect(spec.resolve(DateTime(2026, 10, 12, 8)), isNull);
      expect(spec.label, '不提醒');
    });

    test('提前 N 分钟', () {
      const spec = ReminderSpec.before(30);
      final at = spec.resolve(DateTime(2026, 10, 12, 8));
      expect(at, DateTime(2026, 10, 12, 7, 30));
      expect(spec.label, '提前 30 分钟');
    });

    test('提前 1 天 / 1 小时的文案', () {
      expect(const ReminderSpec.before(1440).label, '提前 1 天');
      expect(const ReminderSpec.before(60).label, '提前 1 小时');
      expect(const ReminderSpec.before(90).label, '提前 90 分钟');
    });

    test('前一天晚上：上课当天往前推一天', () {
      const spec = ReminderSpec.previousDay(21 * 60);
      final at = spec.resolve(DateTime(2026, 10, 12, 8));
      expect(at, DateTime(2026, 10, 11, 21));
      expect(at!.isBefore(DateTime(2026, 10, 12, 8)), true);
    });

    test('前一天晚上可以选任意时刻', () {
      const spec = ReminderSpec.previousDay(7 * 60 + 30);
      final at = spec.resolve(DateTime(2026, 10, 12, 8));
      expect(at, DateTime(2026, 10, 11, 7, 30));
    });

    test('精确到天的备忘也能用「前一天」', () {
      const spec = ReminderSpec.previousDay(21 * 60);
      final at = spec.resolve(DateTime(2026, 10, 12));
      expect(at, DateTime(2026, 10, 11, 21));
    });

    test('数据库往返：null 表示跟随默认', () {
      expect(ReminderSpec.fromDb(null, null), isNull);
      expect(
        ReminderSpec.fromDb(0, null),
        const ReminderSpec.none(),
      );
      expect(
        ReminderSpec.fromDb(1, 45),
        const ReminderSpec.before(45),
      );
      expect(
        ReminderSpec.fromDb(2, 1260),
        const ReminderSpec.previousDay(1260),
      );
    });

    test('数据库字段回写', () {
      const spec = ReminderSpec.before(30);
      expect(spec.dbMode, 1);
      expect(spec.dbValue, 30);
      expect(ReminderSpec.none().dbMode, 0);
      expect(ReminderSpec.none().dbValue, isNull);
    });

    test('相等性', () {
      expect(const ReminderSpec.before(30), const ReminderSpec.before(30));
      expect(const ReminderSpec.before(30), isNot(const ReminderSpec.before(60)));
      expect(
        const ReminderSpec.previousDay(1260),
        isNot(const ReminderSpec.none()),
      );
    });
  });
}
