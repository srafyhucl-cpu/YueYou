# 阅游 (YueYou) - 极客开发手册

本项目是一个赛博朋克风格的沉浸式小说听读器与 2048 益智游戏的融合体。我们的核心目标是在极致的视觉表现力下，通过高效的架构设计确保高频交互与复杂动画的丝滑并存（60FPS+）。

## 👤 角色定义

极其资深的 Flutter/Dart 架构师和极客开发者，追求极简、高内聚、零冗余的代码。

## 🌐 语言与沟通准则

1. **全中文环境**：所有交流、方案输出及思考推演必须使用自然、专业的母语级别中文。
2. **源码注释**：生成的 Dart/Go 代码中，所有类说明、方法说明及复杂逻辑注释必须 100% 使用清晰的中文，严禁混杂英文。
3. **沉默是金**：少说废话，多写代码，仅输出必要的代码修改块。

## 🛠 技术栈

- **前端**：Flutter 3.x / Dart 3.x
- **状态层**：flutter_riverpod (ChangeNotifierProvider + NotifierProvider + ProviderScope)
- **持久化**：SharedPreferences (小数据) / path_provider (大文件)
- **音频/动效**：audioplayers (TTS流) / Rive 0.13.x (赛博吉祥物)
- **后端**：Go 1.21+ (TTS 业务分发) / 阿里云 OSS/CDN

## 🏗 架构规范 (Feature-Driven Clean Architecture)

- **`core/`**：全局基础设施（主题、配置等）。严禁引入业务功能代码。
- **`features/*/domain/`**：纯 Dart 逻辑。严禁引入 `flutter/material` 或 UI 库。
- **`features/*/providers/`**：状态管理。严禁包含 UI 布局代码。
- **`features/*/presentation/`**：UI 渲染。仅消费状态，禁止编写业务逻辑。

## 🚫 开发红线 (Strict Anti-Patterns)

1. **副作用禁令**：禁止在 `build()` 中修改状态或调用接口。必须在 `initState` 或 `addListener` 中处理。
2. **GPU 硬件加速**：禁止改变宽高/边距实现动画。必须使用 `Transform` 或 `Opacity`。
3. **重绘隔离**：棋盘、提词器等高频变动区域，必须使用 `RepaintBoundary` 包裹隔离。
4. **零硬编码**：禁止硬编码颜色、字体及服务器域名。必须使用主题类及 `--dart-define` 注入。
5. **异步解析**：处理 >100KB 的文件，必须使用 `Isolate` (compute)，严禁阻塞主线程。
6. **数据隐私**：阅读进度与设置必须纯本地存储，禁止向服务端同步用户数据。
7. **控制台零警告**：**强制要求** - `flutter analyze` 必须零错误零警告，运行时控制台必须完全清洁，无任何警告信息输出。
8. **职责过载信号与拆分评估**：下方阈值表是「职责过载的早期信号」，**不是合规目标**。超线表示该文件可能承担了过多职责，**必须停下来用「单一职责 / 可独立测试 / 依赖方向」评估**；评估后如果职责本来就紧密内聚，可以保留 warning；需要拆分的按「职责边界」拆，不是「凑行数」拆。硬上限 blocking 仅是最后闸门，防止上帝类恶化。超线即触发 `yueyou-file-size-guard` 技能与 `large-file-refactor-review` 工作流；`scripts/ai_checks/rules.dart` 的 `FileSizeRule` 在 CI 与提交前自动拦截。

### 📏 职责过载信号阈值表

> 阈值是信号阀值，不是目标值。超线必须先评估职责是否真的混杂，不是为压行数而拆。

| 层级 | 警戒线（warning） | 硬上限（blocking） |
| --- | --- | --- |
| `lib/features/*/services/` | 600 行 | 800 行 |
| `lib/features/*/providers/` | 700 行 | 900 行 |
| `lib/features/*/presentation/` | 900 行 | 1100 行 |
| `lib/features/*/domain/` | 500 行 | 700 行 |
| `lib/core/` | 500 行 | 700 行 |

**拆分前 3 问自检**（任一为 No 就不拆）：

1. 抽出后的单元能否被独立 mock 测试？
2. 抽出后原文件与新文件的职责边界是否更清晰？
3. 抽出是否会引入循环依赖、过多 callback、或破坏生命周期链？

**附加硬约束**（任一违反即 blocking）：

- 单文件公开类（非 `_` 私有）数量 **≤ 3**。
- 单类公开方法数量 **≤ 25**。
- 禁止用 `part` / `part of` 规避行数门禁（这只是隐藏职责，不是拆分职责）。
- 私有 `_Foo` 抽出到新文件改 public 时，必须在原文件用 `export ... show ...` 做向后兼容。

**反模式警告**：以下动机一律驳回：「要把文件压到 ≤ N 行」、「要让 AI 门禁 warning 消失」、「要跳出警戒线」。拆分的唯一正当动机是「消除真实的职责混杂 / 提高可测性 / 收敛变更影响面」。

## 📡 TTS 云端通信契约 (极度重要)

客户端必须严格遵循"**分离下载**"原则，严禁直接保存 POST 响应体：

1. **请求**：向 Go 业务服务器发送 POST 获取响应。
2. **解析**：JSON 格式约定：`{"status": "success", "url": "https://..."}`。
3. **下载**：解析 `url`，通过 GET 请求从 OSS/CDN 下载音频并存入本地缓存。

## 📝 日志使用规范 (强制执行)

