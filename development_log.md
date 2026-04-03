# 阅游 (YueYou) 项目开发日志
 
---

### **2026-04-03**
- **架构重构与测试工程化（四阶段整体推进）**: 按优先级分四阶段完成 12 项任务，涵盖测试闭环、生命周期修正、状态解耦、设计系统收口与契约测试。
  - **第一阶段：紧急修复与基础加固**
    - **[P0-1] FileImportService 测试闭环**:
      - 新增 `_activeImportToken` 令牌机制，`cancelImport()` 递增令牌后旧 Isolate 返回值自动丢弃，消除取消后残留回调写入脏状态的竞态。
      - 暴露 `parseFileForTesting()`、`isValidUtf8SampleForTesting()`、`stripUtf8BomForTesting()` 三个测试入口，无需 mock Isolate 即可直接验证流式解析、BOM 跳过与编码检测。
      - 新增 `test/features/library/file_import_service_test.dart`：覆盖正常解析、BOM 跳过与空行过滤、不存在文件返回 null 三个用例。
      - `CyberImportButton` 从 `StatelessWidget` 改为 `StatefulWidget`，`dispose()` 中主动 `cancelImport()`，防止页面销毁后 Isolate 仍在后台运行。
    - **[P0-2] main.dart bootstrap 生命周期修正**:
      - `YueYouApp` 从 `StatelessWidget` 改为 `StatefulWidget`，将 `_loadBootstrapData()` 的 `Future` 缓存到 `initState()` 的 `_bootstrapFuture` 字段。
      - `FutureBuilder` 绑定稳定引用，彻底消除 `build()` 每次重建都触发异步初始化的副作用（违反红线规则 1）。
    - **[P0-3] ReaderProvider 通知粒度优化**:
      - 新增 `_lastTtsEnabled`、`_lastTtsSpeaking`、`_lastTtsBuffering` 三个快照字段，`_onTtsEngineChanged()` 中逐字段 diff，仅在值真正变化时才 `notifyListeners()`。
      - 移除原先无条件 `changed = true` 的粗粒度通知，降低提词器在 TTS 缓冲期间的无效重绘频率。
  - **第二阶段：UI 解耦与设计系统第一轮收口**
    - **[P0-4] 模块三 design token 第一轮收口**:
      - `CyberConfirmDialog` 剥离底层 `showGeneralDialog` 逻辑，改为 `showCyberModal` 的 `child` 传入，消除弹窗代码重复。
      - 弹窗消息文本区包裹 `Flexible` + `SingleChildScrollView`，系统字体放大 200% 时可滑动查看。
      - `cyber_modal.dart` 中硬编码边距/圆角/模糊值全部替换为 `CyberDimensions.radiusL`、`blurStrong`、`borderThick`、`spacingXL`。
      - `LibraryScreen` 标题栏、空态文案、书籍卡片内间距/字号/删除按钮全部收口至 `CyberDimensions` + `CyberTextStyles`。
      - `ChapterListScreen` 标题栏、进度摘要、章节行间距/图标尺寸/排序按钮全部收口至 `CyberDimensions` + `CyberTextStyles`。
      - 书籍删除确认弹窗从手写 `AlertDialog` 迁移到 `showCyberConfirmDialog`，统一视觉规范。
    - **[P1-6] toggleTTS() 去 UI 文案耦合**:
      - `ReaderProvider.toggleTTS()` 返回值从 `void` 改为 `TtsToggleResult` 枚举（`playing` / `paused` / `noContent`），不再内部调用 `setLastError()` 写入 UI 文案。
      - `CyberPlayerConsole` 在调用侧根据返回值决定是否通过 `ttsEngine.setLastError()` 展示提示，实现 domain 层与 UI 文案的彻底解耦。
    - **[P1-7] 删除一致性策略明确化**:
      - `BookshelfProvider.deleteBook()` 的三项持久化清理（书架元数据 / 正文内容 / 阅读记录）从 `Future.wait` 改为独立 `try-catch`，任一失败不影响其他两项。
      - 内存状态 `_shelf` 先行移除并立即 `notifyListeners()`，确保 UI 瞬时响应；持久化清理在后台 best-effort 执行。
      - 补充 `test/features/library/bookshelf_provider_test.dart`：覆盖添加/删除/级联重置等场景。
  - **第三阶段：服务层与状态机解耦**
    - **[P1-5] 拆 TtsEngineService 接口依赖**:
      - 测试中 `TtsEngineService` 构造统一注入 `config`、`audioPlayer`、`wakeLock`、`httpClient`、`delayFn` 五个可替换依赖，不再依赖平台通道。
      - `_FakeHttpClient` / `_FakeAudioPlayer` / `_FakeWakeLock` 统一对齐最新接口签名（`enable/disable` 顺序、`Stream.empty()` 替代 `StreamController`）。
    - **[P1-8] FileImportService 去静态化准备**:
      - 暴露三个 `ForTesting` 静态方法，为后续实例化改造预留测试入口，当前仍保持 `static` 以最小化破坏面。
    - **[P1-9] GameProvider 再解耦**:
      - 所有公开字段（`board`、`score`、`combo`、`maxCombo`、`bestScore`、`isOver`、`soundEnabled`、`lastMoveNoMerge`、`lastMergedValue`）全部私有化为 `_board`、`_score` 等，通过 getter 暴露只读视图。
      - 新增 `setStateForTesting()` 方法，测试通过该入口注入棋盘/分数/状态，不再直接赋值私有字段。
      - `game_provider_test.dart`、`square_board_test.dart` 全量迁移至 `setStateForTesting()` API，消除对内部状态的直接写入。
  - **第四阶段：契约测试与设计系统工程化**
    - **[P2-10] TTS 契约测试**:
      - 新增 `test/features/audio/tts_contract_test.dart`，验证 `TtsEngineService` 严格遵循"分离下载"原则：先 POST 获取 JSON → 解析 `url` 字段 → 再 GET 下载音频。
      - 覆盖成功响应（验证 `wasDownloadCalled` + `downloadedUrl`）与 500 错误响应（验证不下载 + `lastError` 包含错误信息）两个场景。
    - **[P2-11] TextParser 不变量测试**:
      - 扩展 `text_parser_test.dart`，新增 5 项不变量用例：解析结果不丢失有效字符、保持原始顺序、多行输入行号对应、长句截断语义完整性、连续标点符号不导致空句。
      - 新增软断点回归测试：验证无标点长句优先从助词（的/了/和/与）处截断而非硬切。
    - **[P2-12/13/14] 测试与设计系统工程化**:
      - 新增 `test/utils/test_utils.dart`，集中初始化 `SharedPreferences`、`StorageService` 与 6 组平台通道 mock（path_provider / audioplayers / wakelock / haptic / platform / system_sound），所有测试文件统一接入。
      - 修复 `chapter_list_screen_test.dart`：注入固定 `ParseResult` 去除过重解析链路，解决 Widget Test 卡住问题。
      - 修复 `teleprompter_view_test.dart`：关闭测试场景自动 TTS 播放，补齐 `ReaderProvider / TtsEngineService` 资源释放，消除定时器泄漏。
      - 修复 `game_provider_test.dart` 中 2 个过时期望（不可移动棋盘构造 + 单次合并语义断言）。
      - 新增 `reader_provider_test.dart` 三个用例：`toggleTTS` 无书籍返回 `noContent`、有内容返回 `playing`、相同 TTS 错误不重复通知。
      - `CyberDimensions` 补充：`spacingXXS`、`teleprompterHeight`、`teleprompterMaskWidth`、`dashboardMascotWidth/Height`、`dashboardBoardBuffer`、`dashboardStatusCardMinHeight`。
      - `CyberTextStyles` 补充：`overlineTiny`、`segmentLabel`、`teleprompterInlineRead/Unread`、`teleprompterError/Placeholder`、`dashboardCounter/Separator`、`captionBold/Tight/Comfortable/Hint`。
      - `dashboard_screen.dart`：顶部工具栏、状态卡、分数计数器与吉祥物布局全部 token 化。
      - `teleprompter_view.dart`：电传屏高度、左右遮罩、中心指示线、错误提示与占位文案全部 token 化。
      - `settings_screen.dart`：说明文案、倍速芯片边框、TTS 结果面板、音量百分比、空闲暂停说明全部 token 化。
  - **验证结果**:
    - `flutter test` 全量通过（219 用例）。
    - `flutter analyze` 相关修改文件通过。
    - 35 个文件变更，+2209 / -851 行。
  - **提交记录**: Commit ID `ed1c4b8` - "完成P2-12/13/14测试与设计系统工程化收尾"

