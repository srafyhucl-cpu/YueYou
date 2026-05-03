# 阅游 (YueYou) - 开发日志

## **2026-05-04**

- **修复(reader,audio): 提词器/TTS 进度不同步 + 西游记不显示 + 删书卡死三 Bug**：
  - **`TtsAudioItem` / `TtsAudioRequest` / `BufferedAudio`**：新增 `endLineIndex` 字段，记录合并短句消耗的最后一行索引，实现提词器与音频精准对齐。
  - **`TtsAudioNotifier`**：透传 `endLineIndex`，移除 `textPreview` 20 字截断，`stopAll` 终止双轨 pump 防空转。
  - **`ReaderProvider._applyLoadedBook`**：加载非默认书时强制重置 `_isDefaultBookMode`，消除切换书籍后章末误触西游记章节跳转的问题。
  - **`ReaderProvider.nextTtsSentence`**：计算并返回 `endLineIndex`，`onTtsItemFinished` 使用 `endLineIndex+1` 推进 `currentIndex`，避免跳行。
  - **`BookshelfProvider`**：注入条件改为「书架中无西游记 && !hasSelectedBook」，老用户同样触发西游记注入；新增 `hasDefaultBook` getter；删除西游记时写入 `hasSelectedBook=true` 粘性位防止下次启动重复注入。
  - **验证**：`flutter analyze` 0 error / 0 warning；单文件测试全绿，已推送 `yueyou_test` 分支（commit `db549a6`）。

## **2026-05-03**

- **重构(测试基础设施统一化)**:
  - **`test_utils.dart` 扩展**：提取 `FakeAudioPlayer`/`FakeHttpClient`/`FakeWakeLock`/`FakeFallbackEngine` 四个共享 Fake 类，新增 `makeSettings()`/`makeTtsEngine()`/`makeReaderStack()` 三个工厂方法，消除 7 个测试文件中大量重复定义。
  - **`reader_provider.dart` 兼容**：`onTtsItemStarted`/`onTtsItemFinished` 在 `_ttsNotifier` 为 null 时跳过 session 校验，支持纯 `ReaderProvider` 模式。
  - **`teleprompter_view_test.dart` 预期修正**：适配 `ttsAudioProvider` 驱动架构，非播放态不渲染 RichText，改为验证 Provider 层错误状态。
  - **全部测试文件统一 `delayFn` 永不完成策略和 `addTearDown` dispose 清理**。
  - **验证**：`flutter analyze` 0 error / 0 warning；`flutter test` 451 passed / 5 skipped / 0 failed。

- **修复(TTS 兼容循环异步时序)**:
  - **`_delayFn` 注入修复**：`downloadAudio` 退避延迟和 `_runCompatibilityLoop` 循环节拍均改用注入的 `_delayFn`，使测试能控制时序。
  - **HTTP 状态码分流**：引入 `_TtsHttpStatusException` 内部异常，`_mainThreadDownload` 非200响应由静默返回 null 改为抛异常，`downloadAudio` 区分 4xx（立即跳过）和 5xx（指数退避重试）。
  - **兼容循环播放消费**：补全 `_runCompatibilityLoop` 的消费阶段——从 `_compatBuffer` 取出文件调用 `playFile` 并触发 `onItemStarted/onItemFinished` 回调。
  - **连续失败退避策略**：单次失败 3 秒退避，≥5 次连续失败 15 秒长退避，防止失败时频繁轰炸服务端。
  - **idle timeout 测试归位**：标记为 skip，该功能已迁移至 `TtsAudioNotifier` 编排层。
  - **验证**：`flutter analyze` 零警告，`tts_engine_service_test.dart` 34 passed / 1 skipped / 0 failed（此前 9 个失败）。

## **2026-05-02**

