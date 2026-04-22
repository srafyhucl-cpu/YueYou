# 阅游 (YueYou) 项目开发日志

---

## **2026-04-22**

- **重构(全局错误集中化)**: 彻底落实 `CyberErrorMessages` 体系，将全工程 14+ 处硬编码的错误文案统一汇入 `lib/core/constants/cyber_error_messages.dart`，涵盖 TTS 通讯失败、文件格式错误、存储空间不足等所有关键边界，为后续多语言化奠定基础。
- **优化(视觉交互系统)**: 深度重构 `CyberToast` 与 `TtsErrorListener`，接入 "XIAOYO" 吉祥物驱动的拟人化错误反馈机制。报错时不再是冰冷的文字，而是由 `BoardMascot` 实时绘制的赛博气泡通知，显著提升了非法操作时的沉浸感。
- **修正(隐私合规流程)**: 对 `PrivacyAgreementModal` 进行逻辑二次审计，确保 Android 物理返回键无法绕过启动拦截，并完善了点击外链跳转协议页面的逻辑稳定性。
- **提交**: 完成商业化发版前的最后一次架构清道夫工作，移除了 `optimization_tasks.md` 等阶段性开发文档。

## **2026-04-21**

- **重构(设计系统合规)**: 清剿全工程 UI 控件中残留的「魔术数字」（硬编码的边距、圆角等），并强制汇入 `CyberDimensions` 设计系统以确保全局视觉响应式的统一。
  - 核心处理了 `library_screen.dart`、`square_board.dart`、`floating_score.dart`、`rain_effect.dart` 及音频相关组件。
- **架构净化**: 彻底核查整洁架构规范，确保 `domain` 层绝无 `flutter/material` UI 依赖，文本大文件解析全面接入 Isolate，高频重绘区均已使用 `RepaintBoundary` 进行隔离不造成重排污染。
- **重构(全局错误常量)**: 实施 "魔术字符串" 清除计划，新建 `lib/core/constants/cyber_error_messages.dart` 单例，将 TTS 网络通讯、本地解析、文件读取等 14+ 报错及边界脱敏文案全部收口为统一常量枚举，显著提高后续 i18n 效率。
- **构建测试**: 全工程通过 `flutter analyze` 达成 0 issues 健康度，排查宿主构建工具环境后成功达成 Android 端的 `flutter build apk --release` 构建，完全满足 V1.0 商业化上线发版的准备。

## **2026-04-20**

- **整改(错误提示统一与脱敏处理)**:
  - **错误提示统一**：将所有错误提示统一使用 `CyberToast` 组件，显示在屏幕中上部，符合设计规范
  - **错误信息脱敏**：修改 TTS 引擎错误信息，移除 IP 地址、端口号等敏感信息，使用赛博朋克风格的脱敏错误信息
  - **代码质量优化**：清理 `tts_error_listener.dart` 中未使用的导入，更新注释以匹配实际代码
  - **文件结构调整**：将 `tts_error_listener.dart` 从根目录移至 `shared/widgets` 目录，保持架构一致性

- **整改(硬编码问题修复)**:
  - **尺寸常量化**：将 `cyber_toast.dart`、`square_board.dart` 和 `cyber_import_button.dart` 中的硬编码尺寸替换为 `CyberDimensions` 中的对应常量
  - **颜色常量化**：将 `cyber_toast.dart` 和 `cyber_import_button.dart` 中的硬编码颜色替换为 `CyberColors` 中的对应常量
  - **服务器地址配置化**：修改 `TtsConfig` 类，使其从环境变量中读取服务器地址，避免硬编码 IP

- **验证结果**：
  - `flutter analyze` 零问题
  - 所有错误提示现在统一显示在屏幕中上部
  - 错误信息已脱敏，符合隐私合规要求
  - 代码结构更加规范，符合架构设计

## **2026-04-04**