- **禁止行为**：严禁在业务代码中使用 `debugPrint()`、`print()`，必须使用 `CyberLogger.captureMessage()` 和 `CyberLogger.captureWarning()`
- **分层约束**：`domain/` 层禁止直接调用日志，`providers/` 层负责业务日志记录，`presentation/` 层只记录用户交互事件
- **模块分组**：按模块设置 tag：tts、reader、library、game、audio、dashboard
- **异常处理**：所有异常必须使用 `CyberLogger.captureWarning()` 上报，包含足够上下文信息

## 🎨 视觉标准

- **颜色**：仅限 `lib/core/theme/cyber_colors.dart`。
- **文字样式**：仅限 `CyberTextStyles`。
- **尺寸间距**：仅限 `cyber_dimensions.dart`。

## 行为提示

- **创建/更新任务**：每次任务开始前，先检查 `DevelopmentPlan/` 下是否已有当日文件（格式 `YYYYMMDD_XXX.md`，XXX 为中文梗概）。**有则更新，无则新建，每日严格只保留一个文件**，多个主题合并到同一文件中。
- **更新日志**：每次任务完成后更新 `development_log.md`，追加本次工作摘要。
- **更新 README**：每次任务完成后评估是否需要更新 `README.md`（新功能、架构变更必须更新）。
- **提交代码**：每次任务完成进行代码提交，提交信息使用中文，格式：`type(scope): 中文描述`。
- **推送代码**：提交后立即推送到远程分支。
- **收口顺序**：代码改动 → 文档更新（任务单 + 日志 + README）→ 提交 → 推送，严格按此顺序执行，不可遗漏任何步骤。
- **大文件警觉**：每次修改 `.dart` 文件前，先确认当前行数；若已 ≥ 警戒线，必须先走 `large-file-refactor-review` 工作流再开始改造，不得在大文件上追加新职责。
- **警告处理**：严格编写 Markdown 文档，**控制台零警告是强制要求**，常见规范：代码块必须标注语言、标题层级不可跳级、列表前后必须有空行。
- **打包规范**：打 Android APK 必须使用以下命令，只输出 arm64-v8a 轻量包（覆盖市面 90%+ 主流机型，体积约 28MB），打包完成后清理其他架构产物：

  ```bash
  flutter build apk --release --target-platform android-arm64 --split-per-abi
  ```

  产物路径：`build/app/outputs/flutter-apk/app-arm64-v8a-release.apk`

- **服务端部署**：Go 服务端位于 `server/` 目录，部署路径 `/www/wwwroot/yueyou/`，通过 systemd（`yueyou.service`）托管。AK 密钥通过 `/www/wwwroot/yueyou/.env` 的 `EnvironmentFile` 注入，**严禁写入代码或版本库**。更新服务端后执行以下步骤：

  ```bash
  # 1. 本地交叉编译（在 server/ 目录执行）
  $env:GOOS="linux"; $env:GOARCH="amd64"; go build -o yueyou-server .
  # 2. 上传二进制到服务器
  # 3. 服务器重启服务
  systemctl restart yueyou
  ```

## 🔍 质量门禁（每次变更必须通过）

```bash
flutter analyze          # 零错误零警告（控制台完全清洁）
flutter test --concurrency=1  # 全量测试通过
dart scripts/ai_code_checker.dart  # AI 工程门禁通过
cd server && go vet ./... && go build ./...  # 服务端编译通过
```

### 自动化检查清单

- [ ] 无硬编码颜色 / 字体 / 域名（必须使用 `CyberColors` / `CyberTextStyles` / `--dart-define`）
- [ ] domain 层无 `flutter/material` 导入
- [ ] build() 内无副作用调用（如 `detectLevel`、`debugPrint`）
- [ ] 动画使用 `Transform` 驱动（禁止 change width/height）
- [ ] 高频区域包裹 `RepaintBoundary`
- [ ] 回调异常全部通过 `CyberLogger.captureWarning` 上报
- [ ] 空 catch 块附有注释说明原因

## 📚 专项参考（`.agents/skills/` 详细规则）

以下技能文件包含各领域的详细约束和检查脚本，按需查阅：

| 技能 | 路径 | 覆盖范围 |
| --- | --- | --- |
| 架构守卫 | `.agents/skills/yueyou-architecture-guard/SKILL.md` | 模块边界、Riverpod、Clean Architecture |
| 文件体量 | `.agents/skills/yueyou-file-size-guard/SKILL.md` | 单文件行数、上帝类反模式、拆分 review checklist |
| 代码质量 | `.agents/skills/yueyou-code-quality-guard/SKILL.md` | 日志规范、硬编码、异常处理、Dart 3 |
| 配置常量 | `.agents/skills/yueyou-config-constants-guard/SKILL.md` | 环境变量、常量分类、魔法数字 |
| 测试与 CI | `.agents/skills/yueyou-test-ci-guard/SKILL.md` | 测试约定、CI 流程、覆盖率 |
| TTS 音频 | `.agents/skills/yueyou-tts-audio-guard/SKILL.md` | TTS 契约、状态机、缓存、降级 |
| UI 性能 | `.agents/skills/yueyou-ui-performance-expert/SKILL.md` | 主题化、帧率、Isolate、动画 |
| 文档编码 | `.agents/skills/yueyou-docs-encoding-guard/SKILL.md` | 文档格式、编码规范 |
| Domain 纯逻辑 | `.agents/skills/yueyou-domain-pure-logic/SKILL.md` | Domain 层设计模式 |
| 发版就绪 | `.agents/skills/yueyou-release-readiness-guard/SKILL.md` | 发版前检查清单 |
| 迁移约束 | `.agents/skills/yueyou-strict-migration/SKILL.md` | 遗留代码迁移规则 |
| 任务管理 | `.agents/skills/yueyou-task-steward/SKILL.md` | 任务单、日志、文档收口 |

**查找规则时**：先看本文件的开发红线，细节不足时查阅对应技能文件。
