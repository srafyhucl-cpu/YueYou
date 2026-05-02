# TTS 音频流状态机 Riverpod 重构

> **执行日期**: 2026-05-01
> **状态**: 进行中
> **策略**: 渐进迁移，先建新状态模型与兼容骨架，再逐步替换旧播放链路

---

## 一、可行性结论

本任务可行，但不适合一次性重写。当前音频模块已经接入 Riverpod 生命周期托管，但核心仍是 `ChangeNotifierProvider<TtsEngineService>`。直接替换为 `Notifier/AsyncNotifier` 会同时影响阅读器、播放控制台、设置页、2048 行为联动和大量测试。

因此采用分阶段迁移：

1. 新增 Dart 3 `sealed class` 状态树，作为新的 UI 与业务状态契约。
2. 新增 `TtsAudioNotifier`，先以兼容层方式镜像旧引擎状态。
3. 将 UI 消费逐步迁移到 `TtsAudioState` 的穷尽 `switch`。
4. 拆分旧 `TtsEngineService` 内部的 HTTP、缓冲队列、播放器驱动。
5. 最终由 `TtsAudioNotifier` 接管缓冲与播放状态机，旧服务退化为底层驱动或被删除。

---

## 二、阶段拆解

### 阶段 1：状态契约与兼容骨架

- 新增 `TtsAudioState` 密封状态树。
- 新增 `TtsAudioNotifier`，通过 Riverpod 生命周期监听旧 `TtsEngineService`。
- 保持现有 UI、Reader、测试不变。
- 验收：`flutter analyze` 不新增告警。

### 阶段 2：UI 只读状态迁移

- 播放控制台、错误监听器、提词器只读取 `ttsAudioProvider`。
- 所有 UI 展示使用 `switch (TtsAudioState)` 穷尽匹配。
- 点击事件仍可临时调用旧 `ReaderProvider.toggleTTS()`，避免一次性迁移副作用。

### 阶段 3：命令入口迁移

- 将 `play/pause/cycleSpeed/refreshSession` 迁入 `TtsAudioNotifier` 命令。
- Reader 只提供文本源，不直接持有播放状态。
- 保留本地进度持久化，不向云端同步用户进度。

### 阶段 4：缓冲队列迁移

- 将默认 6 句缓冲与低水位预取逻辑迁入 Notifier。
- 网络 POST 与音频下载拆成可测试网关。
- POST 只解析 `{"status":"success","url":"..."}`，音频必须通过 GET 下载缓存。

### 阶段 5：异常与隐私加固

- TTS 超时、格式错误、下载失败统一进入 `TtsAudioError`。
- 通过 `CyberLogger.captureWarning` 分级上报。
- 上报字段执行黑名单过滤，禁止携带文本、进度、书籍标识、个性化语音设置。

---

## 三、当前执行记录

- [x] 新增今日任务文档
- [x] 新增 `TtsAudioState`
- [x] 新增 `TtsAudioNotifier`
- [x] 执行静态分析

### 3.1 阶段 1 已落地文件

| 文件 | 说明 |
| --- | --- |
| `lib/features/audio/domain/tts_audio_state.dart` | 新增 Dart 3 密封状态树，覆盖空闲、缓冲、播放、暂停、错误五类状态 |
| `lib/features/audio/providers/tts_audio_notifier.dart` | 新增 Riverpod `NotifierProvider` 兼容骨架，当前镜像旧 `TtsEngineService` 状态 |

### 3.2 阶段 2 已推进内容

| 文件 | 说明 |
| --- | --- |
| `lib/features/audio/domain/tts_audio_state.dart` | 为所有状态补充 `playbackRate`，支持 UI 从新状态读取倍速 |
| `lib/features/audio/providers/tts_audio_notifier.dart` | 新增 `setBusinessError` 命令，承接 UI 层脱敏业务错误 |
| `lib/features/audio/presentation/widgets/cyber_player_console.dart` | 播放波形、播放按钮、倍速显示改为消费 `ttsAudioProvider`，并使用穷尽 `switch` 判断状态；无书籍错误改由 Notifier 转交 |
| `lib/shared/widgets/tts_error_listener.dart` | 错误提示改为从 `TtsAudioError` 读取脱敏错误信息与时间戳，降级通知改为从 `TtsAudioState.fallbackMessage` 读取 |