- **功能(2048 黑客后门彩蛋)**: 在 2048 游戏方块中植入「连续点击 8 次自毁」隐藏彩蛋，强化赛博朋克极客氛围。
  - **核心逻辑（`GameProvider.eliminateTileById`）**:
    - 遍历棋盘按 `id` 定位目标方块，置 `null` 并触发 2048 级最高音效作为「黑客成功」听觉奖励
    - 消除后重新检查 `_movesAvailable()`，避免误判 GameOver；调用 `_schedulePersistState()` 防止存档丢失
  - **触控层改造（`TileWidget`）**:
    - 构造函数新增 `id`、`onEliminate` 可选参数；`SingleTickerProviderStateMixin` 升级为 `TickerProviderStateMixin` 以支持 dual `AnimationController`
    - 新增 `_tapResetTimer`（`dart:async`）：每次点击重置 1.5s 倒计时，超时则 `_tapCount = 0`，玩家中断操作后须重新从 1 开始
    - 前 7 次点击复用 `_mergeController.forward(from: 0.3)` 产生「正在破解防火墙」的受击抖动反馈
    - 第 8 次点击触发 `_eliminateController`（450ms 三段式）：
      - **膨胀**（0→25%）: scale 1.0 → 1.3，`easeOut`，模拟被锤击的瞬间膨胀
      - **坍缩**（25→100%）: scale 1.3 → 0.0，`easeInBack`，有回弹感的向心崩塌
      - **消散**（60→100%）: opacity 1.0 → 0.0，最后 40% 时间快速淡出
      - **旋转**（0→100%）: 微幅旋转 0 → 0.25 rad，`easeIn`，强化「数据被清除」混乱感
    - 动画结束回调 `.then((_) { widget.onEliminate?.call(); })` 触发全局状态修改，严格遵循「先播动画 → 回调修改状态」解耦原则
    - `_getParticleColor`：`_isEliminating` 时强制返回 `CyberColors.neonPink`（危险粉红粒子爆炸）
  - **连线层（`SquareBoard`）**:
    - `TileWidget` 调用处透传 `id: tile.id` 与 `onEliminate: () => provider.eliminateTileById(tile.id)`
  - **验证结果**: `flutter analyze` 三个修改文件均 0 issues

- **重构(音效引擎 V4)**: 基于旧版 Web 端已验证的 `playEffect('merge')` 音效精确移植到 Flutter 端，替换之前多次迭代但听感不佳的 V1-V3 版本。
  - **核心变更**:
    - 扫频方向从**下行**（高→低）改为**上行**（低→高），与旧版 Web 端 `440→880Hz exponentialRampToValueAtTime` 完全一致，听觉上更贴合"合并上升"的反馈感
    - 音量从 0.85-0.95 大幅降至 **0.12-0.22**，与旧版 Web 端的 0.12 保持一致，柔和不刺耳
    - 架构从 4-5 层叠加（chirp + shimmer + sub-bass + impact + 双 chirp）简化为**极简单层正弦波**，代码量从 308 行降至 209 行
  - **4 阶段递进参数**:
    - Stage 1 (≤16): 440→880Hz, 300ms, vol=0.12（与旧版完全一致）
    - Stage 2 (≤128): 400→900Hz, 340ms, vol=0.15
    - Stage 3 (≤1024): 350→950Hz, 380ms, vol=0.18
    - Stage 4 (>1024): 330→1000Hz, 420ms, vol=0.22
  - **零杂音保证**: 保留解析式 chirp 相位公式 `φ(t)=2π(f₀t+(f₁-f₀)t²/2T)`，连续可微，零相位突变
  - **验证结果**: `flutter analyze` 零问题，`flutter test` 32 测试全部通过

- **发版(Android 发版专项修复 + 图标替换)**:
  - **应用名称**: `AndroidManifest.xml` 中 `android:label` 由 `"yueyou"` 修改为 `"阅游"`，桌面图标与应用管理页将正确显示中文名
  - **退出方式规范化**: `privacy_agreement_modal.dart` 移除 `import 'dart:io'` 及 `exit(0)`，改用 `SystemNavigator.pop()` 符合 Android 生命周期规范；同步引入 `package:flutter/services.dart`
  - **隐私政策外链**: 将弹窗底部提示文字改为 `Wrap` 布局，内嵌霓虹青下划线可点击文字"阅读完整版《阅游隐私政策》"，使用 `url_launcher` 以 `LaunchMode.externalApplication` 打开腾讯文档隐私政策页（`https://docs.qq.com/doc/DVXpHSW9qRkFZVVlN`）
    - `pubspec.yaml` 新增 `url_launcher: ^6.3.0`（已解析为 `6.3.1`）
    - `AndroidManifest.xml` `<queries>` 补充 `https`/`http` scheme intent 声明（Android 11+ 必需）
  - **应用图标替换**: 使用项目已有的赛博朋克霓虹方块图（`assets/icon.png`）替换默认 Flutter 图标
    - `pubspec.yaml` 新增 `flutter_launcher_icons: ^0.14.3`（已解析为 `0.14.4`）并添加配置：`android: true, ios: false, adaptive_icon_background: '#0A0A0F'`
    - `dart run flutter_launcher_icons` 一键生成：5 个 mipmap 尺寸（mdpi/hdpi/xhdpi/xxhdpi/xxxhdpi）+ 5 个 adaptive foreground drawable + `mipmap-anydpi-v26/ic_launcher.xml` + `values/colors.xml`