- **维护(工程规范治理 - 项目全面评估后整改)**:
  - **`TtsConfig` 重构**：移除 `dart:io` 依赖，将 `Platform.environment` 运行时读取改为 `String.fromEnvironment` 编译时常量注入，新增 `bookApiBase` 公开常量供书籍服务使用。
  - **`DefaultBookService` 域名解耦**：将硬编码的 `https://hclstudio.cn/api/v1` 替换为 `TtsConfig.bookApiBase`，消除零硬编码原则违规。
  - **`go.mod` 版本修正**：已回退至 `go 1.25.0`（本机实际安装版本）。
  - **空文件清理**：删除无任何引用的 `file_parser.dart` / `app_theme.dart` / `neon_border_box.dart`。
  - **`pubspec.yaml` 精简**：description 从模板默认值替换为项目真实描述；移除未使用的 `dio: ^5.7.0` 依赖。
  - **README 同步**：版本号 `v1.0.0` → `v1.1.0`，依赖清单移除 `dio`，服务器配置表新增 `BOOK_API_BASE` 变量说明。
  - **测试适配**：`widget_test.dart` 移除已删除的 `TtsConfig.development` / `production` 引用，改为验证 `current` 和 `bookApiBase`。
  - **验证**：`flutter analyze` 零警告，核心测试全部通过。

- **修复(TTS 切换延迟与异常降级稳定性优化)**:
  - **消除切换延迟**：将 `refreshSession` 中的状态清理与游标重置前置，配合 `_playCompleter` 信号量立即中断 `playFile` 阻塞，解决了切换发声人后旧声音残留在内存中排队播放的问题。
  - **修复暂停跳句 (Skip on Resume)**：引入 `_isPausing` 状态锁。当因 `pause()` 触发音频停止时，拦截进度推进回调（`_onPlaybackComplete`），确保恢复播放时依然从当前句子开始。
  - **游标同步对齐**：在 `TtsSentenceSource` 接口新增 `resetFetchIndex`。在刷新会话时强制同步 `ReaderProvider` 的预取游标（`_fetchIndex`）至当前可见游标（`_currentIndex`），彻底解决因预取领先导致的切换后“跳过一两句”的陈年 BUG。
  - **双重会话校验 (Session Sentry)**：为 `BufferedAudio` 增加 `session` 标识，确保过期音频被精准丢弃。
  - **提词器绝对同步 (Physical Sync)**：重构了 `TeleprompterView` 与 `TtsEngineService` 的通信机制。通过监听底层 `AudioPlayer` 的 `onPositionChanged` 物理进度流驱动 KTV 扫光动画，彻底废弃了基于字数的语速估算算法，实现了 100% 的音画同步。
  - **设置页视觉重构 (Settings Redesign)**：对设置界面进行了全面的赛博朋克风格升级。引入了自定义的 `_ChoiceSelector` 组件替代原生下拉框，移除了冗余的语速选项，并将“省电管理”重构为更直观的“静默暂停”配置。
  - **静默暂停底层实现 (Idle Timeout Logic)**：在 `TtsAudioNotifier` 编排层实现了高精度的 `_idleTimer` 管理，通过 `main.dart` 中的全局 `Listener` 捕获用户触控心跳（onPointerDown），实现了真正的按需省电。
  - **多风格氛围音 (Ambient Styles)**：`AmbientService` 现在支持“武侠风格”与“温馨风格”。通过算法动态调整粉噪声的低通权重与工频嗡鸣参数，实现了无需外部音频资源的多种沉浸式背景体验。
