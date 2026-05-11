---
description: 职责过载评估与拆分 review 工作流，每次修改 ≥ 警戒线的 .dart 文件、新增公开类、或拆分 service/provider 时强制前后各走一遍
---

# 职责过载评估与拆分 Review 工作流

> 本工作流的目的是「**保护开发规范**」，不是「让文件变短」。抽出与否取决于职责是否真实混杂，不取决于行数是否超线。

## ⚠️ 核心原则：规范优先于合规

本工作流是阅游项目对抗「上帝类」与「职责过载」的强制评估流程。**行数阈值是「职责可能过载」的早期信号，不是拆分目标**。本流程走完后可能的正当结论：

- ✅ 职责真实混杂 → 按职责拆分
- ✅ 职责本来就紧密内聚 → **保留 warning 不动**也是合法结论

仅当出现「需要在超线文件追加新职责」或「达到硬上限 blocking」时，拆分才是必须动作。

AGENT.md 红线第 8 条与 `yueyou-file-size-guard` 技能联动触发本工作流。

## 🎯 触发条件（任一命中即必须走完本工作流）

- 即将修改的 `.dart` 文件当前行数 **≥ 警戒线**（阈值见 `AGENT.md` 职责过载信号阈值表）。
- 计划在已有文件中新增公开类、新增非私有方法且单类公开方法数将 ≥ 25。
- 计划将一个 `.dart` 文件拆为多个文件，或将私有 `_Foo` 抽出改为 public。
- 计划修改当前已超线文件（需要判断是否追加了新职责）。

## 1️⃣ 预检（开始 coding 之前）

### 1.1 行数与公开类数量基线

```powershell
# 在项目根目录 PowerShell 执行（替换为目标文件）
$f = 'lib/features/audio/services/tts_engine_service.dart'
@(Get-Content -LiteralPath $f).Count

# 公开类（非 _ 开头）统计
Select-String -LiteralPath $f -Pattern '^(class|abstract class|enum)\s+[A-Z]' | Measure-Object | Select-Object -ExpandProperty Count
```

### 1.2 与阈值表比对

- 行数 < 警戒线 且 公开类 ≤ 3 → 绿灯，可继续；但**仍不得追加新公开类**让数量超 3，仍不得追加与文件现有职责无关的新职责。
- 行数 ≥ 警戒线 → 黄灯，**必须先走职责混杂度评估**（见 1.3 节），不得闭眼拆拆分也不得在文件上继续追加新职责。
- 行数 ≥ 硬上限 或 公开类 > 3 或 单类公开方法 > 25 → 红灯，**禁止合入业务变更**。这些阈值针对「上帝类」反模式本质特征，超过则需先做拆分 PR。

### 1.3 职责混杂度评估（超警戒线必走）

在任务单中明列出该文件**当前承担的职责清单**（推荐 5–10 个狭义职责，例如「状态机推进 / 双轨道泵 / 缓冲填充 / 本地降级 / 状态映射」），逐个问 3 个问题：

1. 这个职责能否独立语言（3 句话说清）描述其输入 / 输出 / 副作用？
2. 抽出后能否被独立 mock 测试，而不需要构造一个完整的 Riverpod 容器？
3. 抽出是否会引入循环依赖、 > 8 个 callback、或破坏生命周期链？

**评估后 3 种合法结论**：

- **拆**：职责 1–2 、问题 3 = No → 按职责拆，进入 2–5 节强制流程。
- **不拆**：问题 1 难以拆开（职责互相紧密内聚，例如双轨道泵与缓冲管理）→ 保留 warning，**在任务单记录「为何不拆」的论证**。
- **抽出何类合适**：如果某些职责能拆、某些不能，先拆能拆的，保留不能拆的；可多轮 PR。

### 1.4 调用技能

```text
使用 yueyou-file-size-guard 技能输出当前文件的拆分 review checklist
```

### 1.5 输出 PR 启动 review 记录

将以下五项写入 `DevelopmentPlan/YYYYMMDD_XXX.md` 当日任务单：

1. 目标文件 + 当前行数 + 阈值差距
2. **职责清单**（上述 1.3 节产出）
3. **拆分动机**：哪些职责需要拆 / 哪些不拆 / 为何不拆
4. 计划拆分方案（职责拆分方法 × 抽出文件列表）
5. 是否需要 `export ... show ...` 兼容

## 2️⃣ 拆分原则速查（编码阶段）

