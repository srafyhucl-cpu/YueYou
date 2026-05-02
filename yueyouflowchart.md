# 阅游 (YueYou) — 完整应用流程图

> 赛博朋克风格沉浸式小说听读器 + 2048 益智游戏融合体  
> 技术栈：Flutter 3.x / Dart 3.x / Riverpod + ChangeNotifier

---

## 一、应用启动引导流程

```text
App 启动 (main())
       │
       ▼
┌──────────────────────────────────────┐
│  平台初始化                            │
│  WidgetsFlutterBinding.ensureInit()  │
│  FlutterError.onError → CyberLogger  │
│  PlatformDispatcher.onError → Logger │
└──────────────┬───────────────────────┘
               │
               ▼
┌──────────────────────────────────────┐
│  服务层串行初始化                       │
│  1. StorageService.init()            │
│     └─ SharedPreferences 单例加载     │
│  2. SfxService.init()                │
│     └─ 音效引擎预热（失败静默捕获）    │
│  3. AmbientService.init()            │
│     └─ 环境音引擎预热（失败静默捕获）  │
└──────────────┬───────────────────────┘
               │
               ▼
┌──────────────────────────────────────┐
│  CyberLogger.initSentry()            │
│  └─ SENTRY_DSN 空时静默跳过           │
│  runApp(ProviderScope → YueYouApp)   │
└──────────────┬───────────────────────┘
               │
               ▼
┌──────────────────────────────────────┐
│  _Bootstrapper (ConsumerStatefulWidget)│
│                                      │
│  initState():                        │
│  ├─ addObserver(this)  ← 生命周期监听 │
│  └─ addPostFrameCallback             │
│       └─ _checkPrivacyAndBootstrap() │
│                                      │
│  didChangeDependencies():            │
│  └─ watch(settingsProvider)          │
│       └─ _syncAmbient()             │
│          ├─ AmbientService.setEnabled│
│          ├─ AmbientService.setVolume │
│          └─ AmbientService.setStyle  │
└──────────────┬───────────────────────┘
               │
               ▼
       ┌───────────────────────────┐
       │  hasAgreedPrivacy() ?      │
       └───────┬─────────┬─────────┘
           否  │         │ 是
               ▼         ▼
   ┌───────────────┐  ┌──────────────────────────┐
   │ 隐私协议弹窗   │  │  _bootstrap()            │
   │ 用户同意 →     │  │  ├─ 读 currentNovelId    │
   │ setHasAgreed  │  │  ├─ loadBookContent()     │
   │ → _bootstrap()│  │  └─ reader.loadPreparedBook│
   └───────────────┘  └──────────────┬────────────┘
                                     │
                                     ▼
                          ┌─────────────────────┐
                          │  DashboardScreen     │
                          │  (首页仪表盘渲染完成) │
                          └─────────────────────┘
```

---

## 二、主仪表盘 (DashboardScreen) 布局结构

```text
┌───────────────────────────────────────────────────────────┐
│                   DashboardScreen                          │
│  ┌───────────────────────────────────────────────────┐    │
│  │             顶栏：书名 + 进度 + 操作按钮             │    │
│  │   [书库图标]  [书名/章节标题]  [目录] [设置]         │    │
│  └───────────────────────────────────────────────────┘    │
│                                                            │
│  ┌──────────────────────┐  ┌────────────────────────┐     │
│  │                      │  │                        │     │
│  │   2048 游戏区域       │  │   提词器 (Teleprompter) │     │
│  │   SquareBoardWidget  │  │   TeleprompterView     │     │
│  │   (RepaintBoundary)  │  │   ├─ 当前句高亮          │     │
│  │   BoardMascotWidget  │  │   ├─ 自动滚动            │     │
│  │   (赛博吉祥物 Rive)  │  │   └─ 阅读进度指示       │     │
│  │                      │  │                        │     │
│  └──────────────────────┘  └────────────────────────┘     │
│                                                            │
│  ┌───────────────────────────────────────────────────┐    │
│  │          CyberPlayerConsole (播放控制台)            │    │
│  │   [◄◄ 上句] [▶ 播放/暂停] [►► 下句] [1x/2x 倍速]  │    │
│  │   VoiceWaveform (音浪可视化)                        │    │
│  │   NeonProgressPainter (霓虹进度条)                  │    │
│  └───────────────────────────────────────────────────┘    │
│                                                            │
│  TtsErrorListener（全局错误/降级 Toast，透明覆盖层）        │
└───────────────────────────────────────────────────────────┘
                          │
          initState → _checkAppUpdates()
          └─ UpdateService.checkForUpdate()
             ├─ 有更新 → _UpdateDialog (强制/可选)
             └─ 无更新 / API 未配 → 静默跳过
```