- **发版(V1.0 商业化发版冲刺 Sprint)**: 按照 `v1_release_tasks.md` 依次完成全部 P0/P1 任务，将「阅游」从"内测 Demo"正式升级为"可上架各大应用市场的 V1.0 商业化产品"。
  - **[P0] Task 1: 网络安全策略与 TTS 离线引擎降级兜底**
    - Android `AndroidManifest.xml` 确认已有 `usesCleartextTraffic="true"`（无需修改）
    - iOS `Info.plist` 新兴 `NSAppTransportSecurity / NSAllowsArbitraryLoads = true`，解除 ATS 对 HTTP 明文流量的拦截
    - `pubspec.yaml` 确认已有 `flutter_tts: ^3.8.5`（无需修改）
    - 重构 `TtsEngineService` 降级架构：
      - 新增 `TtsFallbackEngine` 可测试抽象接口 + `_FlutterTtsFallbackEngine` 生产实现（`FlutterTts` 封装，带 `Completer` 完成监听与超时保护）
      - `_downloadTtsAudio()` 返回类型扩展为 `({String? filePath, int attempts, bool useFallback})`，区分降级场景（HTTP 5xx / 超时 / SocketException → `useFallback: true`；HTTP 400 / FormatException → 不降级）
      - 预加载循环 `_startPrefetchLoop()` 在 `useFallback == true` 时自动调用 `_speakWithLocalTts()` 切换至系统原生 TTS 朗读
      - 触发降级时通过 `_fallbackNotification` 字段通知 UI 层，`TtsErrorListener` 展示赛博青色 SnackBar（带霓虹边框）："云端神经网断开，已自动切换至本地仿生发声模块"
      - 降级引擎初始化失败（测试环境 `MissingPluginException`）在独立 `try/catch` 中静默吞掉，不影响主初始化链
    - **验证**: `flutter analyze` 零问题，与修改前相同的测试通过率（`+30 -5`，均为预存缺陷）
  - **[P0] Task 2: 隐私合规与权限前置拦截**
    - `StorageService` 新增 `hasAgreedPrivacy()` / `setHasAgreedPrivacy(bool)` 及持久化键 `has_agreed_privacy`
    - 新建 `lib/features/settings/presentation/widgets/privacy_agreement_modal.dart`：
      - 基于 `showCyberModal(barrierDismissible: false)` 强制拦截，用户必须主动选择
      - 弹窗包含 4 个策略节（数据存储 / 云端 TTS / 存储权限 / 隐私承诺），正文区可滚动
      - "同意接入"：霓虹青渐变主按钮；"拒绝并退出"：霓虹粉边框危险按钮 + 延迟 `exit(0)`
    - `main.dart` `_BootstrapperState`：
      - 新增 `GlobalKey<NavigatorState>` 注入 `MaterialApp.navigatorKey`，绕开 `_Bootstrapper.context` 无 `MaterialLocalizations` 的问题
      - 将原 `_bootstrap()` 拆分为 `_checkPrivacyAndBootstrap()`：先检查隐私 → 同意后才执行书籍加载和网络初始化
    - `CyberImportButton`：在调用系统文件选择器前通过 `showCyberConfirmDialog` 展示存储权限前置说明
    - **Bug Fix**: 首次运行崩溃 `No MaterialLocalizations found`，根因为 `_BootstrapperState.context` 位于 `MaterialApp` 上层；改用 `_navigatorKey.currentContext`（addPostFrameCallback 后第一帧已渲染，Navigator 已初始化）解决
    - **验证**: `flutter analyze` 四文件零问题
  - **[P0] Task 3: 大文件内存硬阻断**
    - `FileImportService` 顶层新增公开常量 `kMaxFileSizeMb = 15` 及内部字节阈值 `_kMaxFileSizeBytes`
    - 新增 `FileTooLargeException implements Exception`，`toString()` 直接返回赛博提示文案（引用常量保证一致性）：`"V1.0 神经接驳器带宽有限，暂不支持超过 15MB 的超大型数据芯片，请分割后导入"`
    - `importTxtFileStructured()` 在文件路径验证后、Isolate 启动前，立即 `File(filePath).lengthSync()` 校验文件大小，超限则 `throw const FileTooLargeException()`
    - catch 块中 `if (error is FileTooLargeException) rethrow;`，使异常穿透到 UI 层
    - `CyberImportButton` catch 块：`FileTooLargeException` 直接展示 `error.toString()`（无"导入失败:"前缀），其余错误保持原有格式
    - **验证**: `flutter analyze` 两文件零问题
  - **[P1] Task 4: 基础崩溃监控与热更新锚点**
    - 新建 `lib/core/utils/cyber_logger.dart`：
      - `recordFlutterError(FlutterErrorDetails)` 对接 `FlutterError.onError`，格式化输出 library / context / exception / stack
      - `recordPlatformError(Object, StackTrace) → bool` 对接 `PlatformDispatcher.instance.onError`，返回 `false` 保持默认崩溃行为
      - 预留 `// TODO: V1.1 接入 Sentry/Crashlytics` 注释占位，升级时只需替换 `_emit()` 实现
    - `main()` 中在 `WidgetsFlutterBinding.ensureInitialized()` 之后、`runApp()` 之前注册两个全局钩子
    - `DashboardScreen._DashboardScreenState` 新增 `initState`，通过 `addPostFrameCallback` 异步触发 `_checkAppUpdates()`（空实现存根），注释完整描述 V1.1 实现路径（GET 版本 JSON → 版本比对 → `showCyberConfirmDialog` → 强制更新开关）
    - **验证**: `flutter analyze` 三文件零问题

