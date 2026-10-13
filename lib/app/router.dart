import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../data/app_database.dart';
import '../data/occurrence.dart';
import '../data/reminder_providers.dart';
import '../features/memo/item_providers.dart';
import '../features/settings/settings_page.dart';
import '../features/memo/memo_page.dart';
import '../features/timetable/timetable_page.dart';
import '../features/today/today_page.dart';
import '../services/notification_service.dart';
import '../services/widget_data_service.dart';

/// 本地 SQLite 数据库，整个 app 唯一实例。
final databaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});

final _rootNavigatorKey = GlobalKey<NavigatorState>();

final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    navigatorKey: _rootNavigatorKey,
    initialLocation: '/today',
    routes: [
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) {
          return AppShell(navigationShell: navigationShell);
        },
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/today',
                builder: (context, state) => const TodayPage(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/timetable',
                builder: (context, state) => const TimetablePage(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/memo',
                builder: (context, state) => const MemoPage(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/settings',
                builder: (context, state) => const SettingsPage(),
              ),
            ],
          ),
        ],
      ),
    ],
  );
});

class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    // 通知权限先要一次，然后把未来 30 天的提醒写进系统；顺带刷新桌面小组件
    Future.microtask(() async {
      await NotificationService.instance.init();
      await ref.read(reminderSchedulerProvider).reschedule();
      await _refreshSideEffects();
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  /// 课程 / 备忘 / 默认提醒变了就重排系统闹钟，并刷新桌面小组件。
  /// 连续改动合并成一次，避免一边打字一边重排。
  void _scheduleReschedule() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 600), () async {
      await ref.read(reminderSchedulerProvider).reschedule();
      await _refreshSideEffects();
    });
  }

  /// 刷新桌面小组件的数据快照（今天 / 明天的备忘）。
  Future<void> _refreshSideEffects() =>
      ref.read(widgetDataServiceProvider).refresh();

  void _goTo(int index) {
    widget.navigationShell.goBranch(
      index,
      initialLocation: index == widget.navigationShell.currentIndex,
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(sessionsWithCourseProvider, (_, _) => _scheduleReschedule());
    ref.listen(itemsProvider, (_, _) => _scheduleReschedule());
    ref.listen(defaultReminderProvider, (_, _) => _scheduleReschedule());

    final destinations = const [
      NavigationRailDestination(
        icon: Icon(Icons.today_outlined),
        selectedIcon: Icon(Icons.today),
        label: Text('今日'),
      ),
      NavigationRailDestination(
        icon: Icon(Icons.grid_on_outlined),
        selectedIcon: Icon(Icons.grid_on),
        label: Text('课表'),
      ),
      NavigationRailDestination(
        icon: Icon(Icons.checklist_outlined),
        selectedIcon: Icon(Icons.checklist),
        label: Text('备忘'),
      ),
      NavigationRailDestination(
        icon: Icon(Icons.settings_outlined),
        selectedIcon: Icon(Icons.settings),
        label: Text('设置'),
      ),
    ];

    final index = widget.navigationShell.currentIndex;

    return Scaffold(
      body: Row(
        children: [
          SafeArea(
            child: NavigationRail(
              destinations: destinations,
              selectedIndex: index,
              onDestinationSelected: _goTo,
              labelType: NavigationRailLabelType.all,
            ),
          ),
          const VerticalDivider(width: 1),
          Expanded(child: widget.navigationShell),
        ],
      ),
    );
  }
}