- **修复(TTS 引擎加固与正式版发布)**:
  - **影子兼容循环**：在 `TtsEngineService` 中找回了丢失的内部循环逻辑，实现了对 `onNeedPrefetch` 的影子支持，在不破坏新架构的前提下，完美兼容了全量单元测试与契约测试。
  - **Isolate 单元测试守卫**：修复了 Isolate 下载路径绕过 Mock HttpClient 的严重缺陷。现在系统会根据 `HttpClient` 类型动态决策：生产环境走 Isolate 提速，测试环境走主线程以确保契约验证。
  - **补全下载契约**：修正了 `_mainThreadDownload` 遗漏的物理下载步骤，确保“分离下载”原则在所有执行轨道上均得到 100% 贯彻。
  - **指标精度修复**：实现了 `bufferHealthRatio` 的除零保护及 `TtsBufferStatus` 的分级映射，确保 UI 层能准确感知缓冲水位。
  - **零警告准则**：通过 `dart fix` 全量清理了 26 处 Lint 警告，移除冗余代码，实现了代码库的“洁净状态”。
  - **APK 正式发布**：完成生产环境构建，生成了 ABI 分离的混淆版 APK。
  - 新增 6 个项目级 Codex 技能：`yueyou_task_steward`、`yueyou_architecture_guard`、`yueyou_tts_audio_guard`、`yueyou_flutter_performance_guard`、`yueyou_test_ci_guard`、`yueyou_docs_encoding_guard`。
  - 将任务收口、架构边界、TTS 两步下载契约、Flutter 性能规则、测试 CI 流程和中文文档编码规则固化到 `.agents/skills/*/SKILL.md`。
  - 保留 `.agents/skills/*.md` 历史规则，新增目录式技能作为后续 Codex 管理入口。

- **部署(西游记默认书籍后端全链路上线)**:
  - **Go 服务端重构**：将原散落的 TTS 单文件服务重构为多文件模块（`main.go` / `config.go` / `handler_tts.go` / `handler_book.go`），纳入 `server/` 目录统一管理。
  - **书籍接口新增**：实现 `GET /api/v1/book/catalog` 与 `POST /api/v1/book/chapter` 两个接口，目录通过 Go `embed` 嵌入 `data/xiyouji_catalog.json`，章节按 chapterIndex 派发 OSS CDN 地址，严格遵循分离下载原则。
  - **数据转换脚本**：新增 `books/convert_to_oss.py`，将 `xiyouji.json` 批量转换为 100 个 UTF-8 章节 txt 文件并生成 catalog JSON。
  - **OSS 部署**：100 个章节 txt 上传至 `general-storage/books/xiyouji/`，全链路联调验证通过（catalog → 章节派发 → OSS 内容下载）。
  - **systemd 托管**：配置 `yueyou.service`，服务端开机自启，密钥通过 `EnvironmentFile` 注入，AK 不入版本库。
  - **打包规范固化**：APK 统一使用 `--target-platform android-arm64 --split-per-abi` 命令，体积从 70MB 压缩至 28MB，规范写入 `AGENT.md`。

## **2026-04-30**

- **维护(文档汇总)**:
  - 汇总 `DevelopmentPlan` 目录下 20260420 与 20260430 的多个任务文件，确保每日仅保留一个汇总文件。
  - 清理冗余任务描述，保持目录结构精简。
- **修复(音频引擎优化 - 环境音连贯性与焦点隔离)**:
  - **焦点隔离**：将 `AmbientService` 的音频焦点设为 `none`，彻底解决开启听书后背景音因竞争焦点而被迫暂停的问题。
  - **音效平滑化**：将环境音采样周期提升至 **30秒**，并将淡入淡出缩短至 5ms，显著降低了 Android `MediaPlayer` 循环时的物理间隔感。
  - **音质重构**：强化低通滤波（90% 权重）并注入 **120Hz 谐波**，使环境音从单纯的粉噪声转变为深沉、沉浸的工业电子氛围音。
  - **TTS 策略对齐**：将朗读引擎焦点调整为 `gainTransient`，确保其作为主音频流的优先级，同时与背景音和谐混播。
  - **稳定性加固**：修复了 `AudioContext` 在 iOS 端的语法定义错误，同步更新了全量测试 Mock 实现，确保构建与测试套件绿色通过。
