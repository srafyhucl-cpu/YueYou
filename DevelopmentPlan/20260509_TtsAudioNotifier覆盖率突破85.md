# 20260509 · TtsAudioNotifier 覆盖率攻坚（80.11% → 85.15%）

承接 `20260508_深度代码评审与回归修复.md` 的阶段 1 入口。本轮单点突破 `TtsAudioNotifier`，
覆盖率从 80.11% 推到 85.15%（+5.04pp），跨越 P4 门禁阈值 85%。

## 目标

| 模块 | 起点 | 终点 | 阶段 1 目标 | 状态 |
| --- | --- | --- | --- | --- |
| `TtsAudioNotifier` | 80.11% | **85.15%** (+5.04pp) | ≥ 85% | ✅ 跨越阈值 |
| 测试用例总数 | 23 | **27** (+4) | — | 全过 / 7 秒 |
| `flutter analyze` | 0 错 0 警 | 0 错 0 警 | 强制零警告 | ✅ |

## 关键改动

### 新增 fakeAsync / 真异步用例（4 条核心 + 2 条防御）

新增 `test/features/audio/tts_audio_notifier_test.dart`：

1. **`cycleSpeed` 在 Idle 状态防御断言**（非 fakeAsync）
   - 已被间接覆盖，作为字段级防回归。
2. **`stopAll` 保留 `playbackRate` 防御断言**（非 fakeAsync）
   - 验证 `_applyState(Idle)` 不重置 `_playbackRate`。
3. **`idleTimer` 到期 fire 必须自动调用 `pause()`**（fakeAsync）
   - **关键发现**：`settingsProvider` 是 `ChangeNotifierProvider`，`prev` 与 `next`
     引用同一个 `SettingsProvider` 实例，`prev?.idleTimeout != next.idleTimeout`
     **永远 false**（lib 侧 settings listener 已知缺陷，line 95-99 dead code）。
   - 改用 `engine.notifyUserActivity()` 触发 `ttsEngineProvider` listener
     → `_resetIdleTimer` → 创建 `Timer(1min)` → `elapse(61s)` fire 走 pause 路径。
4. **`setBackgroundTolerant(true)` 后 pump 必须进入 `_prefetchPaused` 退避**（fakeAsync）
   - 覆盖 `_prefetchRunner` line 317-320 的 2000ms 退避分支。
5. **T-B 衍生 2：降级激活后 sentenceSource 耗尽必须自动退出降级**（真异步）
   - 设 `_LimitedSentenceSource(returnLimit=6)`：与 `_refillBuffer` 的
     `filePath==null` 路径降级阈值齐平。
   - 触发降级后 `_pumpDegraded` 调 `nextTtsSentence` 返回 null
     → 命中 line 683-688 早返路径 → 自动退出降级。
   - **关键**：`request==null` 在 `pingServer` 之前早返，避免触发 dart:io
     真网络 3s 超时。
6. **T-B 衍生 3：`_pumpDegraded` 在 `pingServer` 可达时必须自动退出降级**（真异步）
   - 设 `_LimitedSentenceSource(returnLimit=999999)` 让 `_pumpDegraded`
     始终拿到非 null request。
   - **关键发现**：flutter_test 默认通过 `HttpOverrides` 注入 mock client，
     `response.statusCode=400 < 500` → `pingServer()==true` →
     命中 line 695-698 退出降级路径（日志可见 `[TTS] 网络已恢复，退出降级模式`）。

### 测试基础设施

- 新增 `_LimitedSentenceSource(returnLimit:)`：限定返回次数后返回 null 的可控
  句子源，专门用于驱动 `_pumpDegraded` 的不同分支。

## 关键稳定性踩坑

### 编辑工具批改 fakeAsync 块时结构损坏

第一次新增 `idleTimer` + `setBackgroundTolerant` 两条 fakeAsync 用例时，`edit`
工具误把 `});` 提前关闭整个 `group`，导致 6 条 test 掉到 `main()` 顶层 + 1
条 stopAll 测试体被截断、3 条用例重复。
**结论**：批量插入 fakeAsync 用例时，必须用结构化整段替换 + 立即重读验证。

### `_pumpDegraded` 真网络路径在测试环境的行为偏离

最初的 T-B 衍生 3 用例预期 `pingServer` **失败保持降级**，实际跑下来 mock
HttpClient 返回 400 status → `reachable=true` → `_pumpDegraded` **退出降级**。
**结论**：测试设计必须考虑 flutter_test 的 HttpOverrides 默认行为；与其追求
失败路径覆盖，不如反过来覆盖成功路径。

### `_degradeToLocal` 是 fire-and-forget

`_refillBuffer` 第 N 次失败后 `_degradeToLocal(request)` **未 await**，
`_isDegradedToLocal=true` 在多个 microtask hop 后才同步生效。
期间 `_prefetchRunner` 仍可能跑 1-3 次 `_refillBuffer`，导致 `nextCalls`
超过 returnLimit 的精确推算困难，硬编码 `>N` 断言不稳定，应放宽。

## lib 侧已知缺陷（未修复，已记录）

`@/lib/features/audio/providers/tts_audio_notifier.dart:95-99` 的 settings
listener 是 dead code：`SettingsProvider` 是 ChangeNotifier，notify 时 `prev`
与 `next` 引用同一对象，`prev?.idleTimeout != next.idleTimeout` 永远 false。
真实 idleTimer 触发依赖 `ttsEngineProvider` listener 路径（已工作）。
**后续治理**：将 listener 改为快照对比（保存上一次 `idleTimeout` 数值）。

## 下一轮入口

- **TtsAudioNotifier 85.15% → 90%**（可选）：补 `_onPlaybackComplete` 多分支 +
  `_copyStateWithRate` Playing/Error case + `_isPausedInterrupt`。
- **TtsEngineService 70.18% → ≥75%**（阶段 1 主线）：未覆盖集中在 `_RealHttpClient`
  实例化分支、初始化兜底、`pingServer` / `testConnection` 网络分支、
  `speakWithLocalTts` 降级链路。
- **FileImportService 56.00% → ≥75%**（阶段 1 主线）：Isolate 流式解析的边界与异常路径。

## 验收

| 项 | 指标 | 结果 |
| --- | --- | --- |
| `flutter test test/features/audio/tts_audio_notifier_test.dart` | 全过 | ✅ 27 / 0 失败 / 7 秒 |
| `flutter analyze` | 零错误零警告 | ✅ No issues found |
| `python scripts/coverage_focus.py --files lib/features/audio/providers/tts_audio_notifier.dart` | ≥ 85% | ✅ **85.15%** (321/377) |
