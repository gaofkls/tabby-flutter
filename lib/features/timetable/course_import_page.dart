import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/router.dart';
import '../../data/conflicts.dart';
import '../../data/course_repository.dart';
import '../../data/html_schedule_parser.dart';
import '../../data/sample_schedule_html.dart';
import '../../data/schedule_parser.dart';
import '../memo/memo_editor.dart';

const _weekdayLabels = ['一', '二', '三', '四', '五', '六', '日'];

const _textSample = [
  '高等数学 周一 第1-2节 教三-201 张老师 1-16周',
  '大学英语 周二 10:00-11:40 教二-305 李老师 1-16周',
  '数据结构 周三 第5-6节 实验楼A402 王老师 单周',
  '线性代数 周四 08:00-09:40 教三-208 赵老师',
  '体育 周五 16:00-17:40 操场 陈老师',
];

/// 粘贴教务系统的课表（网页源码 或 纯文本）→ 解析 → 勾选确认 → 批量入库。
class CourseImportPage extends ConsumerStatefulWidget {
  const CourseImportPage({super.key});

  @override
  ConsumerState<CourseImportPage> createState() => _CourseImportPageState();
}

class _CourseImportPageState extends ConsumerState<CourseImportPage> {
  final _controller = TextEditingController();
  ImportResult? _result;
  final _selected = <int>{};
  bool _importing = false;
  bool _isHtml = false;
  bool _applyTermStart = true;
  List<Conflict> _conflicts = const [];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _parse() {
    final source = _controller.text;
    final isHtml = HtmlScheduleParser.looksLikeHtml(source);
    final result =
        isHtml ? HtmlScheduleParser.parse(source) : ScheduleParser.parse(source);
    setState(() {
      _isHtml = isHtml;
      _result = result;
      _applyTermStart = result.termStart != null;
      _selected
        ..clear()
        ..addAll(List.generate(result.entries.length, (i) => i));
    });
    _previewConflicts(result);
  }

  Future<void> _previewConflicts(ImportResult result) async {
    if (result.entries.isEmpty) {
      if (mounted) setState(() => _conflicts = const []);
      return;
    }
    final conflicts = await ref
        .read(courseRepositoryProvider)
        .previewImportConflicts(result.entries);
    if (mounted) setState(() => _conflicts = conflicts);
  }

  Future<void> _import() async {
    final result = _result;
    if (result == null) return;
    final chosen = [
      for (final i in _selected) if (i < result.entries.length) result.entries[i],
    ];
    if (chosen.isEmpty) return;

    setState(() => _importing = true);
    try {
      final db = ref.read(databaseProvider);
      if (result.termStart != null && _applyTermStart) {
        await db.setActiveTermStart(result.termStart!);
      }
      final report = await ref
          .read(courseRepositoryProvider)
          .importEntries(chosen);
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            report.total == 0
                ? '没有可导入的条目'
                : '已导入：新建 ${report.created} 门、更新 ${report.updated} 门',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  String _formatDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final result = _result;

    return Scaffold(
      appBar: AppBar(
        title: const Text('粘贴导入课表'),
        actions: [
          if (result != null && result.entries.isNotEmpty)
            TextButton(
              onPressed: _importing ? null : _import,
              child: _importing
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text('导入 ${_selected.length} 条'),
            ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '两种方式都支持：直接把课表页面的网页源码整段粘进来（推荐，'
              '能认出连堂和单双周），或者一行一节课的文本。'
              '认不出来的内容会列在最下面，不会悄悄丢。',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _controller,
              minLines: 6,
              maxLines: 10,
              style: const TextStyle(fontSize: 13),
              decoration: const InputDecoration(
                hintText: '把课表页面「查看网页源代码」里 <table> 那段粘进来，'
                    '或一行一节课地粘文本',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                FilledButton.tonal(
                  onPressed: _parse,
                  child: const Text('解析'),
                ),
                TextButton(
                  onPressed: () {
                    _controller.text = sampleScheduleHtml;
                    _parse();
                  },
                  child: const Text('填网页示例'),
                ),
                TextButton(
                  onPressed: () {
                    _controller.text = _textSample.join('\n');
                    _parse();
                  },
                  child: const Text('填文本示例'),
                ),
                if (_isHtml)
                  Chip(
                    avatar: const Icon(Icons.html, size: 16),
                    label: const Text('已识别为网页课表'),
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
            if (result?.termStart != null) ...[
              const SizedBox(height: 8),
              Card(
                color: theme.colorScheme.secondaryContainer,
                child: SwitchListTile(
                  value: _applyTermStart,
                  onChanged: (v) => setState(() => _applyTermStart = v),
                  title: const Text('同时写入学期起始日'),
                  subtitle: Text(
                    '页面显示第 ${result!.termWeek} 周，'
                    '反推学期第 1 周从 ${_formatDate(result.termStart!)} 开始'
                    '（周次、单双周过滤要靠它）',
                  ),
                ),
              ),
            ],
            const SizedBox(height: 12),
            const Divider(height: 1),
            if (_conflicts.isNotEmpty) ...[
              const SizedBox(height: 8),
              Card(
                color: theme.colorScheme.errorContainer,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Icon(Icons.warning_amber_rounded,
                          color: theme.colorScheme.error, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '检测到 ${_conflicts.length} 处时间冲突 / 重叠'
                          '（可能与已有课程或备忘撞课），导入后请留意。',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onErrorContainer,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            Expanded(
              child: result == null
                  ? const Center(child: Text('粘贴后点「解析」'))
                  : result.isEmpty
                      ? const Center(child: Text('没解析出内容'))
                      : ListView(
                          children: [
                            ...result.entries.asMap().entries.map((e) {
                              final index = e.key;
                              final entry = e.value;
                              return CheckboxListTile(
                                value: _selected.contains(index),
                                onChanged: (value) {
                                  setState(() {
                                    if (value == true) {
                                      _selected.add(index);
                                    } else {
                                      _selected.remove(index);
                                    }
                                  });
                                },
                                title: Text(entry.name),
                                subtitle: Text(
                                  '周${_weekdayLabels[entry.weekday - 1]} '
                                  '${formatMinute(entry.startMinute)}–'
                                  '${formatMinute(entry.endMinute)}'
                                  '${entry.location == null ? '' : ' · ${entry.location}'}'
                                  '${entry.teacher == null ? '' : ' · ${entry.teacher}'}'
                                  '${entry.weeks == '*' ? '' : ' · ${entry.weeks}周'}',
                                ),
                                secondary: entry.warning == null
                                    ? null
                                    : Tooltip(
                                        message: entry.warning!,
                                        child: Icon(
                                          Icons.info_outline,
                                          size: 18,
                                          color: theme.colorScheme.tertiary,
                                        ),
                                      ),
                              );
                            }),
                            if (result.skipped.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              Padding(
                                padding: const EdgeInsets.all(12),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '没认出来的 ${result.skipped.length} 段',
                                      style: theme.textTheme.titleSmall
                                          ?.copyWith(
                                        color: theme.colorScheme.error,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    ...result.skipped.map(
                                      (line) => Text(
                                        line,
                                        style: theme.textTheme.bodySmall,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ],
                        ),
            ),
          ],
        ),
      ),
    );
  }
}
