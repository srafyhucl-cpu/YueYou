# 阅游测试覆盖率治理方案（互联网大厂正式标准）

**生成日期**: 2026-05-08 | **版本**: v1.0 | **维护**: AI 工程师 + 项目负责人共维

> 本文档是阅游项目对齐**互联网大厂客户端正式发版标准**的覆盖率治理纲领，包含：当前差距分析、强制门禁规则、分阶段达标路线图、可粘贴的验收命令集，以及配套的工具链支撑。

## 一、强制标准（不达标禁止合并 / 禁止发版）

### 1.1 行覆盖率门槛

| 模块类型 | 行覆盖率门槛 | 检查时机 |
| --- | --- | --- |
| **整体仓库** | ≥ **80%** | 每次 PR、每次发版 |
| **核心业务模块**（TTS / Reader / Game / Storage） | ≥ **90%** | 每次 PR、每次发版 |
| **P0 / P1 Bug 修复代码** | **100%**（每行新代码必须有对应回归用例） | PR 阶段强制核对 |
| **纯 UI / Painter / Animation** | **豁免**（不计入分母） | - |
| **常量文件 / 类型定义** | **豁免**（不计入分母） | - |

### 1.2 测试质量门槛

| 规则 | 阻断级别 |
| --- | --- |
| **禁止 `expect(..., returnsNormally)` 作为唯一断言**（必须配副作用断言或属于幂等性合约测试） | 🔴 阻断 |
| **禁止长期 `skip:` 用例**（业务变更后应**删除**或**重写**，不允许长期挂靠 ≥ 1 个迭代周期） | 🔴 阻断 |
| **禁止 `expect(true, isTrue)` 等空用例** | 🔴 阻断 |
| **禁止仅 `isNotNull` 单一断言**（必须跟随字段级断言） | 🟡 警告 |
| **测试方法名必须中文描述业务行为**（避免 `test1 / test2 / shouldWork`） | 🟡 警告 |
| **新增 P0/P1 修复必须配 `T-X` 编号回归用例并写入 development_log** | 🔴 阻断 |

### 1.3 控制台清洁

- `flutter analyze`：**零错误零警告**
- `flutter test`：**零失败**（skipped 计数应趋近于 0）
- `dart scripts/ai_code_checker.dart`：**阻断 0 / 警告 0**

## 二、当前现状（治理前 vs 治理后）

### 2.1 全仓覆盖率对比

| 指标 | 治理前 | 治理后 | 变化 | 大厂门槛 | 距门槛 |
| --- | --- | --- | --- | --- | --- |
| **整体行覆盖率** | 53.78% | **56.60%** | +2.82 pp | 80% | -23.40 pp |
| 测试用例数 | 484 | **494** | +10 | - | - |
| Skipped 用例 | 5 | **4** | -1（删除无效 skip） | 0 | -4 |
| 失败用例 | 0 | **0** | 维持 | 0 | ✅ |

### 2.2 核心文件覆盖率对比

| 文件 | 治理前 | 治理后 | 变化 | 门槛 | 状态 |
| --- | --- | --- | --- | --- | --- |
| `tts_audio_notifier.dart` | 42.18% | **66.31%** | **+24.13 pp** | 90% | 🟡 待提升 |
| `tts_error_listener.dart` | 0.00% | **78.05%** | **+78.05 pp** | 90% | 🟡 待提升 |
| `tts_engine_service.dart` | 64.64% | **67.68%** | +3.04 pp | 90% | 🟡 待提升 |
| `game_provider.dart` | 已高覆盖 | **96.61%** | 维持 | 90% | ✅ 达标 |
| `reader_provider.dart` | 67.22% | 67.22% | 持平 | 90% | 🟡 待提升 |
| `storage_service.dart` | 76.14% | 76.14% | 持平 | 90% | 🟡 待提升 |

### 2.3 模块覆盖率对比

| 模块 | 治理前 | 治理后 | 变化 |
| --- | --- | --- | --- |
| `lib/features/audio` | 51.40% | **59.86%** | **+8.46 pp** |
| `lib/shared/widgets` | 42.86% | **59.18%** | **+16.32 pp** |
| `lib/features/game_2048` | 71.10% | 71.44% | +0.34 pp |
| `lib/features/library` | 42.02% | 42.23% | +0.21 pp |
| `lib/features/dashboard` | 0.41% | 0.41% | 持平 |
| `lib/main.dart` | 4.49% | 4.49% | 持平 |

## 三、本轮治理交付清单

### 3.1 弱断言升级（4 处 → 副作用断言）

| 用例 | 治理前 | 治理后 |
| --- | --- | --- |
| `addRandomTile` 棋盘满时 | `returnsNormally` + 数量 | + ids 集合 + 总和不变 |
| `move(left)` 默认音效路径 | `returnsNormally` | + 验证合并值 + lastMoveNoMerge |
| `eliminateTileById(9999)` 不存在 id | `returnsNormally` + 棋盘第一项 | + tile 总数 + score 不变 |
| `flushPersistState` × 2 | `returnsNormally` | + SP 实际读出与棋盘一致 |

