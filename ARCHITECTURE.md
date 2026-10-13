# Tabby Flutter 版 · 架构设计

离线优先的「备忘录 + 课程表」应用。当前目标平台 macOS 桌面与 Android，一套代码。

## 一、技术选型（为什么是这些）

| 领域 | 选择 | 理由 |
| --- | --- | --- |
| UI 框架 | Flutter 3.47（Dart 3.13） | 一套代码同时覆盖 macOS 桌面与 Android 原生 |
| 状态管理 | Riverpod | 编译期安全、不依赖 BuildContext，方便单元测试 |
| 路由 | go_router + StatefulShellRoute | 保留选中 tab 的导航栈，日后支持 URL / 深链 |
| 本地数据库 | drift + SQLite | 类型安全的查询、响应式 stream、schema migration |
| 路由/DB 之外 | intl（日期格式）、uuid（主键）、path/ path_provider（文件） | 均为纯 Dart，无需原生插件，减少平台适配成本 |

**明确不使用**：Firebase / Google 服务（国内不可用）、任何运行时下载字体的包（字体自托管或系统字体）。

## 二、中国大陆网络适配（已落地）

- `~/.zshrc` 永久写入：
  - `PUB_HOSTED_URL=https://pub.flutter-io.cn`
  - `FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn`
  - `PATH` 追加 `$HOME/development/flutter/bin`
- Flutter SDK 从 `storage.flutter-io.cn` 下载（实测 6.4 MB/s），非 Google 源。
- Homebrew 已装 CocoaPods 1.17（走腾讯 bottle 镜像）。

### Android 工具链（已跑通首个 apk）

| 组件 | 位置 / 版本 | 来源 |
| --- | --- | --- |
| JDK | `/opt/homebrew/opt/openjdk@17`（17.0.20） | brew，腾讯 bottle 镜像 |
| Android SDK | `~/development/android-sdk`（platform 35/36、build-tools 36、NDK r28c、CMake 3.22.1） | `dl.google.com` 直连可用（实测 8 MB/s，21 秒装完） |
| Gradle | 9.3.1 | `services.gradle.org` **不可达** → 腾讯镜像 `mirrors.cloud.tencent.com/gradle/` |
| Maven | — | `maven.google.com` **不可达** → 腾讯镜像；`repo1.maven.org` / `plugins.gradle.org` 直连可用 |

**换源做法**：写 `~/.gradle/init.d/mirrors.gradle`（全局生效，对所有 Gradle 构建包括 Flutter SDK 内部
`includeBuild` 的 `flutter_tools/gradle` 都适用，升级 Flutter 不用重改）：删掉 `google()` 仓库、
补上腾讯镜像，并**显式调一次 `gradlePluginPortal()`**——一旦显式配置 `pluginManagement.repositories`，
Gradle 默认的插件门户就不再生效，不补回来会报「kotlin-dsl 插件找不到」。

`~/.zshrc` 里已写入 `JAVA_HOME` / `ANDROID_SDK_ROOT` / `ANDROID_HOME` 和 `platform-tools` 的 PATH。

构建命令（红米 K70 是 arm64，只打 arm64 更快更小）：

```bash
flutter build apk --release --target-platform android-arm64   # 约 21MB
adb install -r build/app/outputs/flutter-apk/app-release.apk
```

红米 K70（HyperOS）装机的三个开关：设置 → 我的设备 → 全部参数 → 连点版本号开开发者选项；
更多设置 → 开发者选项 → 开「USB 调试」**和「USB 安装」**（MIUI/小米系独有，不开会
`INSTALL_FAILED_USER_RESTRICTED`）；不想插线就用「无线调试」→ `adb pair IP:端口` →
`adb connect IP:端口`。

## 三、数据模型

所有表都有三个「为将来同步预留」的字段：`id`（客户端生成的 uuid）、`updated_at`、`deleted_at`（软删除墓碑）。
同步现在不做，但字段现在就埋好，将来接同步无需数据迁移。

- `terms` 学期：id、name、start_date、end_date、week_count、is_active
- `courses` 课程元信息：id、term_id、name、teacher、location、color、note、reminder_mode、reminder_value
- `course_sessions` 上课时段：id、course_id、weekday(1-7)、start_minute、end_minute、weeks、location_override
  - 时间用「当天 0 点起的分钟数」存储，排序和重叠计算最简单
  - `weeks` 用字符串表达单双周与跳周：`*`=每周、`单`/`双`、`1-16`、`1,3,5`
- `items` 备忘/待办：id、title、note、due_date、due_minute、course_id、done、done_at、reminder_mode、reminder_value
- `app_settings` 全局设置（key/value）：当前存 `defaultReminderMode` / `defaultReminderValue`

**备忘的三种时间粒度**（核心设计）：