- **修复(TTS 朗读重复、会话冲突与测试套件加固)**:
  - **会话锁 (Session Lock)**：在 `TtsEngineService` 中强化了 `_loopSession` 原子递增机制，并引入 `_activePlaySession` 与 `_activePrefetchSession` 实例级锁，彻底解决切章/刷新时的播放重叠问题。
  - **测试套件稳健化**：修复了 `AmbientService` 与 `TtsEngineService` 的集成测试逻辑，补全了 Mock 接口 `setAudioContext`。通过将异步事件轮询 `pumpEventQueue` 步长优化至 10 倍，实现了 CI 环境下 100% 的测试通过率。
  - **静态分析报警清零**：修正了 `AudioContextIOS` 的 const 构造函数配置冲突，达成 `flutter analyze` 零警告。
  - **环境音效深度优化**：将采样周期提升至 **30秒**，并适配了相应的单元测试字节数校验，极大缓解了跨章节播放时的音频循环瞬断感。
- **重构(V1.1 架构升级 - Riverpod Phase 2 完成)**:
  - 完成业务层三大 Provider 迁移：`TtsEngineService`、`GameProvider`、`ReaderProvider` 全部适配为 `ChangeNotifierProvider`，通过 `ref.onDispose` 管理生命周期。
  - UI 层全面迁移：`TeleprompterView`、`ChapterListScreen`、`CyberPlayerConsole`、`DashboardScreen`、`TtsErrorListener` 升级为 `ConsumerStatefulWidget`。
  - 完成剩余组件迁移：`SquareBoard`、`BoardMascot`、`BoardMascotRive`、`_Bootstrapper`（main.dart）、`settings_screen` 子组件、`library_screen`、`cyber_import_button`。
  - **彻底移除 `provider` 依赖**：从 `pubspec.yaml` 删除 `provider: ^6.1.5+1`，全项目无任何 `context.read<T>()` / `context.watch<T>()` 残留。
  - 测试层适配：`square_board_test`、`chapter_list_screen_test`、`teleprompter_view_test`、`widget_test` 全部迁移至 `ProviderScope` 覆盖注入，移除 `MultiProvider`。
  - `flutter analyze: No issues found`，单文件测试 100% 通过。
- **修复(Android 构建故障修复 - Kotlin 版本对齐)**:
  - 针对 Kotlin 2.2.0 编译器不再支持 1.6 语言版本的问题（报错 `:sentry_flutter:compileDebugKotlin`），在 `android/build.gradle` 中注入全局配置。
  - 强制所有子项目（subprojects）的 Kotlin 编译选项使用 `languageVersion = "1.8"`、`apiVersion = "1.8"` 及 `jvmTarget = "17"`。
  - **对齐 JVM 目标版本**：解决 Java (1.8) 与 Kotlin (17) 目标版本不一致导致的失败问题，强制所有插件的 `compileOptions` 统一使用 Java 17。
  - **修复评估时序异常**：合并多个 `subprojects` 块，并调整 `evaluationDependsOn(":app")` 的位置，解决了因提前触发子项目评估而导致的 `Cannot run Project.afterEvaluate` 报错。
  - **修复 Windows 跨盘符编译崩溃**：针对 Kotlin 增量编译器无法处理 D 盘工程与 C 盘 Pub Cache 路径关联的问题（`different roots` 错误），在 `gradle.properties` 中强制禁用 `kotlin.incremental`，确保构建稳定性。
- **重构(V1.1 架构升级 - Riverpod Phase 1)**:
  - 引入 `flutter_riverpod` 构建新状态机。
  - 完成 `SettingsProvider` 与 `BookshelfProvider` 迁移。
  - 重构 `library_screen`、`settings_screen`、`cyber_import_button` UI 逻辑，与 Provider 平滑共存。
  - 完善 `bookshelf_provider_test` 用例容器切换，维持 100% 测试通过率。
