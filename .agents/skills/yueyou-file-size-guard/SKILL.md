---
name: yueyou-file-size-guard
description: 用于阅游项目防止上帝类与单文件膨胀的强制约束。当修改任何 .dart 文件行数 ≥ 警戒线、新增公开类、拆分 service/provider、或评估文件大小时使用。与 yueyou-architecture-guard 并列为最高优先级，超阈值强制触发 large-file-refactor-review 工作流。
---

# 阅游单文件体量与上帝类守卫

## 触发场景

- 修改任何 `.dart` 文件且当前行数 ≥ 警戒线。
- 新增公开类、新增公开方法可能使单类公开方法数 ≥ 25。
- 拆分 service / provider，或将私有 `_Foo` 抽出改 public。
- 修改当前已超线的存量文件（`tts_engine_service.dart`、`tts_audio_notifier.dart`、`reader_provider.dart` 等）。
- 评估某个文件是否需要拆分。

## 📏 单文件体量阈值（与 AGENT.md 单一来源）

| 层级 | 警戒线（warning） | 硬上限（blocking） |
| --- | --- | --- |
| `lib/features/*/services/` | 600 行 | 800 行 |
| `lib/features/*/providers/` | 700 行 | 900 行 |
| `lib/features/*/presentation/` | 900 行 | 1100 行 |
| `lib/features/*/domain/` | 500 行 | 700 行 |
| `lib/core/` | 500 行 | 700 行 |

附加硬约束（任一违反即 blocking）：

- 单文件公开类（非 `_` 私有）数量 **≤ 3**。
- 单类公开方法数量 **≤ 25**。
- 禁止用 `part` / `part of` 规避行数门禁。

## 🚫 上帝类反模式识别

满足以下任一条件即判定为上帝类，必须立刻进入拆分流程：

- 单类承担 **≥ 4 类职责**（如：网络 + 缓存 + 状态 + UI 协调 + 错误处理 同时存在）。
- 单类公开方法 ≥ 25 或 私有方法 ≥ 40。
- 单文件同时包含 ≥ 4 个公开类。
- 文件 import 同时跨越 3 个以上 feature 模块。
- 文件包含 ≥ 6 个抽象接口 + 实现类对（典型如 `tts_engine_service.dart` 当前形态）。

## 🧭 拆分四象限法

把一个膨胀文件按以下四个象限拆解，逐象限抽到独立文件：

1. **接口（abstract class）**：抽到 `<feature>/domain/<topic>_interfaces.dart`。
2. **数据模型（POJO / enum / Exception）**：抽到 `<feature>/domain/<topic>_models.dart`。
3. **适配器实现（与第三方库桥接）**：抽到 `<feature>/services/<topic>_adapters.dart`。
4. **业务编排（核心逻辑）**：保留在原文件或抽到 `<feature>/services/<topic>_<role>.dart`。

每个象限对应一个独立 PR 落地，禁止把四象限揉到同一 PR 一次性大爆炸。

## 🔧 向后兼容策略

- **私有改 public**：`_RealHttpClient` → `RealHttpClient`，新文件 `tts_http_client.dart` 内 public，原文件顶部加：

  ```dart
  export 'tts_http_client.dart' show RealHttpClient, RealTtsHttpClient;
  ```

  这样原 `import 'tts_engine_service.dart'` 处不需要改任何路径。

- **测试 import**：只允许同步 `import` 路径，不允许改 mock 行为或断言；如必须改，拆为独立 PR。
- **CyberLogger tag**：原 `tag: 'tts'`、`tag: 'reader'` 等不可在拆分中丢失或改名。
- **Riverpod 生命周期**：`ref.onDispose`、`ref.listen`、`ProviderScope override` 链不得断裂。

## ✅ 10 条拆分 Review Checklist（每次拆分 PR 必填）

- [ ] 行数已回归阈值内（主文件 + 新增文件均在警戒线下）
- [ ] 单文件公开类 ≤ 3
- [ ] 单类公开方法 ≤ 25
- [ ] 测试是否仍绿且未改断言
- [ ] 拆分后是否引入循环依赖（用 `dart analyze` + 人工检查）
- [ ] 是否破坏了 Riverpod `ref.onDispose` / `ref.listen` 链
- [ ] 是否破坏了 `CyberLogger` 的 tag 分组
- [ ] 拆出的私有类改 public 后，命名是否一致（去掉前导 `_`，无 typo）
- [ ] 是否新增了 `part` / `part of`（应禁止）
- [ ] 是否更新了 `DevelopmentPlan` 当日任务单 + `development_log.md`

## 🛠 检查方法（PowerShell）

```powershell
# 单文件行数
$f = 'lib/features/audio/services/tts_engine_service.dart'
@(Get-Content -LiteralPath $f).Count

# 公开类数量（顶层 class / abstract class / enum 且不以 _ 开头）
Select-String -LiteralPath $f -Pattern '^(class|abstract class|enum)\s+[A-Z]' | Measure-Object | Select-Object -ExpandProperty Count

# 触发 AI 工程门禁
dart scripts/ai_code_checker.dart
```

## 🔗 联动工作流

- 强制工作流：`large-file-refactor-review`（预检 + 中检 + 后检）。
- 收尾 senior review：`/review`。
- 收口：`development-task-closure`。

## 🚧 当前已超线的存量文件（优先级排序）

| 文件 | 实测行数 | 阈值 | 处理 PR |
| --- | --- | --- | --- |
| `lib/features/audio/services/tts_engine_service.dart` | 1387 | 800 (blocking) | PR-A / PR-B / PR-C |
| `lib/features/audio/providers/tts_audio_notifier.dart` | 802 | 900 (warning) | PR-D |
| `lib/features/reader/providers/reader_provider.dart` | 721 | 700 (warning) | PR-E |
| `lib/features/settings/presentation/screens/settings_screen.dart` | 792 | 900 (warning) | PR-F（可选） |
| `lib/features/game_2048/presentation/widgets/square_board.dart` | 809 | 900 (warning) | PR-G（可选） |

修改这些文件时**必须先走本工作流**，且不得追加新职责。
