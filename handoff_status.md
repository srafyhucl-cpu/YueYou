# 阅游 Flutter 重构 - 1:1 全量进度对齐交接文档

## 🛡️ 绝对保护区 (DO NOT TOUCH)
以下核心模块已完美实现，**绝对不能修改其基础架构和状态机逻辑**：
1. `GameProvider` (2048 核心逻辑)
2. `ReaderProvider` (提词器中枢)
3. `TextParser` (Isolate 多线程切片引擎)
4. ~~`TtsEngineService` (基于 flutter_tts 的发声引擎)~~ → **已升级为双轨流媒体引擎 (audioplayers + http)**
5. `FileImportService` (基于 file_selector 的不死解码文件导入)

## 📝 最新完成任务 (2026-03-20)

### ✅ 任务1: 移除2048合并放大效果
- **文件**: `lib/features/game_2048/presentation/widgets/tile_widget.dart`
- **修改**: 将 `StatefulWidget` 改为 `StatelessWidget`，完全移除 `ScaleTransition` 动画
- **原因**: 用户反馈合并放大效果不符合预期，要求保持简洁

### ✅ 任务2: 修复TTS播放卡死问题
- **文件**: `lib/features/audio/services/tts_engine_service.dart`
- **问题**: MediaPlayer频繁创建销毁导致资源泄漏，播放卡死
- **修复**: 
  - 在播放前添加 `await _audioPlayer.stop()` 清理旧资源
  - 重用同一个 `AudioPlayer` 实例，避免频繁创建销毁
  - 修复TTS请求方法从GET改为POST（与旧代码保持一致）

### ✅ 任务3: 全面优化主页面UI效果
- **文件**: `lib/features/dashboard/presentation/dashboard_screen.dart`
- **优化内容**:
  - 添加背景径向渐变效果（青色+紫色）
  - 增强状态卡片毛玻璃效果（blur 15→20）
  - 状态卡片添加渐变背景和青色边框光晕
  - 优化数字计数器颜色（白色→青色，增强发光效果）
  - 优化重置按钮样式（添加渐变和边框）
  - 调整间距布局，提升视觉层次

## 🚀 TTS引擎重大升级 (双轨流媒体架构)

### 架构变更
- **旧引擎**: `flutter_tts` (本地TTS)
- **新引擎**: `audioplayers` + `http` + `path_provider` (远端流媒体)
- **服务器**: `http://8.218.177.149:3000/api/v1/tts/createStream`

### 核心特性
1. **生产者/消费者双轨预加载模型**
   - 生产者轨道: HTTP下载MP3到临时文件，队列最大3个
   - 消费者轨道: 播放队列中的文件，播完自动删除
2. **会话锁机制**: `_loopSession` 控制任务生命周期
3. **无缝连播**: 使用 `Completer` 等待播放完成
4. **API兼容层**: 保留 `getVoices()` 等接口，写死返回音色列表

### 依赖安装
```bash
flutter pub add audioplayers http path_provider
```

### Android配置
在 `AndroidManifest.xml` 添加HTTP明文流量权限：
```xml
<application android:usesCleartextTraffic="true">
```

## 🎯 你的全局重构任务 (核心业务与底层逻辑 1:1 对齐)
我们的当前目标是：**先实现与旧版代码库 100% 的进度和功能对齐，严禁做任何偏离旧版业务逻辑的“提前优化”。**
你需要全面扫描旧版 `www/js/` 目录，找出所有还没迁移的“底层业务/数据逻辑”以及“配套界面”，并进行完整复刻：

1. **底层数据/后端交互层 (Data & Backend)**：深度复刻旧版中所有的本地存储逻辑 (如 `LocalDB.js`)、书签/阅读历史列表的维护、用户全局配置项等。使用 Flutter 的等效方案（如 `shared_preferences` 或本地数据库）原汁原味地还原这些数据的存取流和生命周期。如果有任何网络请求逻辑，也一并迁移（使用 `http`/`dio`）。
2. **核心业务状态流**：扫描旧代码，把遗漏的业务闭环（如看完一章后的数据结算、2048 破纪录后的数据持久化记录）用 Provider 完全接管。
3. **物理音效引擎 (SFX)**：完全对接旧版 `AudioManager.js` 的所有触发时机，使用 `audioplayers` 还原声音反馈。
4. **缺失的 UI 闭环**：基于底层数据的补齐，把剩下的“壳子”页（如图书馆管理列表、全局设置面板、弹窗）全部画完并连通底层。