- **优化(模块三：视觉、交互与用户体验)**: 按 `optimization_tasks.md` 完成模块三全部 4 项任务，清剿弹窗硬编码、字体缩放溢出、僵尸弹窗和文本截断体验问题。
  - **3.1 弹窗组件原子化**:
    - 重构 `CyberConfirmDialog`，剥离底层 `showGeneralDialog` 逻辑，改为 `showCyberModal` 的子节点 `child` 传入
    - 所有硬编码边距（`margin: 40`）、圆角（`BorderRadius.circular(20)`）、边框宽度（`width: 1.5`）、模糊值（`sigmaX: 15`）全部替换为 `CyberDimensions` 常量
    - 同步修复 `cyber_modal.dart` 中的硬编码值，统一使用 `CyberDimensions.radiusL`、`blurStrong`、`borderThick`、`spacingXL`
    - `_CyberButton` 内部 padding/圆角/边框宽度同步收口至 `CyberDimensions.spacingMS`、`radiusS`、`borderNormal`
    - 新增 `CyberDimensions.spacingMS = 12.0` 补全 4px 网格间距体系
  - **3.2 系统字体缩放防溢出**:
    - 弹窗消息文本区包裹 `Flexible` + `SingleChildScrollView`，系统字体放大 200% 时可滑动查看，不再出现 Yellow/Black 溢出条
  - **3.3 僵尸弹窗消除**:
    - `_TtsTestButton` 从 `StatelessWidget` 改为 `StatefulWidget`，使用本地 `_isTesting` 声明式状态控制
    - 移除命令式 `showDialog` + `Navigator.pop` 的 Loading 弹窗，改为按钮内联 `CircularProgressIndicator`
    - 测试期间禁用重复点击（`onTap: _isTesting ? null : ...`），消除 Loading 弹窗与底层数据突变导致的僵尸弹窗风险
  - **3.4 文本解析边缘截断优化**:
    - `_emergencySplit` 增加两遍扫描机制：第一遍寻找强断点（标点/空格/顿号），第二遍寻找软断点（连词/助词：的、了、和、与）
    - 软断点阈值降至 50%（强断点保持 70%），在无标点长句中优先从助词处截断，避免劈开词组导致 TTS 朗读怪异
  - **测试验证**:
    - 新增软断点回归测试，验证无标点长句优先从助词处截断而非硬切
    - `flutter test test/features/reader/text_parser_test.dart` 通过（20/20）
    - `flutter analyze` 全部 5 个修改文件通过，0 issues
    - 相关测试套件全部通过（63/63）

