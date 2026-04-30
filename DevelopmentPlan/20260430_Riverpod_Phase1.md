# 20260430_Riverpod渐进式迁移_Phase1落地

## 任务目标
执行 V1.1 架构升级的 Phase 1：基础设施引入与基础 Provider (Settings/Bookshelf) 的迁移。

## 执行内容
1. **基础设施配置**
   - 引入 `flutter_riverpod: ^2.6.1`。
   - 在 `main.dart` 中使用 `ProviderScope` 包裹根部 `YueYouApp`。
   - 建立双轨兼容层：利用 `ConsumerWidget` 的 `ref.watch(provider.notifier)` 获取 Riverpod 单例对象，并将其实例传递给 `MultiProvider` 以向下兼容未迁移的服务。

2. **基础数据层迁移**
   - 定义 `settingsProvider` 并废弃局部手动创建。
   - 定义 `bookshelfProvider` 并废弃局部手动创建。
   - 清理 `_loadBootstrapData` 中的数据加载，改为直接在 Provider 初始化前依靠 `StorageService.init` 同步读取完成加载。

3. **UI 层迁移体验**
   - 重构 `settings_screen.dart`，由 `StatelessWidget` 转换为 `ConsumerWidget`。
   - 重构 `library_screen.dart`，迁移内部 `_BookCard` 的状态监听逻辑为 `ConsumerWidget`。
   - 重构 `cyber_import_button.dart` 为 `ConsumerStatefulWidget`，并在回调中无缝结合 `ref.read` (新架构) 与 `context.read` (旧架构)。

4. **测试闭环更新**
   - 将 `bookshelf_provider_test.dart` 及 `settings_provider_test.dart` 统一重构为使用 Riverpod 的 `ProviderContainer` 构建测试用例。
   - 验证全域 `flutter test` 与 `flutter analyze` 稳定通过（451+ 测试用例零失败）。

## 下一步 (Phase 2)
进行核心业务层（`TtsEngineService` 与 `GameProvider` / `ReaderProvider`）的依赖链迁移。
