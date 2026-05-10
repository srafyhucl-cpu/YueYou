# YueYou Riverpod 迁移方案

> 本文档面向 AI 和团队开发者，提供从 `provider 6.x` 迁移至 `flutter_riverpod` 的完整分阶段方案。  
> 迁移策略：**共存渐进式**——新功能直接用 Riverpod，旧模块逐阶替换，全程保持绿色测试。

---

## 一、迁移动机与收益

| 痛点（现 Provider 6.x） | Riverpod 改善点 |
| --- | --- |
| `ChangeNotifierProxyProvider2` 链式依赖难读 | `ref.watch` 声明式依赖，逻辑清晰 |
| `context.read` 在 initState 使用有隐患 | `ref.read` 全生命周期安全 |
| 测试需注入 `MultiProvider` Widget 树 | `ProviderContainer` 零 Widget 纯 Dart 测试 |
| `Consumer3` 三泛型可读性差 | 多个 `ref.watch` 独立订阅，按需重建 |
| 无作用域隔离，Provider 全局可见 | `ProviderScope.overrides` 精准隔离 |

---

## 二、当前 Provider 依赖关系图

```text
SettingsProvider (ChangeNotifier)
    ↓ ProxyProvider          ↓ ProxyProvider2
TtsEngineService          GameProvider
    ↓ ProxyProvider
ReaderProvider

BookshelfProvider (独立 ChangeNotifier)
```

**消费侧统计**（截至 2026-04-29）：

| Provider 类型 | 消费文件数 | 消费方式 |
| --- | --- | --- |
| `SettingsProvider` | 3 | `Consumer` / `context.watch` |
| `TtsEngineService` | 6 | `Consumer` / `context.read` |
| `BookshelfProvider` | 3 | `Consumer` / `context.read/watch` |
| `ReaderProvider` | 4 | `Consumer` / `context.read` |
| `GameProvider` | 4 | `Consumer` / `context.read/watch` |

---

## 三、目标依赖关系（Riverpod）

```dart
// lib/core/providers/app_providers.dart

/// 基础单例：设置
final settingsProvider = ChangeNotifierProvider<SettingsProvider>(...);

/// 基础单例：书架
final bookshelfProvider = ChangeNotifierProvider<BookshelfProvider>(...);

/// 依赖 settings 的 TTS 引擎
final ttsEngineProvider = ChangeNotifierProvider<TtsEngineService>((ref) {
  final settings = ref.watch(settingsProvider);
  return TtsEngineService(settings);
});

/// 依赖 tts 的阅读器
final readerProvider = ChangeNotifierProvider<ReaderProvider>((ref) {
  final tts = ref.watch(ttsEngineProvider);
  return ReaderProvider(tts);
});

/// 依赖 settings + tts 的游戏
final gameProvider = ChangeNotifierProvider<GameProvider>((ref) {
  final gp = GameProvider();
  gp.soundEnabled = ref.watch(settingsProvider).sound;
  gp.onUserMove = () => ref.read(ttsEngineProvider).notifyUserActivity();
  return gp;
});
```

---

## 四、迁移阶段计划

### 阶段 0：环境准备（约 0.5 天）

**目标**：引入 Riverpod，新旧共存，不破坏任何现有功能。

```yaml
# pubspec.yaml
dependencies:
  flutter_riverpod: ^2.6.1   # 新增
  provider: ^6.1.5+1          # 保留（共存期）
```

- 在 `main.dart` 最外层包裹 `ProviderScope`，与现有 `MultiProvider` 并行：

```dart
void main() async {
  runApp(
    const ProviderScope(  // ← 新增，包在最外层
      child: YueYouApp(),
    ),
  );
}
```

- 验收：`flutter test` 全绿，`flutter analyze` 零警告。

---

### 阶段 1：迁移独立模块（约 1 天）

**目标**：迁移无上游依赖的两个独立 Provider。

**迁移顺序**：`SettingsProvider` → `BookshelfProvider`

#### 1.1 SettingsProvider

```dart
// lib/features/settings/providers/settings_provider_riverpod.dart
final settingsProvider = ChangeNotifierProvider<SettingsProvider>((ref) {
  final p = SettingsProvider();
  p.loadFromStorage();
  return p;
});
```

UI 侧替换：

```dart
// 旧
final settings = context.watch<SettingsProvider>();
// 新
final settings = ref.watch(settingsProvider);
```

#### 1.2 BookshelfProvider

```dart
final bookshelfProvider = ChangeNotifierProvider<BookshelfProvider>((ref) {
  return BookshelfProvider();
});
```

- 同步更新消费文件：`library_screen.dart`、`cyber_import_button.dart`
- 验收：原有测试用例全通过（bookshelf_provider_test.dart 改用 `ProviderContainer`）

---

### 阶段 2：迁移有依赖的服务层（约 1.5 天）

**目标**：替换 `ChangeNotifierProxyProvider` 链。

**迁移顺序**：`TtsEngineService` → `GameProvider` → `ReaderProvider`