- **测试稳定性修复（CI flaky 收敛）**:
  - 修复 `test/features/audio/tts_engine_service_test.dart` 在 CI/全量运行下的三类不稳定问题：`path_provider` mock 指向真实系统临时目录导致初始化扫描过慢、`testConnection` 写文件失败分支的专用 mock 被构造器内 mock 覆盖、以及依赖固定 delay 的重试断言在不同机器上时序漂移。
  - 新增测试隔离临时目录 `_testTempDir`，`_makeService()` / `_makeMockService()` 统一将 `path_provider` 指向空目录，避免 `_cleanupOrphanedTtsFiles()` 扫描真实系统 temp 引发 `_voice` 尚未初始化就进入下载分支的竞态。
  - `_makeMockService()` 在返回 harness 前主动等待 `setVolume` / `setPlaybackRate` 初始化副作用落地，消除 `syncSpeedFromSettings 相同值时不更新` 被异步初始化污染的问题。
  - 将 HTTP 500 重试测试从“等待固定 delay”改为“等待 `postCalls == maxRetries`”，并仅验证指数退避延迟集合出现，降低对调度细节的脆弱依赖。
  - 调整 `testConnection 写入文件失败：step 5 应为 error` 的 mock 顺序：先创建 service，再将 `getTemporaryDirectory` 改为抛出 `PlatformException`，确保步骤 5 稳定命中 error 分支。
  - `merge_particle_test.dart` 保持 `pumpAndSettle` 写法验证动画完成回调，在与 TTS 套件组合运行时确认已不再被前置测试竞态拖垮。
