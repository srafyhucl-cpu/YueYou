# 阅游测试覆盖率评估报告（发版前体检）

**生成日期**: 2026-05-08 | **基线 commit**: `ab77f92` (`origin/yueyou_test`)

> 数据生成命令：`flutter test --coverage` → `python scripts/parse_lcov.py`
>
> 全量结果原始数据：`coverage/coverage_summary.txt`

## 一、总体数据

| 指标 | 数值 |
| --- | --- |
| 测试文件总数 | **34** 个（其中 6 个 widget 测试） |
| 单元测试用例数 | **484** 通过 / **5** 跳过 / **0** 失败 |
| Dart 行覆盖率 | **53.78%**（2782 / 5173 行） |
| 已覆盖文件数 | **52** / 实际 lib 内 .dart 文件总数 ≈ 60+ |
| `flutter analyze` | ✅ 零错误零警告 |
| `dart scripts/ai_code_checker.dart` | ✅ 阻断 0 / 警告 0 |

整体覆盖率 **53.78%** 不算高，但需要区分"必须覆盖"和"UI 不必单元测覆盖"两类——表层的 `presentation/` 视图层是导致比例偏低的主因。下面按业务重要性分级评估。

## 二、模块覆盖率（按覆盖率升序）

| 模块 | 命中/总 | 覆盖率 | 评估 |
| --- | --- | --- | --- |
| `lib/features/dashboard` | 1/246 | **0.41%** | ⚠️ UI 层为主，但聚合多 Provider 的关键容器，建议至少补 1 条 smoke widget test |
| `lib/main.dart` | 4/89 | **4.49%** | ⚠️ 启动 + 隐私弹窗 + 生命周期，难单测但风险高 |
| `lib/features/settings` | 74/418 | **17.70%** | ⚠️ Provider 层 93% 已达标；隐私弹窗与设置页 UI 几乎裸奔 |
| `lib/core/constants` | 1/5 | 20% | 常量文件，覆盖率不重要 |
| `lib/features/library` | 200/476 | **42.02%** | ⚠️ Provider/Service 已覆盖；导入按钮、书库页 UI 几乎裸奔 |
| `lib/shared/widgets` | 84/196 | **42.86%** | ⚠️ CyberToast 91% 已达标；Modal/Dialog/Listener 全 0 |
| `lib/core/config` | 1/2 | 50% | 配置常量，不需要测 |
| `lib/features/audio` | 662/1288 | **51.40%** | ⚠️ TtsEngineService 64%、TtsAudioNotifier 仅 42% |
| `lib/features/update` | 33/62 | 53.23% | 已合理 |
| `lib/features/reader` | 468/693 | 67.53% | ✅ 合理水位 |
| `lib/features/game_2048` | 844/1187 | 71.10% | ✅ 合理水位 |
| `lib/core/database` | 200/258 | 77.52% | ✅ 良好 |
| `lib/core/utils` | 201/244 | 82.38% | ✅ 良好 |
| `lib/core/theme` | 9/9 | **100%** | ✅ 完美 |

## 三、零覆盖文件清单（必须人工评估）

| 文件 | 行数 | 风险评估 | 是否需要补测 |
| --- | --- | --- | --- |
| `lib/features/audio/presentation/widgets/neon_progress_painter.dart` | 55 | 自定义 CustomPainter，仅视觉 | ❌ 不需要（视觉测试用截图） |
| `lib/shared/widgets/tts_error_listener.dart` | 41 | 监听 TTS 错误并 Toast | ⚠️ **建议补**：错误节流、降级提示场景 |
| `lib/shared/widgets/cyber_confirm_dialog.dart` | 34 | 通用确认弹窗 | ⚠️ **建议补**：onConfirm/onCancel 路径 |
| `lib/shared/widgets/cyber_modal.dart` | 29 | 通用模态框 | ⚠️ 建议补 1 条 smoke 测试 |
| `lib/features/audio/presentation/widgets/voice_waveform.dart` | 24 | 波形绘制 | ❌ 不需要 |
| `lib/core/config/app_info_config.dart` | 1 | 全是 const | ❌ 不需要 |
| `lib/features/settings/constants/settings_texts.dart` | 1 | 全是 const | ❌ 不需要 |

## 四、低覆盖率（< 30%）的"高风险"文件清单

