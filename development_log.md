# 阅游 (YueYou) - 开发日志

## **2026-05-02**

- **修复(TTS 切换延迟与异常降级稳定性优化)**:
  - **消除切换延迟**：将 `refreshSession` 中的状态清理与游标重置前置，配合 `_playCompleter` 信号量立即中断 `playFile` 阻塞，解决了切换发声人后旧声音残留在内存中排队播放的问题。
  - **修复暂停跳句 (Skip on Resume)**：引入 `_isPausing` 状态锁。当因 `pause()` 触发音频停止时，拦截进度推进回调（`_onPlaybackComplete`），确保恢复播放时依然从当前句子开始。
  - **游标同步对齐**：在 `TtsSentenceSource` 接口新增 `resetFetchIndex`。在刷新会话时强制同步 `ReaderProvider` 的预取游标（`_fetchIndex`）至当前可见游标（`_currentIndex`），彻底解决因预取领先导致的切换后“跳过一两句”的陈年 BUG。
  - **双重会话校验 (Session Sentry)**：为 `BufferedAudio` 增加 `session` 标识，确保过期音频被精准丢弃。

- **维护(Codex 开发管理技能体系)**:
  - 新增 6 个项目级 Codex 技能：`yueyou_task_steward`、`yueyou_architecture_guard`、`yueyou_tts_audio_guard`、`yueyou_flutter_performance_guard`、`yueyou_test_ci_guard`、`yueyou_docs_encoding_guard`。
  - 将任务收口、架构边界、TTS 两步下载契约、Flutter 性能规则、测试 CI 流程和中文文档编码规则固化到 `.agents/skills/*/SKILL.md`。
  - 保留 `.agents/skills/*.md` 历史规则，新增目录式技能作为后续 Codex 管理入口。

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