- **验证结果**:
  - `flutter test test/features/audio/tts_engine_service_test.dart test/features/game_2048/merge_particle_test.dart` 通过。
  - `flutter test` 全量通过（210 用例）。

---

### **2026-04-02**
- **重构(TTS)**: TTS 服务架构重构，适配新后端 API 两步下载流程（POST 获取 URL + GET 下载音频），并修复无书籍时开启 TTS 的问题。
  - **架构变更**:
    - 重构 `TtsHttpClient` 抽象，新增 `download()` 方法支持独立音频文件下载
    - 替换原有直接写入响应体逻辑为两步下载：先 POST JSON 获取音频 URL，再 GET 下载到本地缓存
    - 新增临时文件清理机制，避免磁盘空间泄漏
  - **错误处理增强**:
    - 新增 `TtsErrorListener` 全局错误监听组件，通过 `MaterialApp.builder` 集成到应用根节点
    - TTS 错误时自动显示 SnackBar 提示用户（如"无法继续 TTS：没有可读取的内容，请先导入书籍"）
    - 优化 `setEnabled()` 错误清除逻辑，区分用户手动关闭与系统自动关闭场景，保留错误信息供 UI 展示
  - **无书籍保护机制**:
    - 连续 11 次 `onNeedPrefetch` 返回 null 后自动停止 TTS 并显示错误提示
    - 自动关闭前通过 `Future.microtask` 延迟执行，确保监听器先收到错误事件
  - **文件导入优化**:
    - 优化 UTF-8 解码逻辑，添加字节级有效性检查 `_isValidUtf8()`，避免不必要的 `FormatException`
    - 解码策略：UTF-8 严格校验 → GBK 容错解码 → UTF-8 宽松解码三层兜底
  - **测试适配**:
    - 修复 `play/pause` 单元测试，绑定 `onNeedPrefetch` 回调以适配新的启用检查逻辑
    - 更新所有 Mock HTTP Client 实现，适配新 `TtsHttpClient` 接口
  - **验证结果**: 单元测试全部通过（199/199），代码已提交并推送到 `yueyou_test` 分支。
  - **提交记录**: Commit ID `e05005d` - "修复TTS无书籍时自动关闭及添加错误提示"
- **优化(模块一：核心防呆与全域容错机制)**: 按 `optimization_tasks.md` 收口模块一剩余任务，补齐临时文件回收、安全截断和播放超时可见化暂停。
  - **1.1 临时音频文件回收**:
    - 在 `TtsEngineService` 初始化阶段扫描临时目录，主动清理历史遗留的 `tts_*.mp3` 文件
    - 保留当前会话仍可能使用的文件路径，降低强杀 App 后的缓存泄漏风险
  - **1.3 删除书籍级联重置**:
    - 确认 `BookshelfProvider.deleteBook()` 已在删除当前阅读书籍时联动 `ReaderProvider.resetForDeletedBook()`
    - 删除后同步停止 TTS、清空句子/章节/进度状态，避免幽灵章节与越界读取
  - **1.4 提词器安全截断**:
    - 将 `TextParser._emergencySplit()` 中的直接 `substring()` 全部替换为 `safeSubstring()`
    - 统一收口长句切分与提词器高亮切片的越界保护，降低 Emoji / 特殊字符触发 `RangeError` 的风险
  - **1.5 播放超时显式暂停**:
    - `setSource` / 音频加载超时后不再静默跳句，而是显式 `stop + pause`
    - 通过 `lastError` 抛出“音频加载超时，已暂停”状态，交由 UI 提示用户手动恢复
    - 同步保留 `testConnection()` 在初始化未完成场景下的可测性，避免 `LateInitializationError`
  - **测试验证**:
    - `flutter test test/features/audio/tts_engine_service_test.dart` 通过
    - `flutter test test/features/reader/teleprompter_view_test.dart` 通过
    - `flutter analyze lib/features/audio/services/tts_engine_service.dart lib/features/reader/domain/text_parser.dart lib/features/library/providers/bookshelf_provider.dart lib/features/reader/providers/reader_provider.dart` 通过

