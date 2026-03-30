# 阅游 (YueYou)

**赛博朋克风格的沉浸式小说听读器 + 2048 游戏**

[![Flutter CI](https://github.com/srafyhucl-cpu/YueYou/actions/workflows/flutter-ci.yml/badge.svg)](https://github.com/srafyhucl-cpu/YueYou/actions/workflows/flutter-ci.yml)

基于 Flutter 构建的高性能跨平台应用，融合 KTV 提词器听书与益智游戏于一体。

---

## ✨ 核心特性

### 📖 智能阅读引擎
- **双轨流媒体 TTS**：生产者/消费者预加载架构，3 句缓冲，指数退避重试，无卡顿连续朗读
- **赛博提词器**：KTV 逐字扫光动画 + `AnimationController` 驱动平滑滚动
- **章节管理**：正序/倒序切换 + O(1) 定位当前章节
- **空闲超时**：可配置自动暂停计时器，防止忘关耗电
- **阅读进度**：实时持久化，重启恢复上次位置

### 🎮 2048 游戏
- **赛博视觉**：动态霓虹光晕 + 渐变方块 + 棋盘 3D 倾斜手感
- **游戏机制**：滑动合并 + Combo 连击 + 漂浮加分动画
- **XIAOYO 吉祥物**：Canvas 自绘，眼球跟随方向 + 合并欢呼 + 游戏结束同情
- **性能优化**：`RepaintBoundary` 隔离，60FPS 稳定

### 🎨 赛博朋克 UI
- **毛玻璃效果**：`BackdropFilter` + 统一玻璃工具栏
- **霓虹配色**：青色/粉色/紫色/绿色主题，零硬编码颜色
- **微交互**：120ms 动画 + 触觉反馈分级震动

---

## 🚧 开发中功能

| 功能 | 文件 | 状态 |
|------|------|------|
| XIAOYO Rive 动画版 | `board_mascot_rive.dart` + `assets/rive/xiaoyo.riv` | 集成中 |
| 棋盘雨滴特效 | `rain_effect.dart` | 实现完成，待接入 |
| 棋盘重置翻转动画 | `board_reset_animation.dart` | 实现完成，待接入 |
| 环境背景音乐 | `SettingsProvider.ambientEnabled` | 预留字段，待实现 |

---

## 🏗️ 技术架构

### 核心技术栈
- **Flutter 3.x / Dart 3.x** — 跨平台 UI 框架
- **Provider 6.x** — 状态管理（ChangeNotifier + ProxyProvider）
- **SharedPreferences** — 设置/游戏进度持久化
- **File System / path_provider** — 小说正文文件存储
- **audioplayers + http** — 流式 TTS 引擎
- **Isolate (compute)** — 大文件解析后台隔离
- **Rive 0.13.x** — XIAOYO 吉祥物动画（开发中）
- **fast_gbk** — GBK 编码小说文件支持
- **wakelock_plus** — 朗读时屏幕常亮

### 架构模式
```
lib/
├── core/                    # 核心层（严禁引入任何 feature 层代码）
│   ├── theme/              # 主题系统（CyberColors / CyberTextStyles / CyberDimensions）
│   ├── config/             # 环境配置（TtsConfig，dart-define 注入）
│   ├── constants/          # 全局常量
│   └── database/           # StorageService（SharedPreferences + 文件系统）
├── features/               # 功能模块
│   ├── reader/            # 阅读器
│   │   ├── domain/        # 纯业务逻辑（TextParser，严禁引入 material.dart）
│   │   ├── providers/     # 状态管理（ReaderProvider）
│   │   └── presentation/  # UI 层（TeleprompterView）
│   ├── audio/             # TTS 引擎（TtsEngineService / SfxService）
│   ├── game_2048/         # 2048 游戏（GameProvider / BoardMascot / SquareBoard）
│   ├── library/           # 书库管理（BookshelfProvider / LibraryScreen）
│   ├── settings/          # 全局设置（SettingsProvider / SettingsScreen）
│   └── dashboard/         # 主界面（DashboardScreen）
└── shared/                # 共享无状态组件
```

### 数据流
```
UI (Consumer/context.watch)
    → Provider (ChangeNotifier)
        → Service / StorageService
            → SharedPreferences / 文件系统
                    ↑
              domain/ 纯业务逻辑（Isolate 隔离）
```

---

## 🚀 快速开始

### 环境要求
- Flutter SDK ≥ 3.5.0
- Dart SDK ≥ 3.5.0

### 安装依赖
```bash
flutter pub get
```

### 运行项目（本地 TTS 服务器）
```bash
flutter run
```

### 运行项目（指定远端 TTS 服务器）
```bash
flutter run --dart-define=TTS_SERVER_URL=http://your-tts-server:3000/api/v1/tts/createStream
```

### 构建 Release APK
```bash
flutter build apk --release \
  --dart-define=TTS_SERVER_URL=http://your-tts-server:3000/api/v1/tts/createStream
```

### 代码检查
```bash
flutter analyze
```

---

## ✅ 测试与覆盖率

### 运行单元测试
```bash
flutter test
```

### 生成覆盖率报告
```bash
flutter test --coverage
```
生成的覆盖率文件位于 `coverage/lcov.info`。如需查看 HTML 报告，可使用 lcov 的 `genhtml` 工具在本地生成：
```bash
genhtml coverage/lcov.info -o coverage/html
# 打开 coverage/html/index.html 查看报告
```

### CI 集成
- 仓库已配置 GitHub Actions 工作流 `.github/workflows/flutter-ci.yml`
- 在 Push / PR 时自动执行：
  - `flutter analyze`
  - `flutter test --coverage`
- 产出物：覆盖率文件 `coverage/lcov.info` 将作为 Artifact 上传

### 测试约定
- 所有持久化相关测试使用 `SharedPreferences.setMockInitialValues({})` 与 `StorageService.resetForTesting()` 保证隔离
- 依赖 `audioplayers` 的 Provider/Widget 测试，通过 `MethodChannel` mock 避免 `MissingPluginException`

---

## ⚙️ 服务器配置

TTS 服务器地址通过编译期常量注入，**代码中不硬编码任何服务器 IP**。

| 变量 | 说明 | 默认值（开发） |
|------|------|--------------|
| `TTS_SERVER_URL` | TTS 流式接口地址 | `http://localhost:3000/api/v1/tts/createStream` |

> 本地开发时默认指向 `localhost`，部署时通过 `--dart-define` 传入真实服务器地址。

### Android 明文流量（HTTP）
如使用 HTTP 协议连接 TTS 服务器，需在 `android/app/src/main/AndroidManifest.xml` 中添加：
```xml
<application android:usesCleartextTraffic="true">
```

---

## 📦 核心依赖

```yaml
dependencies:
  provider: ^6.1.5           # 状态管理
  shared_preferences: ^2.3.3 # 本地持久化
  file_picker: ^6.1.1        # 文件导入
  http: ^1.6.0               # HTTP 请求（TTS）
  audioplayers: ^6.4.0       # 流式音频播放
  path_provider: ^2.1.5      # 文件路径（小说存储 + TTS 缓存）
  fast_gbk: ^1.0.0           # GBK 编码支持
  wakelock_plus: ^1.4.0      # 屏幕常亮
  rive: ^0.13.14             # Rive 动画（XIAOYO 吉祥物）
  marquee: ^2.3.0            # 跑马灯文字
  equatable: ^2.0.8          # 值相等比较
```

---

## 🎨 主题系统

### CyberColors 色板
```dart
// 霓虹主色
neonCyan    #22D3EE  // 青色（主要交互）
neonPink    #FE019A  // 粉色（强调/活跃）
neonPurple  #8B5CF6  // 紫色（次要）
neonGreen   #00FF41  // 绿色（成功）
hackerBlue  #00F3FF  // 骇客蓝（吉祥物/特效）

// 毛玻璃系统
glassDark         rgba(10,10,15,0.85)  // 深底色
panelBackground   #0D0E18              // 面板底色
surface           #1A1B28             // 卡片表面

// 语义化透明度
whiteHigh/Medium/Dim/Muted/Subtle/Faint  // 白色系列
blackOverlay/Shadow/Dim                   // 黑色系列
```

### CyberTextStyles 字体
```dart
CyberTextStyles.monoFont        // 等宽字体名（JetBrains Mono）
CyberTextStyles.teleprompterActive  // 提词器高亮样式
CyberTextStyles.teleprompterDim     // 提词器暗色样式
CyberTextStyles.gameGridNumber      // 棋盘数字样式
```

> **字体文件**：需将 JetBrains Mono `.ttf` 文件放入 `assets/fonts/`，并在 `pubspec.yaml` 中声明，否则回退系统默认字体。

---

## 🎯 开发规范

项目遵循 `.agents/skills/` 和 `.windsurfrules` 定义的严格规范：

- ✅ **零硬编码颜色**：所有颜色集中在 `CyberColors`，字体名集中在 `CyberTextStyles.monoFont`
- ✅ **UI 物理隔离**：`domain/` 下禁止引入 `material.dart`
- ✅ **强制 Isolate**：大文件解析用 `compute`（参考 `TextParser.parse()`）
- ✅ **build() 纯函数**：禁止在 `build()` 内调用有副作用的方法，副作用统一在 `didChangeDependencies + addListener` 中处理
- ✅ **RepaintBoundary 覆盖**：棋盘、吉祥物、提词器全部隔离重绘
- ✅ **服务器地址外置**：通过 `--dart-define` 注入，禁止硬编码
- ✅ **会话锁模式**：异步循环用递增 `session` 防止切章污染（参考 `TtsEngineService._loopSession`）
- ✅ **存储分级**：小数据用 SharedPreferences，大数据（小说正文）用文件系统

---

## 📄 许可证

MIT License