| 文件 | 覆盖率 | 业务重要性 | 必要性 |
| --- | --- | --- | --- |
| `dashboard_screen.dart` | 0.41% | ⭐⭐⭐ 主入口聚合页 | 🔴 **强烈建议补 smoke widget test** |
| `library_screen.dart` | 0.87% | ⭐⭐⭐ 书库主页 | 🟡 建议补：删书确认 / 空态 / 列表渲染 |
| `settings_screen.dart` | 1.85% | ⭐⭐ 设置页 | 🟡 建议补：音色选择 / TTS 测试连接 |
| `cyber_import_button.dart` | 2.22% | ⭐⭐⭐ 涉及 cancelImport / 异步 | 🔴 **建议补 dispose 时取消导入路径** |
| `privacy_agreement_modal.dart` | 2.67% | ⭐⭐ 合规必经 | 🟡 建议补：同意 / 拒绝 → SystemNavigator.pop |
| `main.dart` | 4.49% | ⭐⭐⭐ 应用启动 | 🟡 建议补：隐私拒绝退出、生命周期 hidden→paused |
| `cyber_player_console.dart` | 5.10% | ⭐⭐⭐ 控播台主组件 | 🟡 已有 5 条 `resolveNovelTitle` 用例，UI 部分仍 0 |
| `board_mascot.dart` | 22.92% | ⭐⭐ 装饰动画 | ❌ Rive 渲染，不必测 |
| `tts_audio_notifier.dart` | **42.18%** | ⭐⭐⭐⭐⭐ 核心音频状态机 | 🔴 **必须补**：见 §六 |

## 五、现有测试中的"无效 / 弱断言"用例审计

### 5.1 跳过的测试（1 条）

| 文件:行 | 跳过原因 | 处理建议 |
| --- | --- | --- |
| `tts_engine_service_test.dart:606-607` | "空闲超时逻辑已迁移到 TtsAudioNotifier" | ✅ 合理；可彻底删除该 test 而非 skip，避免误导 |

### 5.2 弱断言用例（仅 `returnsNormally`）

下列用例**只断言"不抛异常"**而无业务行为校验。短期可保留作 smoke，但长期应升级为有意义的断言：

| 文件 | 行号 | 用例 | 强化建议 |
| --- | --- | --- | --- |
| `default_book_service_test.dart` | 89-100 | `prefetchNextChapter` 的边界（99 / -1 / 0） | 应同时断言：边界时**未发起**网络请求 / 未命中缓存 |
| `game_provider_test.dart` | 390 | `addRandomTile` 棋盘满时 returnsNormally | 应断言：tile 数量保持 16 不变（已有第二行） |
| `game_provider_test.dart` | 532 | `move(left)` 默认音效路径 returnsNormally | 应断言：`onPlayMerge` 被调用 + 棋盘发生预期合并 |
| `game_provider_test.dart` | 925, 931 | `flushPersistState` 不崩溃 | 应断言：调用后 SharedPreferences 中确实写入了快照 |
| `tts_engine_service_test.dart` | 579 | `notifyUserActivity` returnsNormally | 应断言：内部计时器被重置（可观察 `_idleTimer != null`） |
| `sfx_service_test.dart` | 71 | `dispose` returnsNormally | 应断言：dispose 后再次 dispose 仍安全（已在 ambient 测过模式） |

**评估**: 全仓共 **18 条** `returnsNormally` 弱断言，**P1-5 cancelImport 幂等** 那 3 条是合理的（接口契约本就是"不崩溃 + 幂等"），其余 15 条建议在下一轮迭代中升级。

### 5.3 弱断言：仅 `isNotNull`

下列断言只验证非空：

| 文件:行 | 现状 | 建议 |
| --- | --- | --- |
| `theme_constants_test.dart:95` | `expect(greenGlow, isNotNull)` | 已有 `length == 2` 跟进，合理 |
| 其余 8 处 `isNotNull` | 均跟随后续字段断言（如 `result!.title`） | ✅ 合理，无需改 |

### 5.4 重复 / 冗余测试

| 重复模式 | 出现位置 | 建议 |
| --- | --- | --- |
| `cancelImport returnsNormally` × 3 | `file_import_service_test.dart:110-114` | ✅ 故意验证幂等，保留 |
| `dispose 不崩溃` × 2 + `多次 dispose 不崩溃` | `ambient_service_test.dart:130-148` | ✅ 故意验证幂等，保留 |
| `prefetchNextChapter` 边界 × 3 | `default_book_service_test.dart:88-101` | 🟡 可合并为参数化测试，用 `[99, -1, 0]` 数据驱动 |

## 六、必须补充的测试场景（按业务风险倒排）

### 6.1 🔴 强烈建议（发版前应补）

#### T-A. TtsAudioNotifier 的 pause→resume 完整闭环

**当前缺口**: 现有 T-1 仅验证"暂停时 mp3 文件保留"，未验证 resume 时**确实播放回原文件 + 不跳句**。

**新增用例**:

```text
test('暂停 → resume 必须播放同一文件，进度不前进')
test('暂停 → 切书 → resume 必须不重播旧句子（session 哨兵）')
test('暂停 → app 进入 hidden → resume 必须正常恢复')
test('快速 pause/resume 5 次连续切换不应丢句或重播')
```

**位置**: `test/features/audio/tts_audio_notifier_test.dart`

#### T-B. TtsAudioNotifier 自动降级链路

**当前缺口**: `_consecutiveFailures` 累加 → `_degradeToLocal()` → 网络恢复 → 退出降级，全链路无端到端用例。

**新增用例**:

```text
test('连续 N 次下载失败必须降级到本地 TTS 引擎')
test('降级后 ping 探测成功必须自动退出降级')
test('降级期间触发的 TTS 必须走 fallback 引擎')
```