- **优化(模块二：内存与状态管理加固)**: 按 `optimization_tasks.md` 继续推进模块二，优先完成高收益的状态持久化、防竞态启动和 UI 状态解耦。
  - **2.2 2048 持久化防抖**:
    - 为 `GameProvider` 增加可配置的持久化防抖调度，默认 1 秒合并多次写入
    - 在 `AppLifecycleState.paused` 时主动 `flushPersistState()`，避免后台切换时丢档
    - 测试环境使用 `Duration.zero` 关闭防抖，避免挂起 `Timer` 污染单测生命周期
  - **2.3 GameOver 事件化**:
    - 从 `GameProvider` 中移除 `showGameOverDialog` 与 `dismissGameOver()` 等 UI 状态
    - Provider 仅保留 `isOver` 领域状态，并通过 `onGameOver` 广播事件通知界面层
    - `SquareBoard` 改为本地维护弹窗显隐，监听事件后显示，点击取消/重开时仅操作本地 UI 状态
  - **2.4 启动显式预加载**:
    - `main.dart` 改为启动时先显式加载 `SettingsProvider` / `BookshelfProvider`
    - 预加载完成后再构建 `MultiProvider` 与 `TtsEngineService`，降低首屏阶段的 Provider 启动竞态
  - **2.1 TXT 导入流式读取 + Isolate 生命周期管理**:
    - `FileImportService` 从 `compute` 迁移到 `Isolate.spawn`，提供 `cancelImport()` 主动终止能力
    - 彻底移除 `readAsBytes()`，主线程只传文件路径给 Isolate
    - Isolate 内部采用 `File.openRead()` 流式读取 → 编码解码 → `LineSplitter` 行切分，内存中不再同时驻留原始字节和解码字符串
    - 编码检测改为采样前 8KB 判断 UTF-8/GBK，新增 `_isValidUtf8Sample` 允许尾部截断的不完整序列
    - BOM 处理通过 `file.openRead(3)` 跳过前 3 字节，无需额外内存拷贝
  - **测试验证**:
    - `flutter test test/features/game_2048/game_provider_test.dart test/features/game_2048/square_board_test.dart test/widget_test.dart` 通过
    - `flutter analyze lib/features/game_2048/providers/game_provider.dart lib/features/game_2048/presentation/widgets/square_board.dart test/features/game_2048/game_provider_test.dart test/features/game_2048/square_board_test.dart lib/main.dart` 通过
  - **提交记录**: Commit ID `25d15c3` - "优化(模块二完成): 2048 持久化防抖、GameOver 事件化、启动预加载、TXT 流式导入"

---

### **2026-04-01**
- **修复(TTS)**: 修复了暂停后恢复播放时偶发跳句的问题，播放循环现在仅在音频自然播放完成时才推进到下一句，避免暂停、切章、超时等中断场景误触发 `onItemFinished`。
- **修复(提词器)**: 优化了 `TeleprompterView` 与 `ReaderProvider`、`TtsEngineService` 的状态同步链路，确保暂停时提词器立即停止，暂停状态下切换句子时能正确重置进度。
- **修复(TTS 跳句问题)**: TTS 播放时出现跳句现象，日志显示多个播放循环同时运行，导致 `AudioPlayer` 资源竞争，音频互相打断。
  - **根因分析**: `setEnabled(true)` 和 `refreshSession()` 方法会强制重置循环标志位，导致旧循环未完全退出时新循环启动，造成并发竞争。
  - **修复方案**:
    - 在 `_startPlayLoop()` 和 `_startPrefetchLoop()` 中捕获启动时的 `mySession`，并在 `while` 条件中检查 `mySession` 是否与当前 `_loopSession` 匹配，确保旧循环自动退出。
    - 修改 `setEnabled(true)` 逻辑，不再强制重置循环标志位，让现有循环自然恢复。
    - 修改 `refreshSession()` 逻辑，移除标志位重置，延迟启动新循环，给旧循环退出机会。
  - **验证结果**: 单元测试全部通过（199/199），代码已提交并推送到 `yueyou_test` 分支。
  - **提交记录**: Commit ID `a6e5f30` - "修复 TTS 跳句问题：通过 session 隔离循环实例防止并发竞争"
- **测试**: 补充并更新了 TTS 服务、提词器错误提示、章节目录等相关测试用例，同时引入 `mockito`、`fake_async` 以支持更稳定的异步与播放器分支测试。
- **文档**: 更新了调试文档，补充通过 VS Code / Windsurf 原生 Flutter 调试配置 `launch.json` 注入 `TTS_SERVER_URL` 的说明，便于真机热加载与热重启联调。