| due_date | due_minute | 含义 | 展示 |
| --- | --- | --- | --- |
| 空 | 空 | 不限时间 | 进当天待办区；周课表当日格子上方角标 |
| 有 | 空 | 精确到天 | 当天置顶，不占时间轴 |
| 有 | 有 | 精确到小时 | 按时间插入时间轴，与课程块并排 |

## 三·补、提醒（闹钟）与时间冲突检测

**提醒规则**（`lib/data/reminder.dart` 的 `ReminderSpec`，三种形态）：

| 形态 | 存储 | 含义 |
| --- | --- | --- |
| `none` | mode=0 | 不提醒 |
| `before` | mode=1, value=分钟数 | 事件开始前 N 分钟 |
| `previousDay` | mode=2, value=当天 0 点起分钟数 | 前一天固定时刻（默认 21:00） |

`reminder_mode` / `reminder_value` 为 **null 表示跟随全局默认**，全局默认存在 `app_settings` 表，
设置页可改。课程级提醒作用于它的所有时段；备忘级提醒对「精确到天」也成立（按当天 0 点算开始）。

**时间冲突检测**（`lib/data/conflicts.dart`）：保存课程/备忘前跑一遍，
判定条件是「同一天 + 时间区间重叠（半开区间，首尾相接不算）+ 周次有交集」。
只跟「精确到小时」的备忘比；编辑自己时跳过自己。撞了就弹窗列出跟谁撞、撞在什么时候，可选「仍然保存」。

**系统通知**（`lib/services/notification_service.dart`，flutter_local_notifications 22）：
`ReminderScheduler` 把未来 30 天的课程（weekday + 周次展开）与备忘展开成最多 400 条 `ReminderTask`，
`applyPlan` 先 `cancelAll` 再逐条 `zonedSchedule`。AppShell 监听课程/备忘/默认提醒三个流，600ms 防抖重排。
时区写法是 `tz.TZDateTime.from(at, tz.UTC)`：插件把「本地墙钟 + 时区名」传给平台侧，UTC 构造出的瞬时是正确的，
因此不需要 flutter_timezone，也不需要初始化 timezone 数据库。

Android 侧需要：`POST_NOTIFICATIONS` / `SCHEDULE_EXACT_ALARM` / `USE_EXACT_ALARM` / `RECEIVE_BOOT_COMPLETED`
权限、两个 receiver，以及 `coreLibraryDesugaring`（插件内部用了 java.time）。

**入口**：备忘编辑器 / 课程编辑器里的「提醒」卡片（备忘编辑器还会实时算出「X 月 X 日 HH:mm 会响」）、
条目 ⋮ 菜单「设置提醒」、设置页（默认提醒 / 权限 / 已排定数量 / 立即重排 / 批量应用 / 清除单独设置）、
课表页 FAB「批量设置提醒」。

## 四、发生实例层（视图统一的关键）

课程是「每周重复的规则」，备忘是「落在某一天的事实」。两个视图要同时显示它们，
所以中间加一层展开逻辑，把两者统一成 `Occurrence`：

```
course_sessions（weekday + 起止分钟 + 周次）  ─┐
                                              ├─→ Occurrence ─→ 周课表格子 / 月日历格子
items（due_date + due_minute）                ─┘
```

`buildOccurrences(from, to, sessions, items, termStart)`：

- 课程：对区间内每一天，按 weekday 命中 + `weeksMatch(weeks, 第几周)` 过滤，展开成实例
- 备忘：due_date 落在区间内则成为一个实例；due_minute 为空的进 `allDay`，有值的进 `timed`
- 连 due_date 都没有的备忘进 `untimed`（不限时间），以条带形式挂在视图下方

周次规则 `weeksMatch` 支持 `*`、`单`、`双`、`1-16`、`1,3,5`；没有学期起始日时不做周次过滤。

**学期起始日**是周次能成立的唯一依据（`weekNumberFor`）：它存在，才知道「第 3 周」是几月几日，
单双周才能过滤。它有三个来源：导入网页课表时反推、课程编辑器里就地设置、设置页手动改。
`week_helpers.dart` 负责两个方向的换算（`weeksFromDateRange` 日期→周次、`describeWeeks` 周次→日期）。

两个视图共用同一份 `OccurrenceSet`，只是密度不同：

| 视图 | 密度 | 课程 | 备忘 |
| --- | --- | --- | --- |
| 周课表 | 详细 | 时间轴格子（块内含教室/教师） | 精确到小时→时间轴块；精确到天→全天条带；不限时间→底部条带 |
| 月日历 | 粗略 | 当日缩略条（时间+课名），超出折叠 +N | 同上缩略条，点日期弹出当天完整清单 |

## 五、课表导入：网页源码优先

教务系统大多只给 HTML 表格（复制不出干净文本），所以导入有两条路，自动识别：