#### T-C. ReaderProvider 章节边界与默认书自动推进

**当前缺口**: 默认书最后章 → 已是末章不再自动推进 → 边界提示，无完整链条用例。

**新增用例**:

```text
test('默认书读到第 100 章末尾必须停止自动推进并标记结束')
test('非默认书读到章末必须不触发 autoload 默认书章节')
test('jumpTo 跨章必须自动加载目标章节')
```

#### T-D. CyberImportButton.dispose 真的取消了 Isolate

**当前缺口**: P1-5 仅测 `cancelImport` 幂等。未验证导入中 dispose 时 Isolate 确实被 kill。

**新增用例**（widget test）:

```text
testWidgets('导入运行中 pop 页面，必须立即终止 Isolate')
```

### 6.2 🟡 中优先级（下一迭代）

#### T-E. Dashboard / Library / Settings 三大主屏 smoke widget test

每个主屏至少 1 条用例验证：

- 加载完成不抛异常
- 关键 widget（书架卡片 / 控播台 / 音色下拉）渲染存在

**位置**: 新建 `test/features/{module}/{screen}_test.dart`

#### T-F. TtsErrorListener 错误节流

**当前缺口**: P0-6 修复中提到"相同错误不重复通知"，但只在 ReaderProvider 层有用例（`相同 TTS 错误重复写入时 ReaderProvider 不重复通知`），UI 层 `TtsErrorListener` 节流（41 行 0 覆盖）未测。

**新增用例**:

```text
testWidgets('相同错误 1 秒内多次触发只弹 1 次 Toast')
testWidgets('降级 Toast 与错误 Toast 互斥')
```

#### T-G. 隐私弹窗合规链路

**当前缺口**: `privacy_agreement_modal.dart` 仅 2.67% 覆盖；P0-3 中"隐私拒绝退出"未单测。

**新增用例**:

```text
testWidgets('点击"不同意" → 调用 SystemNavigator.pop')
testWidgets('点击"同意" → 写入 hasAcceptedPrivacy=true 并继续启动')
testWidgets('navigatorKey null 时 5 次重试后兜底退出')
```

### 6.3 🟢 低优先级（迭代节奏内补）

| 测试主题 | 位置 | 说明 |
| --- | --- | --- |
| `CyberConfirmDialog` 确认/取消路径 | `test/shared/widgets/` | 简单 smoke |
| `CyberModal` 关闭手势 | `test/shared/widgets/` | 简单 smoke |
| `Mascot` Rive 资源加载失败回退 | `test/features/game_2048/` | 已有降级保护，可选 |

## 七、参数化与精简建议

### 7.1 可合并为参数化的重复用例

```dart
// 现状：3 条独立用例
test('does not throw at boundary chapter 99', () { ... });
test('does not throw for negative index', () { ... });
test('does not throw for valid chapter 0', () { ... });

// 建议：参数化
for (final idx in [99, -1, 0]) {
  test('prefetchNextChapter($idx) 边界路径不抛异常', () {
    expect(() => service.prefetchNextChapter(idx), returnsNormally);
  });
}
```

**收益**: 减少代码重复 + 后续新增边界值时改 1 处。

### 7.2 应删除而非 skip 的测试

`tts_engine_service_test.dart:605-606` 的 `skip` 用例应直接删除：

```dart
// 现状（skip 用例 5 条中的 1 条）：
test('空闲超时触发后应自动 setEnabled(false) ...',
    skip: '空闲超时逻辑已迁移至 TtsAudioNotifier 编排层 ...',
    () async { ... });

// 建议：完整删除（迁移目标已有对应测试在 tts_audio_notifier_test.dart）
```

**理由**: skip 用例长期挂靠会让维护者误以为"待修复"，实际已迁移。

## 八、发版前最低门槛建议

| 项 | 当前 | 发版前最低门槛 | 差距 |
| --- | --- | --- | --- |
| 全仓行覆盖率 | 53.78% | **≥ 60%** | +6 pp |
| `lib/features/audio` 覆盖率 | 51.40% | **≥ 65%** | +13 pp |
| `lib/features/audio/providers/tts_audio_notifier.dart` | 42.18% | **≥ 60%** | +18 pp |
| `flutter analyze` | ✅ 零警告 | 维持 | - |
| `flutter test` 失败数 | 0 | 维持 | - |
| AI 工程门禁 | ✅ 全过 | 维持 | - |

**到达建议门槛预估工作量**: 补 §6.1 中 4 类共约 **15-20 条用例**，2-3 个工作日。

## 九、附录：完整覆盖率原始数据

详见 `coverage/coverage_summary.txt` 与 `coverage/lcov.info`。HTML 报告生成方式（需 `genhtml`）：

```bash
genhtml coverage/lcov.info -o coverage/html
```

> 本文档由 `python scripts/parse_lcov.py` 自动统计 + 人工分析生成，下次发版前请重新执行评估并更新本文。
