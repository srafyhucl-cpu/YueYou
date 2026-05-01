---
name: yueyou_flutter_performance_guard
description: 用于阅游 Flutter UI、动画、2048 棋盘、KTV 提词器、粒子、波形、赛博朋克视觉和大文件解析的性能守卫。当修改 presentation、widgets、动画、Canvas、Rive、文件导入或文本解析时使用。
---

# 阅游 Flutter 性能守卫

## 动画规则

- 高频动画禁止通过宽高、边距、定位尺寸反复触发布局。
- 优先使用 `Transform`、`Opacity`、`AnimatedBuilder`、`CustomPainter`。
- 棋盘、提词器、粒子、声波、雨幕等高频区域必须使用 `RepaintBoundary` 隔离。
- `build()` 中禁止修改状态、发请求、启动计时器或触发播放。

## 视觉系统规则

- 颜色只从 `CyberColors` 取。
- 文字样式只从 `CyberTextStyles` 取。
- 间距、圆角、尺寸 token 优先从 `CyberDimensions` 取。
- 禁止新增硬编码服务器域名、主题色、魔法数字式视觉常量。

## 大文件规则

- 处理超过 100KB 的文本解析、章节切分、编码识别，要使用 `compute` 或 `Isolate`。
- 小说导入应采用流式读取，避免一次性复制巨大字符串。
- GBK/UTF-8/BOM 处理逻辑必须有测试覆盖。

## UI 质量检查

修改视觉或交互后，至少运行相关 widget test。涉及 Web/桌面显示时，建议用 Browser Use 打开本地目标做截图检查。

常用命令：

```powershell
flutter test test/features/game_2048
flutter test test/features/reader
flutter analyze
```