### **2026-03-31**
- **测试**: 扩展了 2048 游戏小组件的测试覆盖范围，并更新了音频相关的测试。 (commit: `925b261`)
- **测试**: 为 TTS（文本转语音）服务注入了延迟函数，并补充了关于失败分支（如 400/500 错误、退避策略、短句过滤）的单元测试。 (commit: `af14d2a`)
- **测试**: 修复了 `TtsEngineService` 单元测试因异步初始化和 `WakeLock` 状态导致的不稳定问题。 (commit: `a55333d`)
- **功能**: 对代码进行了可测试性改造，通过增加单元测试显著提升了代码覆盖率。 (commit: `3f3f176`)
- **CI/CD**: 对持续集成流程进行了多次优化，包括改进测试覆盖率报告的展示方式、调整覆盖率阈值、修复格式问题以及增强中文显示效果。 (commits: `de8f800`, `0f4ba0f`, `6e84637`, `fae5427`, `cebac76`)
- **测试**: 将核心业务逻辑的代码覆盖率提升至 90% 以上，并优化了 CI/CD 流程中的相关提示。 (commit: `878309a`)

### **2026-03-30**
- **CI/CD**: 建立了严格的代码覆盖率标准，要求核心业务逻辑达到 90% 以上，并配置 CI/CD 流水线以支持自动化测试和报告生成。 (commits: `a58685a`, `79e90aa`, `c99b475`, `d933686`, `245e656`, `93088be`, `76f2a31`, `24f4650`, `55c6659`, `8d53106`, `0f709ce`, `28689f4`, `ef49050`)
- **测试**: 新增了大量单元测试，覆盖了存储服务、游戏核心逻辑和文本解析器等关键模块。 (commit: `e31eba3`)
- **测试**: 为阅读器和提词器功能添加了初步测试。 (commit: `07a5f4c`)
- **重构**: 遵循代码规范，大规模清理了项目中的死代码、修复了已知的架构反模式问题，并统一了代码风格。 (commit: `0b2fd39`)
- **文档**: 更新了项目 `README` 和 `.windsurfrules` 规则文件，使其与当前最新的 Flutter 架构保持一致。 (commit: `24da55e`)
- **重构**: 进一步规范代码，修复了性能问题，统一了字体管理方案。 (commit: `94fc2f3`)
- **安全**: 移除了代码中硬编码的服务器 IP 地址，以提升安全性，并完善了 `.gitignore` 文件。 (commit: `792e371`)

### **2026-03-28**
- **功能**: 实现了 XIAOYO 吉祥物系统，为应用增加了互动元素。 (commit: `09500ad`)

### **2026-03-27**
- **功能**: 优化了 UI 样式的统一性，修复了 TTS 播放可能卡死的 Bug，并添加了 TTS 连接测试工具。 (commit: `9e6e14f`)

### **2026-03-26**
- **修复**: 解决了 TTS 播放中的多个问题，包括：防止重复播放、移除不可靠的卡顿检测、增加服务器队列满时的等待时间、优化播放器预加载和状态同步、以及在多次失败后自动跳过问题语句。 (commits: `b86620a`, `56994c8`, `c674509`, `9812f04`, `e840d66`, `2c24d0a`, `f203412`, `4cd5aab`)

### **2026-03-25**
- **修复**: 解决了 TTS 播放逻辑的多个 Bug，包括：修复了切章后光标位置不正确的问题、解决了会话刷新和循环重启的缺陷，并增加了下载失败后的重试延迟。 (commits: `61e2b06`, `cb0ccb1`, `dd6fb2d`)

### **2026-03-23**
- **功能**: 为 TTS 系统增加了自动合并短句的功能，以满足 API 对句子最短长度的要求。 (commit: `2950bbb`)
- **调试**: 添加了更详细的 TTS 日志，以帮助诊断播放无声音的问题。 (commit: `25f7d9a`)

