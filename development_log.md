# 阅游 (YueYou) 项目开发日志
 
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
