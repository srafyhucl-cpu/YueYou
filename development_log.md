# 阅游 (YueYou) - 开发日志

## **2026-04-30**
- **重构(V1.1 架构升级 - Riverpod Phase 2 完成)**:
  - 完成业务层三大 Provider 迁移：`TtsEngineService`、`GameProvider`、`ReaderProvider` 全部适配为 `ChangeNotifierProvider`，通过 `ref.onDispose` 管理生命周期。
  - UI 层全面迁移：`TeleprompterView`、`ChapterListScreen`、`CyberPlayerConsole`、`DashboardScreen`、`TtsErrorListener` 升级为 `ConsumerStatefulWidget`。
  - 完成剩余组件迁移：`SquareBoard`、`BoardMascot`、`BoardMascotRive`、`_Bootstrapper`（main.dart）、`settings_screen` 子组件、`library_screen`、`cyber_import_button`。
  - **彻底移除 `provider` 依赖**：从 `pubspec.yaml` 删除 `provider: ^6.1.5+1`，全项目无任何 `context.read<T>()` / `context.watch<T>()` 残留。
  - 测试层适配：`square_board_test`、`chapter_list_screen_test`、`teleprompter_view_test`、`widget_test` 全部迁移至 `ProviderScope` 覆盖注入，移除 `MultiProvider`。
  - `flutter analyze: No issues found`，单文件测试 100% 通过。
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

## **2026-04-29**
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
