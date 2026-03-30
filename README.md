# 阅游 (YueYou)

**赛博朋克风格的沉浸式小说阅读器 + 2048 游戏**

基于 Flutter 构建的高性能跨平台应用，融合提词器朗读与益智游戏于一体。

---

## ✨ 核心特性

### 📖 智能阅读引擎
- **TTS 朗读**：HTTP 流式 TTS + 智能预加载（3 句缓冲）
- **赛博提词器**：KTV 逐字扫光动画 + 自动滚动
- **章节管理**：正序/倒序切换 + O(1) 定位当前章节
- **阅读进度**：实时同步 + 持久化存储

### 🎮 2048 游戏
- **赛博视觉**：动态霓虹光晕 + 渐变方块
- **游戏机制**：滑动合并 + Combo 连击 + 分数动画
- **性能优化**：`RepaintBoundary` 隔离 + 60FPS 流畅

### 🎨 赛博朋克 UI
- **毛玻璃效果**：`BackdropFilter` + 统一玻璃工具栏
- **霓虹配色**：青色/粉色/紫色/绿色主题
- **动画系统**：120ms 微交互 + 平滑过渡

---

## 🏗️ 技术架构

### 核心技术栈
- **Flutter 3.x** — 跨平台 UI 框架
- **Provider** — 状态管理
- **SharedPreferences** — 本地持久化
- **Isolate (compute)** — 大文件解析隔离
- **audioplayers + http** — 流式 TTS 引擎

### 架构模式
```
lib/
├── core/                    # 核心层
│   ├── theme/              # 主题系统（CyberColors/CyberTextStyles）
│   ├── config/             # 环境配置（TtsConfig）
│   └── services/           # 全局服务
├── features/               # 功能模块
│   ├── reader/            # 阅读器
│   │   ├── domain/        # 纯业务逻辑（UI 隔离）
│   │   ├── providers/     # 状态管理
│   │   └── presentation/  # UI 层
│   ├── audio/             # TTS 引擎
│   ├── game_2048/         # 2048 游戏
│   ├── library/           # 书库管理
│   ├── sync/              # 云同步服务
│   └── dashboard/         # 主界面
└── shared/                # 共享组件
```

### 数据流
```
UI (Consumer) → Provider (ChangeNotifier) → Service → Storage
                    ↓
              业务逻辑 (domain/)
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

### 运行项目（本地 TTS/Sync 服务器）
```bash
flutter run
```

### 运行项目（指定远端服务器）
```bash
flutter run \
  --dart-define=TTS_SERVER_URL=http://your-tts-server:3000/api/v1/tts/createStream \
  --dart-define=SYNC_SERVER_URL=http://your-sync-server:8080
```

### 构建 Release APK
```bash
flutter build apk --release \
  --dart-define=TTS_SERVER_URL=http://your-tts-server:3000/api/v1/tts/createStream \
  --dart-define=SYNC_SERVER_URL=http://your-sync-server:8080
```

### 代码检查
```bash
flutter analyze
```

---

## ⚙️ 服务器配置

TTS 和云同步服务器地址通过编译期常量注入，**不在代码中硬编码任何服务器 IP**。

| 变量 | 说明 | 默认值（开发） |
|------|------|--------------|
| `TTS_SERVER_URL` | TTS 流式接口地址 | `http://localhost:3000/api/v1/tts/createStream` |
| `SYNC_SERVER_URL` | 云同步服务地址 | `http://localhost:8080` |

> 本地开发时默认指向 `localhost`，部署时通过 `--dart-define` 传入真实服务器地址。

### Android 明文流量（HTTP）
如使用 HTTP 协议连接服务器，需在 `android/app/src/main/AndroidManifest.xml` 中添加：
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
  http: ^1.6.0               # HTTP 请求（TTS/Sync）
  audioplayers: ^6.4.0       # 流式音频播放
  path_provider: ^2.1.5      # 临时文件路径
  fast_gbk: ^1.0.0           # GBK 编码支持
  wakelock_plus: ^1.4.0      # 屏幕常亮
  rive: ^0.13.14             # Rive 动画
  marquee: ^2.3.0            # 跑马灯文字
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

// 毛玻璃系统
glassDark         rgba(10,10,15,0.85)  // 深底色
panelBackground   #0D0E18              // 面板底色
surface           #1A1B28             // 卡片表面

// 语义化透明度
whiteHigh/Medium/Dim/Muted/Subtle/Faint  // 白色系列
blackOverlay/Shadow/Dim                   // 黑色系列
```

---

## 🎯 开发规范

项目遵循 `.agents/skills/` 下定义的严格开发规范：

- ✅ **零硬编码颜色**：所有颜色集中在 `CyberColors`
- ✅ **UI 物理隔离**：`domain/` 下禁止引入 `material.dart`
- ✅ **强制 Isolate**：大文件解析用 `compute`
- ✅ **SafeArea 包裹**：顶层界面防止刘海遮挡
- ✅ **RepaintBoundary 隔离**：动画组件性能优化
- ✅ **服务器地址外置**：通过 `--dart-define` 注入，禁止硬编码

---

## 📄 许可证

MIT License