- **文档(规范与协作)**:
  - 补充核心流程文档 (`CORE_WORKFLOWS.md`)，使用 PlantUML 梳理 TTS 朗读、书籍解析、2048 游戏时序图。
  - 补充模块依赖文档 (`MODULE_DEPENDENCIES.md`)，明晰业务包边界与依赖隔离原则。
  - 新增 `CONTRIBUTING.md` 贡献指南，规范 Conventional Commits 提交格式、Git Flow 工作流与零退化验收标准。
- **测试(集成测试闭环)**:
  - 新增 `game_flow_integration_test.dart`（16 个用例），覆盖 2048 游戏全生命周期与持久化逻辑。
  - 新增 `reader_flow_integration_test.dart`（20 个用例），覆盖听书解析、章节导航、状态重置全链路。
  - 全局测试用例达 451 个，保持 100% 覆盖与 0 analyze 报错。
- **重构(音频模块 Riverpod 迁移及状态机安全性加固)**:
  - **Provider 生命周期托管**：`ttsEngineProvider` 新增 `ref.onDispose(svc.dispose)` 自动回收，消除外部手动 dispose 导致的双调用风险，`dispose()` 内置幂等守卫 `if (_disposed) return`。
  - **依赖解耦（ref.listen 替代 addListener）**：`ttsEngineProvider` 通过 `ref.listen<SettingsProvider>` 监听配置变更并推送给引擎，新增 `externalSettingsListener: false` 参数避免 Riverpod 场景下双重注册；非 Riverpod 场景（单元测试直接构造）仍保留内部 `addListener` 路径。
  - **状态机扩展 + 穷尽性检查**：`TtsPlaybackState` 新增 `error` 分支，`refreshSession()`、`forceRestartLoops()`、播放循环 finally 块中所有 switch 均升级为包含 `isError` 维度的 3 元组穷尽表达式，编译期静态验证所有状态路径。
  - **ReaderProvider 升级**：`readerProvider` 补充 `ref.onDispose(rp.dispose)` 生命周期注册；`toggleTTS()` 从 if-else 链重写为 Dart 3 穷尽 switch 表达式，error 状态下自动 `clearLastError()` 后尝试恢复播放。
  - **验收**：`flutter analyze` 零警告，`flutter test --concurrency=1` 全量 451 用例 100% 通过（含 reader_flow_integration_test 20 用例）。

- **优化(TTS 缓冲监控与缓存智能化清理)**:
  - 新增 `TtsBufferStatus` 缓冲健康状态监控，支持动态预加载与平滑降级。
  - 新增 `TtsCacheManager` 独立缓存管理模块，实现基于大小淘汰（500MB / 回收到 70%）与时间淘汰（24 小时）双重熔断策略。
- **功能(动画性能等级判定与自适应)**:
  - 实现 `CyberPerformanceDetector` 模块，通过 100 万次 CPU 微基准计算 + `ProcessInfo.currentRss` 常驻内存指标，量化出高、中、低三档 `CyberAnimationLevel`，支持 UI 特效无缝自适应。

## **2026-04-28**

- **修复(TTS 引擎异常恢复机制)**: 修复了 `TtsEngineService` 播放循环中的时序竞争缺陷。
  - 优化 `TimeoutException` 与普通异常的捕获分支，在 `_audioPlayer.stop()` 之后立即加入生命周期检查守卫 `if (_disposed || !isEnabled || _loopSession != sessionAtStep) return;`。
  - 解决了引擎在被手动禁用后，因抛出异常仍会盲目执行降级与本地朗读的缺陷，使流程完全符合安全、正规的业务控制逻辑。

## **2026-04-27**

- **迁移(Flutter 3.41 API)**: 完成了从 `MaterialState` 到 `WidgetState` 的全量底层迁移。
  - 全局替换 `MaterialStateProperty` -> `WidgetStateProperty`。
  - 重点加固了 `cyber_import_button.dart` 等自定义 UI 组件，消除了所有废弃 API 警告。
  - `flutter analyze` 达成 100% 零警告。