### 3.2 新增 T-X 回归用例（10 条）

| 编号 | 测试 | 文件 |
| --- | --- | --- |
| **T-A** | `pause → resume` 必须复用同一文件，不跳句、不新下载 | `tts_audio_notifier_test.dart` |
| **T-A 衍生** | `pause → stopAll → play` 必须重新下载 | `tts_audio_notifier_test.dart` |
| **T-B** | 连续 N 次下载失败必须自动降级到本地 TTS | `tts_audio_notifier_test.dart` |
| **T-B 衍生** | `refreshSession` 后降级标志必须归零 | `tts_audio_notifier_test.dart` |
| **T-C** | `cancelImport` dispose 路径必须同步快速完成（<100ms） | `file_import_service_test.dart` |
| **T-D × 5** | TtsErrorListener 节流（同时间戳去重 / 1s 节流 / 清空重置 / 不同错误各触发） | `tts_error_listener_test.dart`（新建） |

### 3.3 删除项

| 项 | 理由 |
| --- | --- |
| `tts_engine_service_test.dart:606` 的 `skip: '空闲超时逻辑已迁移...'` | 长期挂靠误导维护者，对应回归已迁移到 `tts_audio_notifier_test.dart` |

## 四、CI 门禁规则（待落地）

### 4.1 GitHub Actions 阻断脚本（建议追加到 `.github/workflows/flutter-ci.yml`）

```yaml
- name: Run tests with coverage
  run: flutter test --coverage --reporter compact

- name: Parse coverage
  run: python scripts/parse_lcov.py --threshold 80 --top-low 0 > coverage_summary.txt
  continue-on-error: false

- name: Coverage gate (overall ≥ 80%)
  run: python scripts/check_coverage_gate.py --overall 80 --core 90
  # 不达标必须 exit 1 阻断 PR
```

### 4.2 待新增的 `scripts/check_coverage_gate.py`（强制门禁脚本）

> **本文档发布后由维护者实现**。脚本契约：
> - 解析 `coverage/lcov.info`
> - 校验全仓 ≥ `--overall` 阈值
> - 校验核心文件清单（`tts_audio_notifier.dart` / `tts_engine_service.dart` / `reader_provider.dart` / `game_provider.dart` / `storage_service.dart`）每个 ≥ `--core` 阈值
> - 校验**新增代码**（与 main 分支 diff）行覆盖率 = 100%
> - 任何不达标输出明细 + 退出码 1

### 4.3 PR 模板检查项（建议追加 `.github/PULL_REQUEST_TEMPLATE.md`）

```markdown
## 自检清单

- [ ] flutter analyze 零警告（粘贴最后一行输出）
- [ ] flutter test 零失败、skipped 数未增加
- [ ] 新增代码已配套 T-X 回归用例
- [ ] dart scripts/ai_code_checker.dart 阻断 0
- [ ] python scripts/parse_lcov.py：变更模块覆盖率未下降
- [ ] 本次 PR 是否新增 returnsNormally 弱断言？（如是必须说明合理性）
```

## 五、分阶段达标路线图

### 阶段 0：当前状态（已完成）

- 整体覆盖率：56.60%
- 核心 `tts_audio_notifier.dart`：66.31%
- 弱断言已清理 4 处，无效 skip 已删除
- T-A / T-B / T-C / T-D / T-E 已落地

### 阶段 1：发版可行版本（≥ 65% / 核心 ≥ 75%）

**预估工作量**：3-5 个工作日

**待补用例**：

| 用例 | 目标文件 | 预计提升 |
| --- | --- | --- |
| ReaderProvider `loadChapter` 失败重试链路 | `reader_provider_test.dart` | 67% → 75% |
| StorageService `loadGameState` JSON 解析异常分支 | `storage_service_test.dart` | 76% → 85% |
| FileImportService Isolate `_isolateEntryPoint` 失败路径 | `file_import_service_test.dart` | 56% → 70% |
| DefaultBookService 章节缓存失效 / 网络异常 | `default_book_service_test.dart` | 48% → 65% |
| TtsEngineService `playFile` 文件不存在路径 | `tts_engine_service_test.dart` | 67% → 75% |
| TtsAudioNotifier `_idleTimer` 触发 pause 路径 | `tts_audio_notifier_test.dart` | 66% → 80% |

### 阶段 2：商店上架版本（≥ 75% / 核心 ≥ 85%）

**预估工作量**：5-8 个工作日

**待补用例**：

- TtsEngineService `_RealHttpClient.download` 流式落盘成功 / 异常清理（P1-6 完整链路）
- ReaderProvider 章节级联跳转、错误恢复
- BookshelfProvider 删书后阅读记录清理
- UpdateService HTTP 异常分支
- `lib/main.dart` 隐私拒绝退出 / `hidden→paused` 生命周期