---

## 三、书库 (Library) 模块流程

```text
用户点击 [书库图标]
       │
       ▼
showCyberModal → LibraryScreen
       │
       ├──────────────────────────────────────────┐
       │  BookshelfProvider.shelf (已有书籍列表)   │
       │  ├─ 每本书显示: 书名 + 阅读进度百分比      │
       │  └─ 长按 / 删除按钮 → deleteBook()       │
       │                                          │
       └──────────────────────────────────────────┤
                    [导入按钮]
                        │
                        ▼
           FileImportService.importTxtFileStructured()
                        │
              ┌─────────┴──────────┐
              │   文件选择器弹出     │
              │   file_picker      │
              └─────────┬──────────┘
                        │ 用户选择 .txt 文件
                        ▼
           ┌────────────────────────────────────┐
           │  文件大小检查 (> 15MB → 抛出异常)    │
           └─────────────┬──────────────────────┘
                         │ 合法
                         ▼
           ┌────────────────────────────────────┐
           │  Isolate.spawn(_parseIsolate)       │
           │  ├─ 读取文件字节 → GBK/UTF-8 解码   │
           │  ├─ 正则提取章节目录 (_chapterRegex) │
           │  └─ 返回 FileImportResult           │
           │     ├─ title: 书名                  │
           │     ├─ lines: 正文行列表             │
           │     └─ chapters: ChapterModel 列表  │
           └─────────────┬──────────────────────┘
                         │
                         ▼
           BookshelfProvider.addBook()
           ├─ 去重同名书
           ├─ 插入书架首位
           ├─ StorageService.saveBookContent()   ← path_provider 大文件
           └─ StorageService.saveBookshelf()     ← SharedPreferences 元数据

                         │
                         ▼
           用户点击书籍卡片
           ├─ StorageService.loadBookContent()
           ├─ reader.loadPreparedBook(lines, chapters, initialIndex)
           └─ 关闭书库弹窗 → 主界面更新

------- 删除书籍 -------
BookshelfProvider.deleteBook(id, reader: readerProvider)
   ├─ reader.resetForDeletedBook()  ← 级联重置阅读器 + TTS 停播
   ├─ _shelf.removeWhere(id)
   ├─ StorageService.saveBookshelf()
   ├─ StorageService.deleteBookContent()
   └─ StorageService.deleteReadingRecord()
```

---

## 四、阅读器 (Reader) 模块流程

```text
ReaderProvider (ChangeNotifier + TtsSentenceSource)
       │
       ├─ loadPreparedBook() / loadBook()
       │     ├─ TextParser.parse() (Isolate，>100KB 时)
       │     ├─ sentences 列表 → 去空行
       │     ├─ chapters 映射行索引
       │     ├─ 恢复阅读进度 (StorageService.getReadingRecord)
       │     └─ _applyLoadedBook()
       │           ├─ _currentIndex = savedCursor
       │           ├─ _fetchIndex = _currentIndex
       │           └─ TtsAudioNotifier.refreshSession() (如已启用)
       │
       ├─ 句子导航
       │     ├─ nextSentence()   → _currentIndex++ → refreshSession()
       │     ├─ previousSentence()→ _currentIndex-- → refreshSession()
       │     └─ jumpTo(index)    → 智能跳噪音 → refreshSession()
       │
       ├─ 章节跳转
       │     └─ switchChapter(index) → jumpTo(chapters[index].lineIndex)
       │
       ├─ 进度保存 (_saveProgress)
       │     ├─ StorageService.updateReadingRecord()
       │     └─ StorageService.setCurrentNovelIndex()
       │
       └─ TtsSentenceSource 接口实现
             ├─ nextTtsSentence(session) → 过滤噪音/短句/章节标题 → TtsAudioRequest
             ├─ onTtsItemStarted(item)   → _currentIndex = item.lineIndex → notifyListeners
             ├─ onTtsItemFinished(item)  → 步进 currentIndex → _saveProgress
             └─ resetFetchIndex()        → _fetchIndex = _currentIndex
```

---

## 五、TTS 音频系统 — 完整流程

### 5.1 三层架构总览