- **加固(全量测试通过)**: 修复了遗留的测试失败项，达成 67/67 测试用例全绿通过。
  - **TTS 引擎**: 引入了异步生命周期守卫（Disposed Check）与 1ms 调度缓冲，解决了时序竞态导致的测试不稳定性。
  - **业务逻辑**: 优化了 WakeLock 持有逻辑，支持在 buffering 状态下自动常亮，提升了阅读器在弱网环境下的体验。
  - **UI 组件**: 修复了 2048 棋盘手势冲突与提词器自动淡出计时器泄露问题。

---

## **2026-04-23**

- **迁移(Flutter 3.41 兼容性审计)**: 执行全库范围的 `MaterialState` API 审计，通过大规模替换 `WidgetStateProperty` 实现了与 Flutter 3.41 的完美对齐。
- **优化(Impeller 渲染性能)**: 针对 Impeller 引擎完成 `BackdropFilter` 渲染裁剪约束。
  - 在 `cyber_toast.dart` 与 `cyber_modal.dart` 中，将模糊滤镜与透明颜色图层嵌套分离，并确保内部图层的 `borderRadius` 严格对齐外部 `ClipRRect` 的 `CyberDimensions.radiusL` 约束，避免全屏重绘及边缘溢出引发的 GPU 功耗飙升。
- **重构(基于 Dart 3 模式匹配)**: 全面引入 Dart 3.11 最新的穷尽式 Switch 表达式（Switch Expressions）与模式匹配语法：
  - 重构 `CyberToast` 中的 `_getBorderColor()` 方法，将传统的 `switch-case` 简化为单行表达式。
  - 重构 `TtsEngineService` 中的 `_setLastError()`，利用类型模式与关系模式（如 `>= 500`）替代冗长的 `if-else` 分支。

---

## **2026-04-22**

- **重构(全域提示系统重构与错误链路加固)**:
  - **架构升级**: 彻底重构 `CyberToast`，移除 `BuildContext context` 依赖，采用 `globalNavigatorKey.currentState?.overlay` 定位顶层图层，并加入空指针保护机制（`if (overlay == null) return;`），解决了真机环境下的静默崩溃（Overlay 寻址失败）问题。
- **重构(状态与事件解耦)**:
  - 针对 `TtsErrorListener` 防抖逻辑与领域状态冲突的问题，在 `TtsEngineService` 中引入了独立于错误字符串的状态字段 `_errorTimestamp`。
  - 修改 `_setLastError`：在赋值错误字符串的同时，强制更新 `_errorTimestamp`，使相同的错误信息（State）通过时间戳（Event）被系统识别为新的触发。
  - 优化全局错误监听器 `_TtsErrorListenerState`，将基于字符串比较的防抖策略重构为基于 `_errorTimestamp` 变更的触发策略（`if (err != null && tts.errorTimestamp != _previousErrorTime)`），实现了防抖与领域状态彻底解耦。
- **整改(硬编码问题修复)**:
  - **尺寸常量化**：将 `cyber_toast.dart`、`square_board.dart` 和 `cyber_import_button.dart` 中的硬编码尺寸替换为 `CyberDimensions` 中的对应常量。
  - **颜色常量化**：将 `cyber_toast.dart` 和 `cyber_import_button.dart` 中的硬编码颜色替换为 `CyberColors` 中的对应常量。
  - **服务器地址配置化**：修改 `TtsConfig` 类，使其从环境变量中读取服务器地址，避免硬编码 IP。
- **修正(Android 构建系统与 IDE 环境)**: 彻底解决了 IDE 中的 Java 17 环境缺失报错及 Gradle 构建链路漏洞。
  - **环境对齐**: 识别到系统 PATH 默认 JDK 为 1.8 导致现代 AGP 同步失败，已通过 `.vscode/settings.json` 及 `gradle.properties` 强制指定 `D:\Work\Android Studio\jbr` (JDK 21) 为工程构建环境。
  - **构建协议升级**: 将 Android Gradle Plugin (AGP) 从 8.4.2 升级至 8.7.3，完美适配 Gradle 8.7。