| 输入 | 解析器 | 可靠度 |
| --- | --- | --- |
| 网页源码（含 `<table>`） | `html_schedule_parser.dart` | 高：class="节次_星期" 直接给出星期几，`rowspan` 给出连堂，表头给出星期列 |
| 一行一节课的文本 | `schedule_parser.dart` | 中：靠样式挑片段，剩下最长中文词当课程名 |

HTML 解析的三个关键步骤：

1. **摊平网格**：按 `<tr>/<td>` 还原成「行 × 列」矩阵，处理 `rowspan` / `colspan`，
   并记下哪些单元格是在这一行「新出现」的（跨行的格子只在首行生成一条记录）。
2. **定位列**：表头含「星期一…星期日」的列即星期列；只粘到 `<tbody>` 没有表头时，
   退化为「节次列右侧连续 7 列」。
3. **合并连堂**：单元格 `rowspan=4` 表示连上 4 节，起止时间 = 首行的开始时间 + 末行的结束时间
   （例：第 1 节 rowspan=4 → 08:00–11:25，而不是 08:00–08:45）。

**学期起始日反推**：课表页里通常有 `<input class="ksrq" value="2026-10-12">`（本周周一）
和 `<span class="djz">第六周</span>`，两者相减即得第 1 周的周一（2026-09-07）。
导入时可勾选「同时写入学期起始日」——没有它，单双周和跳周无法过滤。

单元格内容解析：`<b>` 内是课程名，`【】` 内是教师，括号内按 `;` 分组、
每组「地点,第X-Y周」拆成 location + weeks（如 `1-3,5-9周` → `weeks="1-3,5-9"`）。

## 六、代码结构

```
lib/
  main.dart                 入口
  app/
    app.dart                MaterialApp.router（主题、明暗色）
    router.dart             go_router + 侧边导航壳 + databaseProvider
  data/
    app_database.dart       drift schema（4 张表 + 种子数据）
    app_database.g.dart     build_runner 生成
    item_repository.dart    备忘的读写入口（软删除 / 撤销）
    course_repository.dart  课程读写 + 导入合并（同名合并成一门课）
    schedule_parser.dart    课表文本 → 结构化条目（宽容解析）
    week_helpers.dart        周次 ⇄ 日期换算（第几周是几月几日）
    html_schedule_parser.dart 教务系统网页源码（HTML 表格）→ 结构化条目
    sample_schedule_html.dart 真实课表页面 HTML（示例 + 测试夹具）
    occurrence.dart         发生实例：展开规则 + 周次匹配 + provider
  features/
    today/                  今日：已过期 / 精确到小时 / 精确到天 / 不限时间
    timetable/
      timetable_page.dart   周课表 ⇄ 月日历 切换壳 + 周/月导航 + 新增菜单
      week_grid.dart        时间轴网格（7:00–22:00，重叠并排分道）
      course_editor.dart    新建/编辑课程（多时段、颜色、周次）
      course_import_page.dart 粘贴课表（网页源码 / 纯文本）→ 解析 → 勾选 → 入库
    calendar/month_grid.dart 月日历网格 + 当天清单底部面板
    memo/
      memo_page.dart        按日期分组的时间轴
      memo_editor.dart      新建/编辑面板（三档粒度切换）
      item_tile.dart        共用条目（勾选 / 编辑 / 删除 + 撤销）
      item_providers.dart   itemsProvider 等
    settings/               设置（写入示例数据）
test/
  item_repository_test.dart 备忘读写
  occurrence_test.dart      周次展开规则
  views_test.dart           两个视图的渲染 widget 测试
```

## 七、路线图（下一步）

1. ~~今日页 + 新建备忘表单~~（已完成）
2. ~~周课表格子 + 月日历双视图~~（已完成）
3. ~~快速导入：粘贴课表文本 → 解析 → 预览确认 → 入库~~（已完成）
4. ~~课程编辑：新建/编辑/删除课程，支持多时段~~（已完成）
5. ~~教务系统网页源码（HTML 表格）解析 + 学期起始日反推~~（已完成）
6. ~~Android 工具链：JDK 17 + Android SDK + 国内 Gradle/Maven 换源，apk 已出~~（已完成）
7. ~~学期起始日：导入反推 + 课程编辑器就地设置 + 设置页手动改~~（已完成）
8. **真机验证**：红米 K70 装 release apk，检查 SQLite 落盘、周课表/月日历在小屏上的排版
9. **节次表可配置**：文本导入用的 12 节作息写死了，各校不同
10. 之后才是同步（那时后端 + 增量同步 + 冲突策略）

## 八、命令备忘

```bash
flutter run -d macos           # 桌面运行
flutter build macos --debug    # 验证原生链路（需关沙箱，且已 --no-enable-swift-package-manager）
dart run build_runner build -d # 改了数据库 schema 之后必须跑
flutter analyze
flutter test                   # 42 个测试：备忘读写 / 课程读写 / 两种课表解析 / 周次换算 / 双视图渲染
```