```text
╔═══════════════════════════════════════════════════════════╗
║                    UI 触发层                               ║
║  CyberPlayerConsole → ReaderProvider.toggleTTS()          ║
║  ├─ [播放/暂停]  ├─ [上一句]  ├─ [下一句]  ├─ [倍速切换]   ║
╚══════════════════╦════════════════════════════════════════╝
                   ║
                   ▼
╔══════════════════════════════════════════════════════════╗
║             TtsAudioNotifier (状态编排层)                  ║
║  Riverpod NotifierProvider                               ║
║                                                          ║
║  公开 API:                                               ║
║  play() / pause() / stopAll() / refreshSession()         ║
║  cycleSpeed() / recover() / registerSentenceSource()     ║
║                                                          ║
║  双轨并行:                                               ║
║  ┌─ _prefetchRunner ──────────────┐                      ║
║  │  后台循环，持续下载音频填充缓冲  │                      ║
║  └────────────────────────────────┘                      ║
║  ┌─ _playRunner ──────────────────┐                      ║
║  │  串行消费缓冲队列，播完即焚     │                      ║
║  └────────────────────────────────┘                      ║
║                                                          ║
║  缓冲队列: TtsAudioBuffer (maxSize = 6)                   ║
╚══════════════╦═══════════════════════════════════════════╝
               ║
               ▼
╔══════════════════════════════════════════════════════════╗
║           TtsEngineService (执行层)                       ║
║  Riverpod ChangeNotifierProvider                         ║
║                                                          ║
║  downloadAudio(request) → Isolate.run → OSS/CDN GET      ║
║  playFile(path)         → AudioPlayer (audioplayers)     ║
║  stopAudio() / pauseAudio()                              ║
║  speakWithLocalTts()    → FlutterTts 降级引擎             ║
║  syncShadow()           → 同步影子状态（供 UI 读取）       ║
║  cycleSpeed()           → 1.0x → 1.25x → 1.5x → 2.0x   ║
║  notifyUserActivity()   → 重置静默暂停计时器              ║
╚══════════════╦═══════════════════════════════════════════╝
               ║
               ▼
╔══════════════════════════════════════════════════════════╗
║           ReaderProvider (句子源 + 进度持久化)             ║
║                                                          ║
║  TtsSentenceSource 接口：提供下一句 → 回调进度 → 持久化   ║
║  StorageService：纯本地 SQLite + SharedPreferences        ║
╚══════════════════════════════════════════════════════════╝
```

### 5.2 TTS 下载契约（分离下载原则）

```text
TtsEngineService.downloadAudio(TtsAudioRequest)
       │
       ▼  Isolate.run(后台线程，不阻塞主线程)
       │
       ├─ 1. POST → Go 业务服务器
       │         Body: { text, voice, rate }
       │         Response: { "status": "success", "url": "https://cdn.../xxx.mp3" }
       │
       ├─ 2. 解析 JSON → 提取 url 字段
       │         status ≠ "success" → 抛出 TtsContractException
       │
       └─ 3. GET url → 从 OSS/CDN 下载 mp3
                 └─ 写入本地临时文件 (path_provider/temp)
                 └─ 返回本地文件路径 String

       严禁：直接将 POST 响应体当音频保存！
```

### 5.3 TTS 状态机流转

```text
                ┌─────────────────────────────┐
                │       TtsAudioIdle           │
                │  (空闲 / 引擎未启用)           │
                └──────────────┬──────────────┘
                               │ play() 首次启动
                               ▼
                ┌─────────────────────────────┐
                │      TtsAudioBuffering       │ ◄─────────────┐
                │  (预取音频 / 等待缓冲就绪)    │               │
                │  bufferedCount / targetCount │               │
                └──────────────┬──────────────┘               │
                               │ _buffer 非空                  │
                               ▼                              │
                ┌─────────────────────────────┐               │
                │       TtsAudioPlaying        │──playFile()──►│
                │  (播放中 / 消费缓冲)           │  播完下一句   │
                │  item: TtsAudioSnapshot      │               │
                └─────────┬─────────────┬─────┘               │
                          │             │                     │
                     pause()         stopAll()                │
                          ▼             ▼                     │
                ┌──────────────┐  ┌──────────────┐           │
                │TtsAudioPaused│  │ TtsAudioIdle  │           │
                │ 暂停，保留    │  │ 完全停止       │           │
                │ 缓冲 + 句子  │  │ 清空缓冲       │           │
                └──────┬───────┘  └──────────────┘           │
                       │ play() 恢复                           │
                       └───────────────────────────────────►──┘

                ┌─────────────────────────────┐
                │       TtsAudioError          │──recover()──▶ Buffering
                │  网络超时 / 契约异常 / 播放失败│
                │  recoverable: bool           │
                └─────────────────────────────┘
```

### 5.4 双轨并行时序