### 阶段 3：大厂正式版（≥ 80% / 核心 ≥ 90%）

**预估工作量**：8-12 个工作日

**待补用例**：

- Dashboard / Library / Settings 三大主屏 smoke widget test（每屏 3-5 条）
- CyberImportButton widget test（结合 `_FakeFilePicker` mock）
- CyberConfirmDialog / CyberModal smoke widget test
- 隐私弹窗"同意 / 不同意 / NavigatorKey 重试" 完整 widget test
- `_RealHttpClient` 真实 HttpClient 用 `MockClient` 覆盖

### 阶段 4：CI 强制门禁上线（持续维护）

- 落地 `scripts/check_coverage_gate.py`
- GitHub Actions 配置 PR 阻断
- 每月 review：覆盖率不得低于上次发版水位

## 六、可粘贴命令集

### 6.1 本地完整验收链路

```powershell
# Windows PowerShell
$env:PYTHONIOENCODING="utf-8"

# 1. 静态分析
flutter analyze --no-pub

# 2. 全量测试
flutter test

# 3. AI 工程门禁
dart scripts/ai_code_checker.dart

# 4. 覆盖率统计
flutter test --coverage
python scripts/parse_lcov.py --threshold 80 --top-low 30
```

### 6.2 仅看核心模块覆盖率

```powershell
$env:PYTHONIOENCODING="utf-8"
python scripts/parse_lcov.py --threshold 90 --top-low 50 |
  Select-String "tts_audio_notifier|tts_engine_service|reader_provider|game_provider|storage_service"
```

### 6.3 单文件回归验证（开发期高频使用）

```powershell
flutter test test/features/audio/tts_audio_notifier_test.dart --reporter compact
flutter test test/features/game_2048/game_provider_test.dart --reporter compact
flutter test test/shared/widgets/tts_error_listener_test.dart --reporter compact
```

### 6.4 HTML 覆盖率报告（需安装 lcov / genhtml）

```bash
genhtml coverage/lcov.info -o coverage/html
# 打开 coverage/html/index.html 查看交互式覆盖率报告
```

## 七、配套工具链

| 工具 | 路径 | 职责 |
| --- | --- | --- |
| `parse_lcov.py` | `scripts/parse_lcov.py` | 解析 lcov.info，输出模块/文件级覆盖率 |
| `fix_relative_imports.py` | `scripts/fix_relative_imports.py` | 统一 lib/ 内导入路径风格 |
| `ai_code_checker.dart` | `scripts/ai_code_checker.dart` | 全仓阻断/警告级规则扫描 |
| `ai_checks/rules.dart` | `scripts/ai_checks/rules.dart` | 工程门禁规则定义（包含 ProductionDomainDefaultRule） |
| **`check_coverage_gate.py`** | 待实现 | CI 阶段覆盖率强制门禁 |

## 八、风险与建议

### 8.1 已知风险

| 风险 | 现状 | 建议 |
| --- | --- | --- |
| **Dashboard 0.41% 覆盖** | 246 行核心聚合页几乎裸奔 | 阶段 3 强制补 smoke test |
| **`main.dart` 4.49% 覆盖** | 启动 + 隐私 + 生命周期 | 阶段 2 补关键路径 |
| **18 条原 returnsNormally** | 已升级 4 条 | 阶段 1 继续升级剩余 14 条 |
| **核心文件 `tts_audio_notifier.dart` 仍 66%** | 离 90% 门槛差 24 pp | 阶段 1 优先级最高 |

### 8.2 长期建议

1. **每周一次** 覆盖率 review：CI 自动跑 `parse_lcov.py`，对比上周数据，下降必须给出原因
2. **每月一次** 弱断言巡检：grep 全仓 `returnsNormally` / `isNotNull`，新增条目必须 review
3. **每次发版** 覆盖率快照存档：`docs/testing/COVERAGE_HISTORY/YYYYMMDD.md`

## 九、附录

### 9.1 大厂参考标准对标

| 标准 | 阅游当前 | Google Flutter 团队 | 阿里巴巴客户端 | 字节跳动客户端 |
| --- | --- | --- | --- | --- |
| 整体行覆盖率 | 56.60% | ≥ 80% | ≥ 80% | ≥ 80% |
| 核心模块覆盖率 | 66.31%（tts_audio_notifier） | ≥ 90% | ≥ 85% | ≥ 90% |
| Bug 修复代码覆盖 | 已配 T-X 回归 | 100% | 100% | 100% |
| 弱断言 | 已清理 4/18 | 严格禁止 | 严格禁止 | 严格禁止 |

### 9.2 历史变更

| 日期 | 版本 | 变更 |
| --- | --- | --- |
| 2026-05-08 | v1.0 | 首版发布，治理基线建立 |

---

> 本文档是 **强制性** 项目质量纲领。任何 PR 不达标必须修复后再合并；任何发版不达标必须修复后再提审。