## **2026-04-03**

- **修复(TTS 联调与告警清理)**: 收口一批开发期告警，并为 TTS 新旧接口不匹配场景补充更明确的诊断信息。
  - **TTS 契约诊断增强**:
    - 在 `TtsEngineService._downloadTtsAudio()` 中为 POST 响应增加 JSON 形态预检查，避免将 MP3/二进制流误当作 JSON 解析后直接抛出原始 `FormatException`。
    - 当服务端返回非 JSON 内容时，明确提示当前地址可能指向旧版“直出音频”接口，客户端应接入返回 `{"status":"success","url":"..."}` 的业务接口。
    - 增加原始响应前 100 字符调试输出，便于真机联调时快速确认后端返回的是 JSON 还是音频流。
  - **Lint 与测试辅助脚本清理**:
    - 清理 `fix_tests.dart`、`fix_tests_new.dart`、`fix_tests_v3.dart` 中的字符串拼接告警，统一改为字符串插值。
    - 将辅助脚本中的 `print` 替换为 `stdout.writeln`，消除开发期 info 级提示。
    - 为 `tts_contract_test.dart`、`chapter_list_screen_test.dart`、`teleprompter_view_test.dart` 中可常量化的 `Stream.empty()` 与 `Duration` 调用补齐 `const`。

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
      - `CyberDimensions` 补充：`spacingXXS`、`teleprompterHeight`、`teleprompterMaskWidth`、`dashboardBoardBuffer`、`dashboardStatusCardMinHeight`。
      - `CyberTextStyles` 补充：`overlineTiny`、`segmentLabel`、`teleprompterInlineRead/Unread`、`teleprompterError/Placeholder`、`dashboardCounter/Separator`、`captionBold/Tight/Comfortable/Hint`。
      - `dashboard_screen.dart`：顶部工具栏、状态卡、分数计数器与吉祥物布局全部 token 化。
      - `teleprompter_view.dart`：电传屏高度、左右遮罩、中心指示线、错误提示与占位文案全部 token 化。
      - `settings_screen.dart`：说明文案、倍速芯片边框、TTS 结果面板、音量百分比、空闲暂停说明全部 token 化。

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

- **测试稳定性修复（CI flaky 收敛）**:
  - 修复 `test/features/audio/tts_engine_service_test.dart` 在 CI/全量运行下的三类不稳定问题：`path_provider` mock 指向真实系统临时目录导致初始化扫描过慢、`testConnection` 写文件失败分支的专用 mock 被构造器内 mock 覆盖、以及依赖固定 delay 的重试断言在不同机器上时序漂移。
  - 新增测试隔离临时目录 `_testTempDir`，`_makeService()` / `_makeMockService()` 统一将 `path_provider` 指向空目录，避免 `_cleanupOrphanedTtsFiles()` 扫描真实系统 temp 引发 `_voice` 尚未初始化就进入下载分支的竞态。
  - `_makeMockService()` 在返回 harness 前主动等待 `setVolume` / `setPlaybackRate` 初始化副作用落地，消除 `syncSpeedFromSettings 相同值时不更新` 被异步初始化污染的问题。
  - 将 HTTP 500 重试测试从“等待固定 delay”改为“等待 `postCalls == maxRetries`”，并仅验证指数退避延迟集合出现，降低对调度细节的脆弱依赖。
  - 调整 `testConnection 写入文件失败：step 5 应为 error` 的 mock 顺序：先创建 service，再将 `getTemporaryDirectory` 改为抛出 `PlatformException`，确保步骤 5 稳定命中 error 分支。
  - 修复一次补丁误操作导致的 `tts_engine_service_test.dart` 后半段测试块截断问题，恢复被误删的测试用例与相关辅助类引用，消除 `flutter analyze --no-fatal-infos` 中的 `unused_element` warning。
  - `merge_particle_test.dart` 保持 `pumpAndSettle` 写法验证动画完成回调，在与 TTS 套件组合运行时确认已不再被前置测试竞态拖垮。

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