阶段 2 当前保留点：

- `TeleprompterView` 的逐字动画仍依赖 `ReaderProvider` 监听旧引擎状态，建议在命令入口迁移后再处理。

### 3.3 阶段 3 已推进内容

| 文件 | 说明 |
| --- | --- |
| `lib/features/audio/presentation/widgets/cyber_player_console.dart` | 播放按钮命令改为调用 `TtsAudioNotifier.play/pause/recover`，倍速切换改为调用 `TtsAudioNotifier.cycleSpeed` |
| `lib/features/audio/domain/tts_audio_models.dart` | 新增 `TtsAudioItem`、`TtsAudioRequest` 与 `TtsSentenceSource`，为后续状态机接管预取队列建立领域接口 |
| `lib/features/reader/providers/reader_provider.dart` | 实现 `TtsSentenceSource`，将原有三个闭包整理为具名方法，行为保持不变 |
| `lib/features/audio/services/tts_engine_service.dart` | 改为复用并导出音频领域模型，保持既有测试导入兼容 |

阶段 3 当前保留点：

- `ReaderProvider.toggleTTS()` 暂时保留，避免一次性影响测试、快捷入口或后续未迁移 UI。
- 控播台仍从 `ReaderProvider` 读取书籍是否存在、章节标题与阅读进度；该部分属于阅读领域，不迁入音频状态机。
- 旧引擎仍通过 `onNeedPrefetch/onItemStarted/onItemFinished` 调用文本源；后续阶段再由 `TtsAudioNotifier` 直接持有 `TtsSentenceSource`。

### 3.4 验证记录

Codex 执行通道中曾出现 Dart 工具链启动卡住的问题，但用户本地终端验证正常。当前阶段已完成以下验证：

```powershell
dart --version
# Dart SDK version: 3.11.5 (stable) on "windows_x64"

dart format lib\features\audio\domain\tts_audio_state.dart lib\features\audio\providers\tts_audio_notifier.dart lib\features\audio\presentation\widgets\cyber_player_console.dart lib\shared\widgets\tts_error_listener.dart
# Formatted 4 files (2 changed)

flutter analyze --no-fatal-infos
# No issues found

flutter test test\features\reader\reader_flow_integration_test.dart
# 20/20 通过
```

测试输出中仍存在历史噪声：

```powershell
MissingPluginException(No implementation found for method getTemporaryDirectory ...)
MissingPluginException(No implementation found for method setLanguage ...)
```

该噪声未导致测试失败，后续可在测试桩中继续消除。

---

## 四、Codex 开发管理技能体系落地

### 任务目标

基于当前 Flutter/Riverpod、TTS 音频、2048 动效、中文文档和自动化收口流程，为 Codex 补齐项目级开发管理技能，让后续开发能按阅游工程纪律完成规划、实现、验证、记录、提交与推送。

### 已完成内容

- 新增 `.agents/skills/yueyou_task_steward/SKILL.md`，约束任务收口、开发计划、日志、README、提交与推送流程。
- 新增 `.agents/skills/yueyou_architecture_guard/SKILL.md`，约束 Clean Architecture 边界与 Riverpod 生命周期。
- 新增 `.agents/skills/yueyou_tts_audio_guard/SKILL.md`，固化 TTS 两步下载契约、音频状态机、缓存与降级规则。
- 新增 `.agents/skills/yueyou_flutter_performance_guard/SKILL.md`，固化 Flutter 动画、重绘隔离、视觉 token 和大文件 Isolate 规则。
- 新增 `.agents/skills/yueyou_test_ci_guard/SKILL.md`，固化静态分析、单测、平台插件 mock 与 CI 排查流程。
- 新增 `.agents/skills/yueyou_docs_encoding_guard/SKILL.md`，固化中文 Markdown、UTF-8、DevelopmentPlan 与日志维护规则。

### 验证计划

- [x] 完成本地技能文件结构创建。
- [ ] 检查技能元数据与目录结构。
- [ ] 运行轻量级文本检查。
