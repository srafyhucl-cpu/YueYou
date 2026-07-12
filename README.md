# 阅游 (YueYou)

**赛博朋克风格的沉浸式小说听读器 + 2048 游戏**  
版本 `v1.1.1` · Flutter 3.x / Dart 3.x · 跨平台（Android / iOS / Windows / macOS / Linux / Web）

[![Flutter CI](https://github.com/srafyhucl-cpu/YueYou/actions/workflows/flutter-ci.yml/badge.svg)](https://github.com/srafyhucl-cpu/YueYou/actions/workflows/flutter-ci.yml)

---

## ✨ 核心特性

### 📖 阅读引擎

- **云端 TTS（两步下载）**：POST 业务服务器获取 JSON `{"status":"success","url":"..."}` → GET 通过短效签名 URL 下载 `.mp3` → 本地缓存；客户端严格遵循分离下载契约，不直接消费响应体字节流
- **本地 TTS 降级**：云端 HTTP 5xx / 超时 / 网络异常时自动切换至系统 `flutter_tts` 朗读，CyberToast 赛博青色通知用户
- **生产者-消费者预加载**：最多 6 句缓冲队列，指数退避重试（最大 2 次，800ms 基础延迟），无卡顿连续朗读
- **会话哨兵 (Session Sentry)**：通过 `BufferedAudio` 会话标识与 Completer 强制中断机制，解决切换发声人/章节时的延迟与旧声音残留问题
- **TTS 错误全局监听**：`TtsErrorListener` 通过 `MaterialApp.builder` 挂载根节点，统一展示赛博风格顶部 CyberToast
- **KTV 提词器**：`TeleprompterView` 逐字扫光动画，`AnimationController` 驱动平滑滚动，高亮/暗色双轨渲染
- **章节导航**：`ChapterListScreen` 正序/倒序切换，O(1) 定位当前章节
- **空闲自动暂停**：可配置超时计时器（`idleTimeout`），防止忘关持续耗电
- **阅读进度持久化**：实时存档，重启自动恢复至上次段落与滚动位置
- **本地书签**：播放器控制台可标记当前句，书签仅保存行号并随书籍加载恢复

### 📚 默认书籍（西游记）

- **目录先行**：App 启动时从服务端拉取 100 章目录，网络异常时降级使用内置常量（`BookConstants`）
- **分章懒加载**：`DefaultBookService` 按需下载章节正文（OSS CDN），三级缓存（内存 → 本地文件 → 网络），影子预读下一章
- **跨章自动推进**：`ReaderProvider` 章末状态机，TTS 播完最后一句自动加载下一章并续播
- **新用户零配置**：书架为空时自动注入默认书籍，粘性位 `hasSelectedBook` 防止老用户被重置

### 📚 书库管理

- **文件导入**：系统文件选择器选定 TXT 后由 `FileImportService` 基于 `Isolate.spawn` 流式读取，
  主线程仅传文件路径，内存零拷贝；自动朗读开启时导入完成即开始播放
- **编码自动识别**：采样前 8KB → UTF-8 严格校验 → GBK 容错解码 → UTF-8 宽松兜底，三层覆盖
- **BOM 跳过**：`File.openRead(3)` 直接偏移，无需内存拷贝
- **大文件拦截**：超过 15MB 抛出 `FileTooLargeException`，Isolate 启动前即拦截
- **取消导入**：令牌机制 `_activeImportToken`，取消时旧 Isolate 返回值自动丢弃，无脏状态
- **级联删除**：删除书籍时联动停止 TTS、清空阅读进度，防止幽灵章节

### 🎮 2048 游戏

- **完整游戏逻辑**：`GameProvider` 完整复刻自旧版 Web 端 JS 引擎，滑动合并 + Combo 连击计分
- **赛博视觉方块**：`TileWidget` 11 级渐变配色 + 动态霓虹光晕 + 合并弹性缩放（120ms，1.0→1.15→1.0）+ 粒子爆炸
- **棋盘 3D 倾斜**：每次滑动触发 `Matrix4` 倾斜动画（约 5°），增强物理手感
- **漂浮加分**：`FloatingScore` 组件，合并时数字飘出并淡出
- **游戏结束雨幕**：`RainEffect` 在 Game Over 弹窗背景营造赛博朋克雨夜氛围
- **棋盘重置动画**：`BoardResetAnimation` 在新局开始时触发翻转过渡动画
- **XIAOYO 吉祥物**：`BoardMascot` Canvas 自绘，眼球实时跟随滑动方向，合并时欢呼，游戏结束时同情
- **战绩分享**：Game Over 弹窗展示得分/最大棋子/最高连击/评级，一键复制战绩文案至剪贴板
- **持久化防抖**：1 秒防抖合并多次写入，App 切后台时 `flushPersistState()` 强制落盘，防止丢档
- **陪伴模式可关闭**：设置中关闭“2048 陪伴模式”后，主界面只保留听读内容
- **🔓 黑客后门彩蛋**：连续点击同一方块 8 次触发自毁程序——三段式崩塌动画（膨胀 1.0→1.3 + 坍缩 easeInBack + opacity 淡出 + 微旋转 0.25 rad）+ 粉红霓虹粒子爆炸，1.5s 无操作自动清零点击计数

### 🔊 音效系统

- **SfxService V4**：基于旧版 Web Audio API 解析式 Chirp 公式 `φ(t)=2π(f₀t+(f₁-f₀)t²/2T)` 移植，零相位突变，4 阶段递进（≤16 / ≤128 / ≤1024 / >1024），440→880Hz 上行扫频
- **分级触觉反馈**：方块数值越高震动强度越大

### ⚙️ 设置与合规

- **隐私前置启动闸门**：首次启动未同意或隐私政策版本发生变化时只展示独立 `ConsentApp`，不初始化 Sentry、业务 `ProviderScope`、Dashboard、TTS、音效、环境音、默认书恢复或更新检查；同意后才进入完整应用
- **授权撤回**：设置页可撤回隐私授权，撤回后清理第三方会话状态并在下次启动重新确认
- **Android 备份边界**：Release Manifest 显式 `android:allowBackup="false"`，并通过 `dataExtractionRules` 排除本地文件、数据库和偏好设置，防止阅读进度、书籍正文、设置和 TTS 缓存进入系统自动备份或设备迁移
- **TTS 参数**：语速（`ttsRate`）、音色选择（`voice`）
- **游戏音效开关**：实时同步至 `GameProvider`
- **多风格环境音**：`AmbientService` 支持"江湖风云（武侠）"与"围炉夜话（温馨）"，算法动态生成粉噪声，无需外部音频资源

### 🎨 设计系统

- **全 Token 化**：所有颜色、字号、间距、圆角、模糊值均通过 `CyberColors` / `CyberTextStyles` / `CyberDimensions` 统一管理。
- **全域错误集中化**：通过 `CyberErrorMessages` 全局收口所有报错文本，移除魔法字符串，支持极致脱敏与拟人化表达。
- **沉浸式反馈系统**：`CyberToast` 深度集成 XIAOYO 吉祥物 PFP，将系统通知转化为拟人化对话气泡，强化赛博朋克极客交互氛围。
- **毛玻璃弹窗**：`CyberModal` + `BackdropFilter`，支持 `barrierDismissible` 控制。
- **交互式设计预览**：`docs/ui-demo/` 提供基于当前 Flutter 页面结构的 UI 设计系统 Demo，可用于回迁前验证主仪表盘、书架、章节、设置与 TTS 控制台视觉方向。
- **崩溃监控锚点**：`CyberLogger` 挂接 `FlutterError.onError` + `PlatformDispatcher.instance.onError`，预留 Sentry/Crashlytics 接入位。

---

## 🚧 开发中 / 待完善

| 功能 | 文件 | 状态 |
| :--- | :--- | :--- |
| XIAOYO Rive 动画版 | `board_mascot_rive.dart` + `assets/rive/xiaoyo.riv` | Rive 文件已就位，UI 接入中 |
| 崩溃上报（Sentry/Crashlytics） | `core/utils/cyber_logger.dart` | 同意隐私政策后初始化，撤回授权时关闭会话 |
| 热更新版本检查 | `DashboardScreen._checkAppUpdates()` | 存根已注册，V1.1 实现 |

---

## 🏗️ 技术架构

### 核心技术栈

| 层次 | 技术 | 用途 |
| :--- | :--- | :--- |
| UI 框架 | Flutter 3.x / Dart 3.x | 跨平台渲染 |
| 状态管理 | Riverpod 2.x (`Notifier` + `ChangeNotifierProvider`) | 全局与局部状态 |
| 本地持久化 | SharedPreferences | 设置、游戏存档 |
| 文件存储 | path_provider + File System | 小说正文、TTS 音频缓存 |
| 云端 TTS | http + audioplayers | 两步下载 + 流式播放 |
| 本地 TTS | flutter_tts | 云端降级兜底 |
| 大文件解析 | Isolate.spawn | 流式读取，主线程零阻塞 |
| 吉祥物动画 | Rive 0.13.x | XIAOYO 骨骼动画（集成中） |
| 编码支持 | fast_gbk | GBK 小说文件 |
| 屏幕常亮 | wakelock_plus | TTS 朗读期间保持亮屏 |
| 外链跳转 | url_launcher | 隐私政策等外部链接 |

### 目录结构

```text
lib/
├── core/                          # 全局基础设施（严禁引入任何 feature 层代码）
│   ├── config/
│   │   └── tts_config.dart        # TTS 服务器地址（--dart-define 注入）
│   ├── database/
│   │   └── storage_service.dart   # 全局 SharedPreferences 封装
│   ├── theme/
│   │   ├── cyber_colors.dart      # 霓虹色板（零硬编码颜色）
│   │   ├── cyber_animation_scope.dart # 共享 UI 动画等级上下文
│   │   ├── cyber_dimensions.dart  # 间距、圆角、模糊值 token
│   │   ├── cyber_shadows.dart     # 预设 BoxShadow 组合
│   │   └── cyber_text_styles.dart # 字体样式 token
│   └── utils/
│       ├── cyber_logger.dart      # 全局崩溃钩子与 Sentry 会话控制
│       ├── safe_string.dart       # safeSubstring 防越界
│       └── ...
├── features/
│   ├── audio/
│   │   ├── providers/
│   │   │   └── tts_engine_provider.dart # TTS Provider 生命周期装配
│   │   ├── services/
│   │   │   ├── tts_engine_service.dart  # 云端 TTS 引擎（两步下载 + 降级）
│   │   │   └── sfx_service.dart         # 游戏音效（V4 Chirp 公式）
│   │   └── presentation/
│   │       └── widgets/
│   │           ├── cyber_player_console.dart  # 播放控制台
│   │           ├── neon_progress_painter.dart # 霓虹进度条
│   │           └── voice_waveform.dart        # 声波可视化
│   ├── dashboard/
│   │   └── presentation/
│   │       └── dashboard_screen.dart    # 主界面（吉祥物 + 棋盘 + 控制台）
│   ├── game_2048/
│   │   ├── domain/
│   │   │   ├── game_engine.dart         # 纯 Dart 棋盘、移动、合并与结束判断
│   │   │   └── tile_model.dart          # 方块数据模型
│   │   ├── providers/
│   │   │   └── game_provider.dart       # 游戏编排、随机数、持久化与副作用
│   │   └── presentation/
│   │       └── widgets/
│   │           ├── square_board.dart         # 棋盘主组件（Transform 位移动画）
│   │           ├── tile_widget.dart          # 方块（合并动画 + 黑客彩蛋）
│   │           ├── board_mascot.dart         # XIAOYO 吉祥物（Canvas）
│   │           ├── board_mascot_rive.dart    # XIAOYO Rive 版（集成中）
│   │           ├── merge_particle.dart       # 合并粒子特效
│   │           ├── floating_score.dart       # 漂浮加分动画
│   │           ├── rain_effect.dart          # Game Over 雨幕特效
│   │           └── board_reset_animation.dart # 新局翻转动画
│   ├── library/
│   │   ├── domain/book_model.dart
│   │   ├── services/
│   │   │   └── file_import_service.dart  # Isolate 流式导入（GBK/UTF-8）
│   │   ├── providers/
│   │   │   └── bookshelf_provider.dart   # 书架状态 + 级联删除
│   │   └── presentation/
│   │       ├── screens/library_screen.dart
│   │       └── widgets/cyber_import_button.dart
│   ├── reader/
│   │   ├── domain/
│   │   │   └── text_parser.dart          # 智能断句（严禁引入 material.dart）
│   │   ├── providers/
│   │   │   └── reader_provider.dart      # 阅读状态 + TTS 调度
│   │   └── presentation/
│   │       ├── screens/chapter_list_screen.dart
│   │       └── widgets/teleprompter_view.dart  # KTV 提词器
│   └── settings/
│       ├── providers/settings_provider.dart
│       └── presentation/
│           ├── screens/settings_screen.dart
│           └── widgets/privacy_agreement_modal.dart  # 隐私协议内容组件
├── app/
│   └── composition/
│       ├── app_bootstrapper.dart    # 跨 feature 应用装配与生命周期连接
│       └── tts_error_listener.dart  # 应用级 TTS 错误到 Toast 适配
├── shared/
│   └── widgets/
│       ├── cyber_modal.dart          # 毛玻璃弹窗基础组件
│       ├── cyber_confirm_dialog.dart # 确认弹窗
│       ├── cyber_toast.dart          # 赛博风格顶部提示
│       ├── neon_border_box.dart
│       └── safe_padding_wrap.dart
└── main.dart                         # 隐私启动闸门、ProviderScope 树、应用入口壳
```

`shared/widgets` 只依赖 Flutter、`core` 和其他共享组件；跨 feature 的 Provider、生命周期和
错误提示连接统一放在 `app/composition`。该边界由 AI 工程门禁自动检查。

### 数据流

```text
UI (Consumer / context.watch)
    → Notifier / ChangeNotifierProvider
        → Service / StorageService
            → SharedPreferences / 文件系统 / OSS CDN
                         ↑
               domain/ 纯业务逻辑（Isolate 隔离大文件）
```

---

## 🚀 快速开始

### 环境要求

- Flutter SDK ≥ 3.41.0
- Dart SDK ≥ 3.5.0

### 安装依赖

```bash
flutter pub get
```

### 运行（使用默认 TTS 服务器）

```bash
flutter run
```

### 运行（指定远端 TTS 服务器）

```bash
flutter run --dart-define=TTS_SERVER_URL=http://your-server/api/v1/tts
```

### VS Code / Windsurf 原生调试

在项目根目录创建 `.vscode/launch.json`：

```json
{
  "configurations": [
    {
      "name": "yueyou (Flutter Device)",
      "request": "launch",
      "type": "dart",
      "deviceId": "你的设备ID",
      "toolArgs": [
        "--dart-define=TTS_SERVER_URL=http://your-server/api/v1/tts"
      ]
    }
  ]
}
```

### 构建 Release APK

Release 构建必须使用正式签名，禁止回退 debug 签名。签名参数只能来自未跟踪的
`android/key.properties`，或 CI Secret 注入的 `ANDROID_STORE_FILE`、
`ANDROID_STORE_PASSWORD`、`ANDROID_KEY_ALIAS`、`ANDROID_KEY_PASSWORD`。
GitHub Actions 手动发布任务使用 `ANDROID_KEYSTORE_BASE64` 生成临时 keystore，
再通过上述 Secret 注入签名参数，构建结束后仅上传 APK 与 SHA-256。
Windows 首次构建前应把 Gradle 缓存放到非 C 盘，例如
`$env:GRADLE_USER_HOME="D:\Temp\gradle-cache"`；同时使用 JDK 17+，例如
`$env:JAVA_HOME="D:\Work\Java\jdk-17.0.19+10"`。

```bash
# 只打 arm64-v8a 轻量包（约 28MB，覆盖 90%+ 主流机型）
flutter build apk --release \
  --target-platform android-arm64 \
  --split-per-abi \
  --dart-define=TTS_SERVER_URL=https://hclstudio.cn/api/v1/tts \
  --dart-define=BOOK_API_BASE=https://hclstudio.cn/api/v1 \
  --dart-define=APP_VERSION=1.1.1
```

服务端生产部署使用 `server/` 交叉编译为 Linux amd64，由 `yueyou.service` 托管；
Nginx 反代配置模板位于 `deploy/nginx/yueyou-hclstudio.conf`。TTS 临时对象使用私有
OSS Bucket，`cache/tts/v2/` 生命周期目标为 24 小时内自动清理。

### 代码检查

```bash
flutter analyze
dart analyze test
dart scripts/ai_code_checker.dart
```

---

## ✅ 测试与覆盖率

### 运行测试

```bash
flutter test --concurrency=1
```

当前覆盖 **697 个通过用例**（另有 4 个已登记跳过项），涵盖 `GameProvider`、`TtsEngineService`（含降级）、`TextParser`、`BookshelfProvider`、`ReaderProvider`、`FileImportService`、`StorageService` 和服务端契约等核心模块。

### 生成覆盖率报告

```bash
flutter test --coverage --concurrency=1
python scripts/check_coverage_gate.py --overall 80 --core 90
genhtml coverage/lcov.info -o coverage/html
# 打开 coverage/html/index.html
```

### CI 集成

仓库配置了 GitHub Actions（`.github/workflows/flutter-ci.yml`），Push / PR 时自动执行：

- `flutter analyze`
- `dart analyze test`
- `dart scripts/ai_code_checker.dart`
- `flutter test --coverage --concurrency=1`
- `python scripts/check_coverage_gate.py --overall 80 --core 90`
- `cd server && go test ./... && go test -race ./... && go vet ./... && go build ./...`

覆盖率文件 `coverage/lcov.info` 作为 Artifact 上传，任一分析、测试、覆盖率或服务端门禁失败都会阻断合并。
手动触发 `workflow_dispatch` 时，CI 会额外构建 arm64 Release APK 并上传 APK 与 SHA-256。

共享 API JSON 契约样例位于 `docs/contracts/`，Go 服务端测试与 Flutter 客户端测试会读取同一批样例，防止响应字段漂移。

### 测试约定

- 持久化测试：`SharedPreferences.setMockInitialValues({})` + `StorageService.resetForTesting()` 保证隔离
- 平台插件测试：通过 `test/utils/test_utils.dart` 集中初始化 6 组 `MethodChannel` mock（path_provider / audioplayers / wakelock / haptic / platform / system_sound）
- 异步测试：`fake_async` + `mockito` 模拟 HTTP 客户端与音频播放器

---

## ⚙️ 服务器配置

TTS 服务器地址通过 `--dart-define` 编译期注入，**代码中严禁硬编码任何服务器 IP**。

| 变量 | 说明 | 默认值 |
| :--- | :--- | :--- |
| `TTS_SERVER_URL` | TTS 业务接口（返回 JSON `{"status":"success","url":"..."}`) | `https://hclstudio.cn/api/v1/tts` |
| `BOOK_API_BASE` | 书籍服务 API 基础地址（目录 + 章节派发） | `https://hclstudio.cn/api/v1` |

客户端会为 TTS POST 附带本地随机 `X-YueYou-Install-ID`，仅用于服务端匿名限流。

### 应用外链配置

| 变量 | 说明 | 默认值 |
| :--- | :--- | :--- |
| `MARKET_DOWNLOAD_URL` | 版本更新弹窗跳转的应用市场地址 | `https://play.google.com/store/apps/details?id=com.yueyou.app` |

### 服务端 TTS 安全配置

| 变量 | 说明 | 默认值 |
| :--- | :--- | :--- |
| `YUEYOU_OSS_EP` | OSS 上传端点，生产建议内网端点 | `oss-cn-beijing-internal.aliyuncs.com` |
| `YUEYOU_OSS_SIGN_EP` | OSS 签名下载端点，必须客户端可访问 | `oss-cn-beijing.aliyuncs.com` |
| `YUEYOU_TTS_OBJECT_SECRET` | TTS 临时对象键 HMAC 密钥 | 回退 `YUEYOU_AKSEC` |
| `YUEYOU_TTS_SIGNED_URL_TTL_SECONDS` | TTS 签名下载 URL 有效期 | `600` |
| `YUEYOU_TTS_MAX_BODY_BYTES` | TTS POST 请求体字节上限 | `16384` |
| `YUEYOU_TTS_IP_LIMIT_PER_MIN` | 单 IP 每分钟 TTS 请求上限 | `30` |
| `YUEYOU_TTS_ID_LIMIT_PER_HOUR` | 单匿名安装 ID 每小时 TTS 请求上限 | `120` |

> 客户端拿到 `url` 字段后，再通过 GET 请求从 OSS 下载音频文件存入本地缓存。**禁止将 POST 响应体直接保存为音频文件。**TTS 音频对象使用私有 ACL 和短效签名 URL；生产环境还必须为 `cache/tts/v2/` 配置 24 小时生命周期清理。

### 书籍接口

| 接口 | 方法 | 说明 |
| :--- | :--- | :--- |
| `/api/v1/book/catalog?bookId=xiyouji` | GET | 返回书籍目录 JSON（100 章标题 + lineIndex） |
| `/api/v1/book/chapter` | POST `{bookId, chapterIndex}` | 返回章节 OSS CDN URL，客户端再 GET 下载正文 |

### TTS 核心参数（`TtsConfig`）

| 参数 | 默认值 | 说明 |
| :--- | :--- | :--- |
| `requestTimeout` | 8s | 单次请求超时 |
| `maxRetries` | 2 | 最大重试次数 |
| `baseRetryDelay` | 800ms | 指数退避基础延迟 |
| `maxPrefetchQueue` | 6 | 预加载队列上限 |

### Android 明文流量

使用 HTTP 协议时需在 `AndroidManifest.xml` 中配置：

```xml
<application android:usesCleartextTraffic="true">
```

---

## 📦 依赖清单

### 运行时依赖

```yaml
flutter_riverpod: ^2.6.1   # 状态管理
shared_preferences: ^2.3.3 # 本地持久化
file_picker: ^8.1.7        # 文件导入
http: ^1.6.0               # TTS HTTP 请求
audioplayers: ^6.4.0       # TTS 音频播放
flutter_tts: ^3.8.5        # 本地 TTS 降级引擎
path_provider: ^2.1.5      # 文件路径（存储 + 缓存）
fast_gbk: ^1.0.0           # GBK 编码小说支持
wakelock_plus: ^1.4.0      # 朗读时屏幕常亮
rive: ^0.13.14             # XIAOYO 吉祥物动画
marquee: ^2.3.0            # 跑马灯文字
equatable: ^2.0.8          # 值对象相等比较
url_launcher: ^6.3.0       # 外部链接（隐私政策）
```

### 开发依赖

```yaml
mockito: ^5.4.4            # Mock 对象
fake_async: ^1.3.1         # 虚拟异步时间
flutter_lints: ^4.0.0      # 代码规范
flutter_launcher_icons: ^0.14.3  # 应用图标生成
```

---

## 🎨 主题系统

### `CyberColors` 色板

```dart
// 霓虹主色
neonCyan    #22D3EE  // 青色（主要交互）
neonPink    #FE019A  // 粉色（强调 / 彩蛋危险色）
neonPurple  #8B5CF6  // 紫色（次要）
neonGreen   #00FF41  // 绿色（成功）
hackerBlue  #00F3FF  // 骇客蓝（吉祥物 / 特效）
tileGold    #FFD700  // 金色（传奇光晕）

// 毛玻璃底层
background        #0A0A0F
panelBackground   #0D0E18
surface           #1A1B28

// 语义化透明度
whiteHigh / whiteMedium / whiteDim / whiteMuted / whiteFaint
blackOverlay / blackShadow / blackDim
```

### `CyberDimensions` 间距体系（4px 网格）

```dart
spacingXXS=2 / spacingXS=4 / spacingS=8 / spacingMS=12 / spacingM=16 / spacingL=24 / spacingXL=32
radiusS=6 / radiusM=8 / radiusL=16 / radiusXL=24
borderNormal=1.0 / borderThick=1.5
blurLight=8 / blurStrong=16
```

### `CyberTextStyles` 字体

```dart
CyberTextStyles.monoFont            // 等宽字体（JetBrains Mono）
CyberTextStyles.teleprompterActive  // 提词器当前句高亮
CyberTextStyles.teleprompterDim     // 提词器其余句暗色
CyberTextStyles.dashboardCounter    // 主界面分数计数器
CyberTextStyles.captionBold         // 说明文字加粗
```

> **字体文件**：将 JetBrains Mono `.ttf` 放入 `assets/fonts/` 并在 `pubspec.yaml` 中声明，否则回退系统默认字体。

---

## 🎯 开发规范

为了保持代码质量，项目严格遵循以下文档：

- [核心业务流程](DevelopmentPlan/核心业务流程.md)
- [模块依赖边界](DevelopmentPlan/模块依赖关系.md)
- [贡献指南](贡献指南.md)

项目硬性红线（详见 `CLAUDE.md` 与 `.agents/skills/`）：

- ✅ **零硬编码颜色/尺寸**：所有视觉 token 必须来自 `CyberColors` / `CyberDimensions` / `CyberTextStyles`
- ✅ **domain 层纯 Dart**：`features/*/domain/` 下严禁引入 `flutter/material.dart`
- ✅ **build() 纯函数**：禁止在 `build()` 或动画 `builder` 内产生副作用，须在 `initState` / `addListener` 中处理
- ✅ **Transform 驱动动画**：禁止用改变宽高/边距做动画，必须使用 `Transform.scale` / `Transform.translate` / `Opacity`（GPU 加速）
- ✅ **RepaintBoundary 隔离**：棋盘、吉祥物、提词器等高频重绘区域必须包裹 `RepaintBoundary`
- ✅ **Isolate 大文件**：>100KB 文本解析必须通过 `Isolate.spawn`（参考 `FileImportService`）
- ✅ **服务器地址外置**：通过 `--dart-define` 注入 `TtsConfig`，禁止硬编码 IP
- ✅ **TTS 分离下载契约**：客户端只能 POST→JSON→GET 下载，严禁将响应体直接保存为音频
- ✅ **纯本地用户数据**：阅读进度与设置严禁上传服务端，只存本地；Android 自动备份与设备迁移默认禁用
- ✅ **会话锁防竞态**：TTS 播放/预加载循环用递增 `_loopSession` 防止并发多循环

---

## 📄 许可证

MIT License