#### 2.1 TtsEngineService

```dart
final ttsEngineProvider = ChangeNotifierProvider<TtsEngineService>((ref) {
  final settings = ref.watch(settingsProvider);
  final svc = TtsEngineService(settings);
  // 生命周期：Provider 销毁时自动 dispose
  ref.onDispose(svc.dispose);
  return svc;
});
```

> ⚠️ **重要**：现有 `TtsEngineService` 的 `init()` 需在 `_BootstrapperState.initState()` 中显式调用，Riverpod 的 lazy 初始化不改变这一要求。

#### 2.2 GameProvider

```dart
final gameProvider = ChangeNotifierProvider<GameProvider>((ref) {
  final gp = GameProvider();
  // 监听 settings 变化（sound 开关）
  ref.listen(settingsProvider, (_, next) {
    gp.soundEnabled = next.sound;
  });
  gp.onUserMove = () => ref.read(ttsEngineProvider).notifyUserActivity();
  return gp;
});
```

#### 2.3 ReaderProvider

```dart
final readerProvider = ChangeNotifierProvider<ReaderProvider>((ref) {
  final tts = ref.watch(ttsEngineProvider);
  final rp = ReaderProvider(tts);
  ref.onDispose(rp.dispose);
  return rp;
});
```

- 更新消费文件：`teleprompter_view.dart`、`chapter_list_screen.dart`、`cyber_player_console.dart`
- 验收：TTS 测试套件（`tts_engine_service_test.dart`）全通过

---

### 阶段 3：清理旧 Provider（约 0.5 天）

**目标**：删除 Provider 6.x 依赖，代码库完全基于 Riverpod。

- 删除 `main.dart` 中 `MultiProvider` / `ChangeNotifierProxyProvider` 树
- 从 `pubspec.yaml` 移除 `provider: ^6.1.5+1`
- 全局检查：移除所有 `Consumer`、`Consumer3`、`context.watch<T>()`、`context.read<T>()`
- `flutter pub get` → `flutter analyze` → `flutter test`

---

## 五、测试迁移对照

| 场景 | 旧（Provider 6.x） | 新（Riverpod） |
| --- | --- | --- |
| 纯 Dart 单元测试 | 需要 `pumpWidget(MultiProvider(...))` | `ProviderContainer` 直接创建 |
| Provider 覆盖 | `MultiProvider(providers: [ChangeNotifierProvider.value(...)])` | `ProviderScope(overrides: [settingsProvider.overrideWith(...)])` |
| 监听变化 | `addListener` 手动注册 | `container.listen(provider, ...)` |

### 示例：settings 测试迁移

```dart
// 旧
test('旧写法', () async {
  await tester.pumpWidget(
    ChangeNotifierProvider.value(
      value: SettingsProvider()..loadFromStorage(),
      child: const MaterialApp(home: SettingsScreen()),
    ),
  );
});

// 新
test('新写法', () {
  final container = ProviderContainer(
    overrides: [
      settingsProvider.overrideWith((ref) {
        final p = SettingsProvider();
        p.loadFromStorage();
        return p;
      }),
    ],
  );
  addTearDown(container.dispose);
  final settings = container.read(settingsProvider);
  expect(settings.sound, isTrue);
});
```

---

## 六、兼容性风险与规避

| 风险项 | 描述 | 规避方案 |
| --- | --- | --- |
| `TtsEngineService.dispose()` 双调用 | Riverpod `ref.onDispose` + `_BootstrapperState.dispose()` 可能双次调用 | 在 `dispose()` 内加 `if (_disposed) return` 幂等守卫 |
| `GameProvider.onUserMove` 闭包捕获 | `ref.read` 在 Provider 创建时调用可能读到旧实例 | 改为 `ref.read(ttsEngineProvider).notifyUserActivity` 延迟求值 |
| 测试 `ProviderContainer` 未 dispose | 内存泄漏 | 每个 test 中 `addTearDown(container.dispose)` |
| `Consumer3` → 多个 `ref.watch` 重建频率 | 单一 watch 变化不触发其他状态重建，可能行为差异 | Widget 拆分为多个 `ConsumerWidget` 精准订阅 |

---

## 七、验收标准

每个阶段完成后必须满足：

- [x] `flutter test --concurrency=1` 全量通过（451+）
- [x] `flutter analyze` 零 warning/error
- [x] 不引入新的 `@visibleForTesting` 破坏封装
- [x] CI pipeline（`.github/workflows/flutter-ci.yml`）已更新 `--concurrency=1` 消除 mock 竞态

> **2026-04-30 完结**：阶段 0~3 及测试清理全部完成，provider 依赖彻底移除。

---

## 八、参考资源

- [Riverpod 官方迁移指南](https://riverpod.dev/docs/migration/from_change_notifier)
- [flutter_riverpod pub.dev](https://pub.dev/packages/flutter_riverpod)
- 本项目 CI：`.github/workflows/flutter-ci.yml`
