# 项目交接文档 (Project Handoff)

## 1. 已完成的架构 (Do Not Touch)
- **2048 核心引擎**：`lib/features/game_2048/providers/game_provider.dart` 已实现 1:1 逻辑还原（包含全盘求和加分、连续滑动 Combo 等）。
- **提词器解析引擎**：`lib/features/reader/domain/text_parser.dart` 已实现 Isolate 多线程标点正则切片。
- **神经链路桥接**：2048 的有效滑动已通过 `context.read<ReaderProvider>().nextSentence()` 成功点燃提词器。

## 2. 当前待办战役 (Next Phase)
我们需要开发**“TTS 全息控播与音频引擎”**。老代码中拥有一个极度复杂的 `AudioManager.js`（包含了 TTS 预加载队列、缓冲状态机、全局播控引擎）以及一个悬浮在底部的 `cyber-player` 毛玻璃 UI。

## 3. 你的任务目标
阅读老代码的 `AudioManager.js` 和 `style.css`，用 Flutter 的 Stream/异步队列重写为 `TtsEngineService`，并注入到当前的 `ReaderProvider` 中，最后渲染出底部的毛玻璃 `CyberPlayerConsole` 控制台。