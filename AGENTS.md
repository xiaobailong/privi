# 密册 (privi) – Architecture Guide

## Overview

密册 — personal on-device Android media vault，基于 Flutter 构建的个人本地媒体保险库应用。

---

## Entry Points

**Main Entry** (`lib/main.dart`):
Flutter 应用入口，初始化绑定、配置依赖注入、启动 App 组件。

**App** (`lib/app.dart`):
顶层 MaterialApp 组件，配置路由、主题、国际化。

---

## Architecture (Clean Architecture)

```
privi/
├── lib/
│   ├── main.dart                  # 应用入口
│   ├── app.dart                   # App 组件
│   ├── application/               # 应用层（Use Cases / BLoC / Services）
│   ├── core/                      # 核心模块（工具类、常量、扩展）
│   ├── data/                      # 数据层（Repository 实现、数据源）
│   ├── domain/                    # 领域层（Entity、Repository 接口）
│   ├── presentation/              # 展示层（Widget、Page、State 管理）
│   └── l10n/                      # 国际化
├── android/                       # Android 工程文件
├── scripts/                       # 构建脚本
└── memory-bank/                   # 知识库
```

---

## Layer Dependencies

```
presentation → domain ← data
     ↓                     ↑
  application ─────────────┘
```

- **presentation**: UI widgets, pages, state management（不直接依赖 data）
- **application**: Use cases, services, BLoC（依赖 domain 和 data）
- **domain**: Entity, Repository interfaces（不依赖任何其他层）
- **data**: Repository 实现、本地数据源（实现 domain 层的接口）
- **core**: 跨层共享的工具类、常量、扩展

---

## Build

- **框架**: Flutter
- **Android 构建**: Gradle + Android SDK
- **完整构建**: `build.bat`（全流程）
  - `build.bat gradle` — 仅 Gradle
  - `build.bat fast` — 快速构建
  - `build.bat norelease` — 构建但不发布
  - `build.bat clean` — 清理
- **自测**: `dart analyze <文件>` / `dart format --output=none --set-exit-if-changed <文件>`

---

## Key Dependencies

| Dependency | Purpose |
|-----------|---------|
| Flutter | UI 框架 |
| Dart | 编程语言 |
| Gradle | Android 构建 |