- **四象限拆分法**：接口 / 数据模型 / 适配器实现 / 业务编排，按象限各放一个文件。
- **私有改 public 必须 export 兼容**：原文件保留 `export 'xxx.dart' show Foo, Bar;`，确保 `import 'tts_engine_service.dart'` 处不需要改。
- **禁止 `part` / `part of`**：这种方式只是把行数隐藏，不算真正拆分，不允许用来规避门禁。
- **测试 import 同步、断言不动**：拆分只允许调整测试文件的 `import` 路径，不允许改 mock 行为或断言；如必须改，拆为独立 PR。
- **`CyberLogger` 的 tag 分组保留**：原 `tag: 'tts'` 等不可在拆分中丢失或改名，否则破坏既有日志聚合。
- **Riverpod 生命周期保留**：`ref.onDispose`、`ref.listen`、`ProviderScope override` 不得在拆分中失效。

## 3️⃣ 中检（拆分代码完成时）

```bash
flutter analyze
dart scripts/ai_code_checker.dart
flutter test --concurrency=1
```

通过条件（任一失败即回滚或细化拆分）：

- `flutter analyze` 零错误零警告。
- AI 工程门禁通过（包括 `FileSizeRule`）。
- 全量测试通过；受影响测试只允许改 `import` 路径。

## 4️⃣ 后检（PR 提交前）

### 4.1 阈值回归

```powershell
$f = 'lib/features/audio/services/tts_engine_service.dart'
@(Get-Content -LiteralPath $f).Count
```

- 主文件行数应明显下降，且新生成文件均应位于警戒线下方。
- 单文件公开类 ≤ 3、单类公开方法 ≤ 25。

### 4.2 走 senior review

```text
使用 /review 工作流做 senior 视角复查
```

将 `/review` 工作流输出的结论附在 `DevelopmentPlan/` 当日任务单末尾。

### 4.3 收口检查清单

- [ ] 行数 / 公开类 / 公开方法均回到阈值内
- [ ] 受影响测试仅调整 import，未改断言
- [ ] 无新增 `part` / `part of`
- [ ] 原文件用 `export ... show ...` 做了向后兼容（如有私有改 public）
- [ ] `CyberLogger` tag 分组保留
- [ ] Riverpod `ref.onDispose` / `ref.listen` 链未破坏
- [ ] 任务单已更新 PR review 结论
- [ ] `development_log.md` 已追加
- [ ] `README.md` 已评估是否需要更新

## 5️⃣ 失败处理

- **行数仍超阈值**：拆为更细的 PR，遵循"接口/模型 → 适配器 → 核心"分批。
- **测试断言被迫修改**：本次拆分含语义变更，拆为独立 PR 并补充测试。
- **公开类数量仍 > 3**：识别仍未抽离的子职责，再分一个文件。
- **影响 Riverpod 生命周期**：回滚，改为先抽接口再做实现迁移的两步走方案。

## 📋 PR review 结论模板（粘贴至当日 DevelopmentPlan）

```markdown
## PR-X review 结论

- **拆分动机**：清晰列出本次拆出的是哪些职责、为何要拆（职责边界变化：原文件 6 职责 → 4 职责 + 新文件 2 职责）
- **可测性变化**：新抽出的单元能否独立 mock？是否减少了 Riverpod 容器构造需要？
- **依赖方向**：domain ← providers ← services 是否保持单向无环？有无 callback 数量过多的可疑调动（例如 > 8 个 callback 提示过度解耦）？
- **变更影响面收敛**：受影响测试个数、断言是否修改、是否需要同步新门禁规则
- **行数变化**（仅作附属信息、不作 KPI）：A.dart 1387 → 1180；新增 B.dart (≈ 80)
- **阈值合规**（信号层面）：✅ / ⚠️ / ❌（附超线文件列表）
- **AI 门禁**：通过 / 失败原因
- **senior review 发现**：……（来自 /review 工作流）
- **遗留 / 待改进**：……
```

> 模板原则：拆分动机 / 可测性 / 依赖方向 / 影响面为首要评估项，行数变化仅作附属。若仅能写出「行数变化」而不能说清「职责边界变化」，为闭眼拆拆分的可疑信号。

## 🔗 相关资产

- 红线：`.windsurf/rules/AGENT.md` 第 8 条
- 技能：`.agents/skills/yueyou-file-size-guard/SKILL.md`
- 阈值常量：`scripts/ai_checks/thresholds.dart`
- 检查规则：`scripts/ai_checks/rules.dart` 的 `FileSizeRule`
- 回归测试：`test/scripts/ai_code_checker_test.dart`
