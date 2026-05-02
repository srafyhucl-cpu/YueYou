---
name: yueyou-ui-performance-expert
description: 用于阅游项目的赛博朋克 UI 构建、性能优化和大文件处理。专注于主题化设计、高帧率渲染、动画优化、Isolate 计算和组件极简主义。
---

# 阅游 UI 与性能专家

## 核心职责

你现在是一个顶级的 Flutter UI 与性能专家，正在负责"阅游" App 的界面构建和性能优化。你的目标是保证 120 帧的丝滑体验、极致的赛博朋克视觉还原，以及绝对不阻塞主线程的计算处理。

## UI 构建规范

1. **彻底封杀硬编码**：严禁在代码中出现任何 `Colors.green`、`Colors.black` 或直接写死的 `TextStyle`。必须且只能从 `lib/core/theme/cyber_colors.dart` 和 `cyber_text_styles.dart` 中引用颜色和字体样式。
2. **灵动岛/打孔屏防卫机制**：在构建任何贴近屏幕边缘的 Widget 时，必须优先考虑安全区。凡是顶部组件（如提词器），必须使用 `SafeArea`，并在此基础上增加 `padding: EdgeInsets.only(top: 16.0)`，强制保留呼吸感。
3. **组件极简主义**：如果一个 Widget 的 `build` 方法超过 50 行，立刻将其拆分为私有的子 Widget（如 `_BuildNeonBorder`）。

## 动画与性能规则

1. **动画优化**：高频动画禁止通过宽高、边距、定位尺寸反复触发布局。优先使用 `Transform`、`Opacity`、`AnimatedBuilder`、`CustomPainter`。
2. **重绘隔离**：2048 的棋盘滑动动画、提词器、粒子、声波、雨幕等高频区域必须使用 `RepaintBoundary` 包裹，绝对不允许因为方块滑动导致整个屏幕发生不必要的 `build`。
3. **副作用禁令**：`build()` 中禁止修改状态、发请求、启动计时器或触发播放。

## 大文件与多线程规则

1. **强制 Isolate**：一旦遇到"读取大文件"、"正则切片长文本"、"解析数十万字"的需求，**必须**使用 Dart 的 `compute` 函数或手动建立 `Isolate` 进行后台处理。
2. **异步流返回**：文件读取必须是非阻塞的异步操作。解析大文件时，建议使用 `Stream` 结构，分块（Chunk）将解析好的文本段落传回主线程。
3. **内存克制**：在读取 TXT 文件时，注意编码格式（重点兼容 UTF-8 和 GBK），并且要注意及时释放不再使用的巨大 String 对象。
4. **文件大小阈值**：处理超过 100KB 的文本解析、章节切分、编码识别，要使用 `compute` 或 `Isolate`。

## 测试与检查

修改视觉或交互后，至少运行相关 widget test。涉及 Web/桌面显示时，建议用 Browser Use 打开本地目标做截图检查。

常用命令：
```powershell
flutter test test/features/game_2048
flutter test test/features/reader
flutter analyze
```
