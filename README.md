# 阅游 (YueYou)

**赛博朋克风格的沉浸式小说阅读器 + 2048 游戏**

从 Capacitor/JS/CSS 混合应用 1:1 重构为 Flutter 高性能原生应用。

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
- **Provider** — 状态管理（百万级架构）
- **SharedPreferences** — 本地持久化
- **Isolate (compute)** — 大文件解析隔离

### 架构模式
```
lib/
├── core/                    # 核心层
│   ├── theme/              # 主题系统（CyberColors/CyberTextStyles）
│   └── services/           # 全局服务
├── features/               # 功能模块
│   ├── reader/            # 阅读器
│   │   ├── domain/        # 纯业务逻辑（UI 隔离）
│   │   ├── providers/     # 状态管理
│   │   └── presentation/  # UI 层
│   ├── audio/             # TTS 引擎
│   ├── game_2048/         # 2048 游戏
│   ├── library/           # 书库管理
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

## 🎯 开发规范

项目遵循 `.agents/skills/` 下定义的严格开发规范：

### 1. **UI/UX 规范** (`ui_cyberpunk.md`)
- ✅ **零硬编码颜色**：所有颜色集中在 `CyberColors`
- ✅ **SafeArea 包裹**：顶层界面防止刘海遮挡
- ✅ **RepaintBoundary 隔离**：动画组件性能优化
- ✅ **组件模块化**：单一职责 + 可复用

### 2. **领域逻辑规范** (`domain_pure_logic.md`)
- ✅ **UI 物理隔离**：`domain/` 下禁止引入 `material.dart`
- ✅ **纯函数设计**：无副作用 + 可测试
- ✅ **强类型约束**：避免 `dynamic`（JSON 序列化除外）
- ✅ **中文算法注释**：复杂逻辑必须注释

### 3. **性能规范** (`isolate_computation.md`)
- ✅ **强制 Isolate**：大文件解析用 `compute`
- ✅ **异步流处理**：TTS 流式响应
- ✅ **内存管理**：及时释放资源

### 4. **迁移规范** (`skill_strict_migration.md`)
- ✅ **1:1 逻辑复刻**：保留旧版业务规则
- ✅ **溯源注释**：61 处 `对应 JS xxx` 注释
- ✅ **禁止脑补**：不添加旧版不存在的功能

---

## 🚀 快速开始

### 环境要求
- Flutter SDK ≥ 3.0.0
- Dart SDK ≥ 3.0.0

### 安装依赖
```bash
flutter pub get
```

### 运行项目
```bash
flutter run
```

### 代码检查
```bash
flutter analyze  # 当前：零报错 ✅
```

---

## 📦 核心依赖

```yaml
dependencies:
  flutter:
    sdk: flutter
  provider: ^6.0.0           # 状态管理
  shared_preferences: ^2.0.0 # 本地存储
  file_picker: ^5.0.0        # 文件选择
  http: ^1.0.0               # HTTP 请求
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
glassDark         #D90A0A0F  // 深底色
panelBackground   #0D0E18    // 面板底色
surface           #1A1B28    // 卡片表面

// 语义化透明度
whiteHigh/Medium/Dim/Muted/Subtle/Faint  // 白色系列
blackOverlay/Shadow/Dim                   // 黑色系列
```

---

## 📝 开发日志

### 最近更新
- ✅ **2024-03** 完成开发规范审计，消灭 71 处硬编码颜色
- ✅ **2024-03** 重构顶部导航为统一玻璃工具栏（方案C）
- ✅ **2024-03** 修复章节标题朗读逻辑（拆分噪音/标题判定）
- ✅ **2024-03** 实现 TTS 流式引擎 + 智能预加载

### 待办事项
- [ ] 添加书签功能
- [ ] 支持更多 TTS 发音人
- [ ] 优化大文件（>10MB）加载性能
- [ ] 添加夜间模式切换

---

## 📄 许可证

MIT License

---

## 🙏 致谢

本项目从旧版 Capacitor 应用迁移而来，保留了原有的业务逻辑和用户体验，同时通过 Flutter 重构实现了更高的性能和更好的代码可维护性。