```text
时间线 ─────────────────────────────────────────────────────►

预加载轨道: [下载句1] [下载句2] [下载句3]     [下载句4] [下载句5]
              │         │         │               │         │
              ▼         ▼         ▼               ▼         ▼
缓冲队列:  [句1句2]  [句2句3]  [句3句4]  [句4句5]  [句5句6]

播放轨道:            [播句1]   [播句2]   [播句3]           [播句4]
                       │         │         │                │
阅后即焚:                      [删句1]   [删句2]          [删句3]
```

### 5.5 降级路径（网络失败 → FlutterTts）

```text
_prefetchRunner → downloadAudio() 连续失败
       │
       ├─ 失败 3 次（null path）
       └─ 失败 5 次（抛出异常）
              │
              ▼
       _degradeToLocal(request)
       ├─ 1. _engine.stopAudio()   ← 停远程播放器，杜绝二重唱
       ├─ 2. _engine.pauseAudio()
       ├─ 3. _isDegradedToLocal = true
       ├─ 4. _fallbackMessage = '网络音频加载失败，已切换至本地语音'
       └─ 5. _engine.speakWithLocalTts(text) ← FlutterTts 朗读 zh-CN

       恢复条件: nextTtsSentence() 返回 null (书末)
              → _isDegradedToLocal = false
              → _consecutiveFailures = 0
              → 切回远程下载
```

### 5.6 静默暂停（闲置超时）

```text
SettingsProvider.idleTimeout (分钟，0 = 永不)
       │
       ▼
TtsAudioNotifier._resetIdleTimer()
       ├─ 每次 play() / 每句开始播放 / 用户操作 notifyUserActivity() 时重置
       └─ 超时 → pause()  ← 自动执行停播
```

---

## 六、2048 游戏模块流程

```text
SquareBoardWidget (RepaintBoundary 隔离重绘)
       │
       ├─ 手势检测 (GestureDetector 上下左右滑动)
       │      │
       │      ▼
       │  GameProvider.move(direction)
       │      ├─ 矩阵位移算法（纯 Dart domain 层，零 UI 依赖）
       │      ├─ 合并同色方块，生成得分
       │      ├─ 随机生成新方块 (2 或 4)
       │      ├─ 检查胜负条件
       │      └─ notifyListeners → UI 重建（Transform 动画，不改宽高）
       │
       ├─ BoardMascotWidget (Rive 动画)
       │      └─ GlobalKey<BoardMascotState> 持有于 State 层
       │         避免每次 build 重建导致 Rive 控制器重置
       │
       └─ 分数面板
              ├─ 当前分 (score)
              ├─ 最高分 (bestScore) ← StorageService.loadBestScore()
              └─ 连击数 (combo)
```

---

## 七、设置 (Settings) 模块流程

```text
用户点击 [设置图标]
       │
       ▼
showCyberModal → SettingsScreen
       │
       ├─ TTS 开关 (storyTts)
       │     └─ SettingsProvider.setStoryTts() → StorageService → notifyListeners
       │
       ├─ 音色选择 (voice)
       │     └─ setVoice() → 校验白名单 → TtsEngineService.syncSettingsFromProvider()
       │
       ├─ 倍速 (ttsRate)
       │     └─ setTtsRate() → 下次 refreshSession 生效
       │
       ├─ 静默暂停时长 (idleTimeout)
       │     └─ setIdleTimeout() → TtsAudioNotifier._resetIdleTimer()
       │
       ├─ 环境音设置 (ambientEnabled / ambientVol / ambientStyle)
       │     └─ _Bootstrapper.didChangeDependencies() → AmbientService.set*()
       │
       └─ 动画质量 (animationQualitySetting)
             ├─ 'auto'   → CyberPerformanceDetector.detectLevel()
             ├─ 'high'   → CyberAnimationLevel.high
             ├─ 'medium' → CyberAnimationLevel.medium
             └─ 'low'    → CyberAnimationLevel.low
```

---

## 八、音频服务矩阵

```text
服务                   职责                             生命周期
─────────────────────────────────────────────────────────────────
TtsEngineService       TTS 下载 + 播放 + 降级            Riverpod ChangeNotifier
TtsAudioNotifier       状态机编排 + 双轨泵                Riverpod Notifier
AmbientService         背景环境音（static）               App 生命周期（切后台暂停）
SfxService             UI 音效（static）                  App 启动时预热
```

---

## 九、持久化存储层