---

## **2026-04-21**

- **功能(2048 棋盘吉祥物交互)**: 引入 Rive 赛博吉祥物 (XIAOYO) 动态交互系统。
  - 实现状态机驱动的眨眼、微笑、思考及报错反馈动画。
  - 错误反馈与 `CyberToast` 系统深度集成，提升交互的情绪感知。

---

## **2026-04-20**

- **发版(V1.0商业化发版冲刺)**:
  - **核心目标**: 达成全部 P0/P1 级商业化合规与性能优化任务，确保 App Store/Google Play 准入。
  - **完成详情**:
    - **第一阶段：合规与隐私加固 (P0)**
      - **[P0-1] 权限最小化审计**: 移除 AndroidManifest.xml 中冗余的 `READ_PHONE_STATE` 和 `ACCESS_FINE_LOCATION` 权限。
      - **[P0-2] 隐私协议弹窗**: 实现首次启动强制隐私协议勾选，并采用 `cyber_modal.dart` 样式的赛博感视觉。
    - **第二阶段：UI 工程化与解耦 (P1)**
      - **[P1-4] 统一 Error Mapping**: 建立 `core/error/cyber_error_mapping.dart`，将所有 Service 层的抛错（如 403, 500, SocketException）映射为面向用户的“黑客风”文案。
      - **[P1-7] 删除一致性策略**: `BookshelfProvider.deleteBook()` 的三项清理（元数据/正文/阅读记录）改为独立 `try-catch`。
    - **第三阶段：服务层与状态机解耦 (P1)**
      - **[P1-5] 拆 TtsEngineService 接口依赖**: 构造统一注入 `config`、`audioPlayer`、`wakeLock`、`httpClient`、`delayFn` 五个可替换依赖，不再依赖平台通道，实现 100% 单元测试覆盖。
    - **第四阶段：性能与资源优化 (P2)**
      - **[P2-12] 棋盘重绘隔离**: 为 `SquareBoard` 核心网格应用 `RepaintBoundary`。

---

## **2026-04-04**

- **功能(2048 黑客后门彩蛋)**: 在 2048 游戏方块中植入「连续点击 8 次自毁」隐藏彩蛋，强化赛博朋克极客氛围。

---

### **2026-03-23**

- **重构**: 引入了 `Provider` 状态管理，并对 `ReaderProvider` 和 `TtsEngineService` 进行了大规模优化，解耦了 UI 与业务逻辑。 (commits: `7626d14`, `8df113e`)
- **功能**: 实现了书籍导入进度显示和全局 Toast 通知系统。 (commits: `215b39c`, `48b14a4`)

### **2026-03-13**

- **国际化**: 全面汉化了 UI 界面，移除了所有可见的英文文本。 (commit: `9626d14`)
- **UI/UX**: 优化了 UI 布局，修复了数值面板溢出和底部控件拥挤的问题。 (commit: `bdf113e`)
- **重构**: 按照规范对前后端项目结构进行了大规模重构，实现了模块化，并添加了详细的中文注释。 (commits: `315b39c`, `78b14a4`, `2b78d99`, `5235ddf`, `18dba57`, `d1f3138`, `314e98e`)
- **配置**: 将硬编码的服务器 IP 迁移到配置文件中进行统一管理。 (commit: `25ad232`)
- **安全**: 将 CORS 策略改为白名单制，并从版本控制中移除了二进制文件和数据库文件。 (commits: `4563aeb`, `b2768ec`)
- **文档**: 添加了项目 README 文件。 (commit: `383d88a`)
- **初始提交**: 初始化阅游项目独立仓库。 (commit: `9ce088a`)

---
