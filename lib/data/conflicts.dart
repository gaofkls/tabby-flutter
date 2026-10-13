import 'app_database.dart';
import 'occurrence.dart';
import 'session_input.dart';

/// 一次时间冲突：新建/修改的安排跟已有的哪一条撞了。
class Conflict {
  const Conflict({
    required this.title,
    required this.detail,
    required this.kind,
  });

  /// 跟谁撞了，例如「高等数学」「备忘：交作业」
  final String title;

  /// 撞在什么时间，例如「每周三 08:00–09:40（第 1-16 周）」
  final String detail;

  /// '课程' / '备忘' / '本课程'
  final String kind;

  @override
  String toString() => '$kind · $title · $detail';
}

const _weekdayLabels = ['一', '二', '三', '四', '五', '六', '日'];

/// 两个时间段是否重叠（半开区间，首尾相接不算撞）。
bool timeRangesOverlap(int aStart, int aEnd, int bStart, int bEnd) {
  return aStart < bEnd && bStart < aEnd;
}

/// 两条周次规则是否有交集。周数上限取 32（覆盖一学期 + 小学期）。
bool weeksOverlap(String a, String b, {int weekCount = 32}) {
  for (var week = 1; week <= weekCount; week++) {
    if (weeksMatch(a, week) && weeksMatch(b, week)) return true;
  }
  return false;
}

/// 检查一门课（若干时段）跟已有安排的冲突。
///
/// [ignoreCourseId] 传正在编辑的课程 id，免得跟自己撞。
/// 冲突分三类：本课程内部互撞、跟别的课撞、跟已有备忘撞。
List<Conflict> findCourseConflicts({
  required List<SessionInput> sessions,
  required List<SessionWithCourse> existingSessions,
  required List<Item> existingItems,
  DateTime? termStart,
  String? ignoreCourseId,
}) {
  final conflicts = <Conflict>[];
  final seen = <String>{};

  void add(Conflict c) {
    final key = '${c.kind}|${c.title}|${c.detail}';
    if (seen.add(key)) conflicts.add(c);
  }

  // 1. 本课程内部：同一天的两个时段互相重叠
  for (var i = 0; i < sessions.length; i++) {
    for (var j = i + 1; j < sessions.length; j++) {
      final a = sessions[i];
      final b = sessions[j];
      if (a.weekday != b.weekday) continue;
      if (!timeRangesOverlap(a.startMinute, a.endMinute, b.startMinute,
          b.endMinute)) {
        continue;
      }
      if (!weeksOverlap(a.weeks, b.weeks)) continue;
      add(
        Conflict(
          title: '本课程的两个时段',
          detail: '${_weekSession(a)} 与 ${_weekSession(b)} 重叠',
          kind: '本课程',
        ),
      );
    }
  }

  // 2. 跟已有课程
  for (final s in sessions) {
    for (final entry in existingSessions) {
      final other = entry.session;
      if (ignoreCourseId != null && entry.course.id == ignoreCourseId) continue;
      if (other.weekday != s.weekday) continue;
      if (!timeRangesOverlap(
        s.startMinute,
        s.endMinute,
        other.startMinute,
        other.endMinute,
      )) {
        continue;
      }
      if (!weeksOverlap(s.weeks, other.weeks)) continue;
      add(
        Conflict(
          title: entry.course.name,
          detail: _weekSession(
            SessionInput(
              weekday: other.weekday,
              startMinute: other.startMinute,
              endMinute: other.endMinute,
              weeks: other.weeks,
            ),
          ),
          kind: '课程',
        ),
      );
    }

    // 3. 跟已有备忘（只跟「精确到小时」的备忘比较，精确到天不算撞）
    for (final item in existingItems) {
      if (item.done) continue;
      final due = item.dueDate;
      final minute = item.dueMinute;
      if (due == null || minute == null) continue;
      if (due.weekday != s.weekday) continue;
      if (!weeksMatch(
        s.weeks,
        weekNumberFor(due, termStart),
      )) {
        continue;
      }
      if (!timeRangesOverlap(
        s.startMinute,
        s.endMinute,
        minute,
        minute + _itemDurationMinutes,
      )) {
        continue;
      }
      add(
        Conflict(
          title: item.title,
          detail: '${due.month}/${due.day} '
              '${_time(minute)}–${_time(minute + _itemDurationMinutes)}',
          kind: '备忘',
        ),
      );
    }
  }

  return conflicts;
}

/// 检查一条备忘跟已有安排的冲突。
/// 「精确到天 / 不限时间」的备忘没有具体时段，不参与冲突判断。
List<Conflict> findItemConflicts({
  required Item candidate,
  required List<SessionWithCourse> existingSessions,
  required List<Item> existingItems,
  DateTime? termStart,
}) {
  final due = candidate.dueDate;
  final minute = candidate.dueMinute;
  if (due == null || minute == null) return const <Conflict>[];

  final conflicts = <Conflict>[];
  final start = minute;
  final end = minute + _itemDurationMinutes;

  for (final entry in existingSessions) {
    final s = entry.session;
    if (s.weekday != due.weekday) continue;
    if (!weeksMatch(s.weeks, weekNumberFor(due, termStart))) continue;
    if (!timeRangesOverlap(start, end, s.startMinute, s.endMinute)) continue;
    conflicts.add(
      Conflict(
        title: entry.course.name,
          detail: _weekSession(
            SessionInput(
              weekday: s.weekday,
              startMinute: s.startMinute,
              endMinute: s.endMinute,
              weeks: s.weeks,
            ),
          ),
        kind: '课程',
      ),
    );
  }

  for (final item in existingItems) {
    if (item.id == candidate.id) continue;
    if (item.done) continue;
    final otherDue = item.dueDate;
    final otherMinute = item.dueMinute;
    if (otherDue == null || otherMinute == null) continue;
    if (!isSameDay(otherDue, due)) continue;
    if (!timeRangesOverlap(
      start,
      end,
      otherMinute,
      otherMinute + _itemDurationMinutes,
    )) {
      continue;
    }
    conflicts.add(
      Conflict(
        title: item.title,
        detail: '${_time(otherMinute)}–'
            '${_time(otherMinute + _itemDurationMinutes)}',
        kind: '备忘',
      ),
    );
  }

  return conflicts;
}

/// 一条备忘在时间轴上占多长。默认 1 小时，跟 occurrence.dart 保持一致。
const int _itemDurationMinutes = 60;

String _weekSession(SessionInput s) =>
    '每周${_weekdayLabels[s.weekday - 1]} '
    '${_time(s.startMinute)}–${_time(s.endMinute)}'
    '${s.weeks == '*' ? '' : '（第 ${s.weeks} 周）'}';

String _time(int minute) {
  final m = minute % (24 * 60);
  final h = m ~/ 60;
  final mm = m % 60;
  return '${h.toString().padLeft(2, '0')}:${mm.toString().padLeft(2, '0')}';
}