### **2026-03-21**
- **重构**: 对切章逻辑进行了领域驱动设计（DDD）重构，彻底解决了相关的历史遗留问题。 (commit: `fa79a50`)
- **修复**: 解决了切章后 TTS 不播放、智能跳过章节标题、以及修复了多个致命 Bug 和性能问题，显著提升了应用的稳定性和用户体验。 (commits: `b5bd6e9`, `3807939`, `337c1d5`, `c8687bd`, `6e0d910`, `8fc0cb5`)
- **性能**: 优化了切章时的性能，消除了可能导致主线程死锁和掉帧的问题。 (commit: `8fc0cb5`)
- **功能**: 切换并集成了新的 TTS 引擎。 (commits: `685bd66`, `8734a00`)

### **2026-03-20**
- **重构**: 进行了大规模的 UI 和全局架构重构，为后续开发奠定了坚实的基础。 (commits: `3c299fb`, `498bbd7`, `f1888fd`, `e5133c6`, `36b0439`)
- **功能**: 实现了文件导入系统。 (commit: `89646b7`)

### **2026-03-19**
- **功能**: 开发并重构了 TTS 全息控播与音频引擎，实现了对音频播放的精准控制。 (commits: `7bb6875`, `27c27e3`, `02bb8a7`)
- **功能**: 实现了集 2048 游戏、提词器、导航和分数显示于一体的仪表盘主屏幕。 (commit: `24e643c`)
- **UI**: 实现了 2048 游戏界面、赛博朋克风格光标、提词器视图，并引入了全新的主题色彩。 (commit: `f248f36`)
- **UI**: 完成了应用的赛博朋克 UI 骨架设计，并对“灵动岛”等设备特性进行了适配。 (commit: `abfb8a6`)

### **2026-03-14**
- **UI/UX**: 对 UI 进行了多次美化和体验优化，包括美化滚动条、调整弹窗透明度、修复了启动时小说加载和目录可见性问题。 (commits: `0461a90`, `0be55ef`, `97c90b8`, `bdfa562`)
- **功能**: 默认并仅保留武侠主题的环境音景，聚焦核心体验。 (commit: `da416e2`)
- **修复(v1.2.1)**: 修复了书籍删除时崩溃、导入卡死及 TTS 对 0 字节响应的容错问题。 (commit: `9879a5d`)
- **重构(v1.2)**: 进行了视觉和音效的深度重构，移除了进度条等元素，增强了 3D 悬浮质感和音效饱满度。 (commit: `8ccf3ec`)
- **修复**: 调整了连击特效的位置和持续时间，并修复了多个 UI 和功能性 Bug。 (commits: `adb8e79`, `dc1e2f2`)
- **功能(v1.0, v1.1)**: 实现了微霓虹流体方块配色、Apple 胶囊导航栏、连击特效、404 提示、全域音频静音解锁等核心功能。 (commits: `e846431`, `609bdde`)
- **重构**: 彻底重构了 UI、计分逻辑、章节排序和 TTS 语音队列，修复了 7 大严重缺陷。 (commits: `93c78ec`, `cb65c01`)
- **重构**: 收敛产品方向，还原为无尽 2048 模式，并重构音频引擎以支持章节自动解析。 (commit: `44cef4f`)
- **修复(TTS)**: 优化了 TTS 引擎，通过填充无声标点、增加超时快速降级和原生语音合成回退机制，解决了服务器 400 错误、字符限制和网络阻塞等问题。 (commits: `601d2ff`, `3cee376`, `06488a9`, `4e741fa`)

### **2026-03-13**
- **国际化**: 全面汉化了 UI 界面，移除了所有可见的英文文本。 (commit: `9626d14`)
- **UI/UX**: 优化了 UI 布局，修复了数值面板溢出和底部控件拥挤的问题。 (commit: `bdf113e`)
- **重构**: 按照规范对前后端项目结构进行了大规模重构，实现了模块化，并添加了详细的中文注释。 (commits: `315b39c`, `78b14a4`, `2b78d99`, `5235ddf`, `18dba57`, `d1f3138`, `314e98e`)
- **配置**: 将硬编码的服务器 IP 迁移到配置文件中进行统一管理。 (commit: `25ad232`)
- **安全**: 将 CORS策略改为白名单制，并从版本控制中移除了二进制文件和数据库文件。 (commits: `4563aeb`, `b2768ec`)
- **文档**: 添加了项目 README 文件。 (commit: `383d88a`)
- **初始提交**: 初始化阅游项目独立仓库。 (commit: `9ce088a`)

---