```text
StorageService (SharedPreferences + path_provider)
       │
       ├─ SharedPreferences (小数据)
       │     ├─ 书架元数据 (local_bookshelf)
       │     ├─ 阅读进度 (reading_records)
       │     ├─ 当前书 ID/游标 (current_novel_id / novel_index)
       │     ├─ 游戏状态 (local_save_data, bestScore, maxCombo)
       │     ├─ 隐私协议状态 (has_agreed_privacy)
       │     └─ 所有设置项 (setting_*)
       │
       └─ path_provider (大文件)
             ├─ 书籍正文内容 ({id}.json)
             └─ TTS 临时音频文件 (temp/*.mp3) ← 阅后即焚
```

---

## 十、Provider 依赖拓扑

```text
settingsProvider (ChangeNotifierProvider)
       │
       ├──────────────────────────────────────────┐
       │                                          │
       ▼                                          ▼
ttsEngineProvider (ChangeNotifierProvider)   [UI 读取动画质量/环境音]
       │
       ├─ ref.listen → TtsAudioNotifier.syncSettingsFromProvider()
       │
       ▼
ttsAudioProvider (NotifierProvider<TtsAudioState>)
       │
       ├─ ref.read(ttsEngineProvider)
       └─ registerSentenceSource(readerProvider)
              │
              ▼
       readerProvider (ChangeNotifierProvider)
              ├─ ref.read(ttsEngineProvider)
              └─ ref.read(ttsAudioProvider.notifier)

bookshelfProvider (ChangeNotifierProvider)
       └─ StorageService (纯静态，无依赖)
```

---

## 十一、应用生命周期管理

```text
AppLifecycleState.paused / inactive
       └─ AmbientService.pause()  ← 切后台停止环境音

AppLifecycleState.resumed
       └─ AmbientService.resume() ← 切前台恢复环境音

AppLifecycleState.detached / hidden
       └─ AmbientService.dispose() ← 完全释放资源

Pointer 事件（任意触摸）
       └─ TtsEngineService.notifyUserActivity()
              └─ TtsAudioNotifier._resetIdleTimer() ← 重置静默计时
```

---

## 十二、关键文件索引

| 层级 | 文件 | 职责 |
|------|------|------|
| 入口 | `lib/main.dart` | App 初始化、Provider 挂载、生命周期观察 |
| UI | `lib/features/dashboard/presentation/dashboard_screen.dart` | 主仪表盘（游戏+提词器+控制台） |
| UI | `lib/features/library/presentation/screens/library_screen.dart` | 书库管理界面 |
| UI | `lib/features/reader/presentation/screens/chapter_list_screen.dart` | 章节目录界面 |
| UI | `lib/features/settings/presentation/screens/settings_screen.dart` | 设置界面 |
| UI | `lib/features/audio/presentation/widgets/cyber_player_console.dart` | TTS 播放控制台 |
| 状态 | `lib/features/audio/providers/tts_audio_notifier.dart` | TTS 状态机编排层（双轨泵） |
| 状态 | `lib/features/reader/providers/reader_provider.dart` | 阅读器状态 + 句子源实现 |
| 状态 | `lib/features/library/providers/bookshelf_provider.dart` | 书架状态管理 |
| 状态 | `lib/features/settings/providers/settings_provider.dart` | 全局设置状态 |
| 状态 | `lib/features/game_2048/providers/game_provider.dart` | 2048 游戏状态 |
| 执行 | `lib/features/audio/services/tts_engine_service.dart` | TTS 下载/播放/降级/影子状态 |
| 执行 | `lib/features/audio/services/ambient_service.dart` | 环境音管理 |
| 执行 | `lib/features/audio/services/sfx_service.dart` | UI 音效管理 |
| 执行 | `lib/features/library/services/file_import_service.dart` | 书籍导入（Isolate 解析） |
| 领域 | `lib/features/audio/domain/tts_audio_state.dart` | TTS 密封状态树 (5 节点) |
| 领域 | `lib/features/audio/domain/tts_audio_buffer.dart` | 缓冲队列纯领域逻辑 |
| 领域 | `lib/features/audio/domain/tts_audio_models.dart` | TtsAudioItem / TtsSentenceSource 接口 |
| 领域 | `lib/features/reader/domain/text_parser.dart` | 文本解析（Isolate compute） |
| 基础 | `lib/core/database/storage_service.dart` | 全量本地持久化（SharedPreferences + 文件） |
| 基础 | `lib/core/theme/cyber_colors.dart` | 赛博朋克色板（唯一颜色来源） |
| 基础 | `lib/core/config/tts_config.dart` | TTS 服务器地址配置（--dart-define 注入） |
| 基础 | `lib/core/utils/cyber_logger.dart` | 全局日志 + Sentry 错误上报 |
| 共享 | `lib/shared/widgets/tts_error_listener.dart` | 全局 TTS 错误/降级 Toast |
