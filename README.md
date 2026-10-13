# tabby-flutter

备忘录 + 课程表结合的多端应用（macOS / Android，未来可扩展 iOS / Web）。

## 功能

- 课程表：快速导入课表，支持周视图与日视图
- 备忘录：支持「不限时间 / 精确到天 / 精确到小时」三种粒度，统一在时间轴与课表上呈现
- 提醒：可为单条备忘或课程设置提醒（跟随默认 / 不提醒 / 提前 N 分钟 / 前一天晚上指定时刻），也支持批量设置
- 冲突检测：插入与已有时间重叠的条目时弹窗提示
- 离线优先：本地 SQLite 存储，数据存于本机，无网络也可用

## 技术栈

- Flutter 3.x / Dart 3.x
- 状态管理：flutter_riverpod
- 本地数据库：drift (SQLite)
- 路由：go_router
- 系统通知/闹钟：flutter_local_notifications（离线也能响铃）

## 衍生来源与协议

本项目在**产品思路与设计**上衍生自 Tabby（原协议 MIT，Copyright (c) 2018 Maxime GRIS）。
当前 Flutter 代码为独立重写，未包含原项目的源码；国际化文案目前尚未迁入。
详见 [NOTICE.md](./NOTICE.md)。

本仓库代码采用 **MIT License**，版权归作者所有，见 [LICENSE](./LICENSE)。

## 环境

```bash
flutter pub get
flutter run          # 开发运行
flutter build apk    # 构建 Android 安装包
flutter build macos  # 构建 macOS 应用
```
