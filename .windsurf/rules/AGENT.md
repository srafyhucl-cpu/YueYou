---
trigger: always_on
---
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
8. **职责过载信号与拆分评估**：下方阈值表是「职责过载的早期信号」，**不是合规目标**。超线表示该文件可能承担了过多职责，**必须停下来用「单一职责 / 可独立测试 / 依赖方向」评估**；评估后如果列出的职责本来就紧密内聚（例如双轨道泵 + 缓冲管理），可以保留警戒线 warning；需要拆分的按「职责边界」拆，而不是「凑行数」拆。硬上限 blocking 仅是**最后闸门**，防止股股膏药的上帝类恶化。超线即触发 `yueyou-file-size-guard` 技能与 `large-file-refactor-review` 工作流；`scripts/ai_checks/rules.dart` 的 `FileSizeRule` 在 CI 与提交前自动拦截。

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
3. 抽出是否会引入循环依赖、过多 callback、或破坏已有生命周期链？

**附加硬约束**（任一违反即 blocking，这些针对「上帝类」反模式本质特征，非合规表演）：

- 单文件公开类（非 `_` 私有）数量 **≤ 3**（超过则一个文件同时控制多个顶层抽象，违反 SRP）。
- 单类公开方法数量 **≤ 25**（超过则接口面过大，使用方需记住太多调用口）。
- 禁止用 `part` / `part of` 规避行数门禁（这只是隐藏职责，不是拆分职责）。
- 私有 `_Foo` 抽出到新文件改 public 时，必须在原文件用 `export ... show ...` 做向后兼容，保证现有 `import` 不变。

**反模式警告**：以下动机一律驳回，不得作为拆分理由：

- 「要把文件压到 ≤ N 行」
- 「要让 AI 门禁 warning 消失」
- 「要跳出警戒线」

拆分的唯一正当动机是「消除真实的职责混杂 / 提高可测性 / 收敛变更影响面」。

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
- **职责过载警觉**：行数阈值是「职责可能过载」的早期信号，不是拆分目标。每次修改 `.dart` 文件前先确认行数（IDE 行号或 `Measure-Object -Line`）；若已 ≥ 警戒线，先走 `large-file-refactor-review` 工作流**评估职责**、不是闭眼拆拆分。评估后可能的结论：① 职责真实混杂 → 按职责拆分；② 职责本来就紧密内聚 → 保留 warning 不动。**不得在大文件上继续追加新职责**是硬约束，不受以上评估影响。
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

## 🛠 技能体系与工作流

### 技能调用优先级

1. **yueyou-architecture-guard** - 架构边界约束（最高优先级）
2. **yueyou-file-size-guard** - 单文件体量与上帝类反模式（与架构守卫并列，超阈值强制触发）
3. **yueyou-code-quality-guard** - 代码质量规范（含零警告检查）
4. **yueyou-config-constants-guard** - 配置常量管理
5. **yueyou-test-ci-guard** - 测试与 CI 规范
6. **yueyou-tts-audio-guard** - TTS 音频专项
7. **yueyou-ui-performance-expert** - UI 性能优化
8. 其他专项技能按需调用

### 工作流使用

- **code-standardization-check** - 代码规范化检查（强制零警告）
- **large-file-refactor-review** - 大文件治理与拆分 review（每次修改 ≥ 警戒线文件前/后必走）
- **development-task-closure** - 开发任务收口管理
- **environment-configuration** - 环境配置验证
- **skill-usage-guide** - 技能使用指南

### 验收标准

- [ ] `flutter analyze` **零错误零警告（控制台完全清洁）**
- [ ] 运行时控制台无任何警告信息输出
- [ ] 所有技能检查通过
- [ ] 工作流验收标准全部满足
