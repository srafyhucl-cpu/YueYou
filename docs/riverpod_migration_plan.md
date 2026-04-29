# 阅游 (YueYou) - Riverpod 状态管理迁移与升级规划方案

## 1. 背景与迁移痛点

当前项目主要使用 `Provider 6.x` (结合 `ChangeNotifier` 与 `ProxyProvider`) 实现全局与模块间状态共享。随着 2048 益智游戏与小说朗读器的深度融合，暴露了以下核心技术痛点：
- **隐式 Context 依赖**：核心业务模块（如 `TtsEngineService` 与 `ReaderProvider`）在非 UI 上下文中进行状态联动时，强依赖 `BuildContext`，增加了领域模型与视图层的耦合风险。
- **依赖刷新冗余**：在大规模状态推导（如小说当前章节 -> TTS 音频合成 -> 滚动高亮）场景下，`ProxyProvider` 的依赖追踪过于粗粒度，易引发不必要的组件重绘（Widget Rebuild）。
- **类型安全薄弱**：极客团队需要编译期级别的状态强类型安全与异常捕获，避免过度依赖运行时判定。

## 2. 技术路线与规范 (选用 Riverpod 2.x + 代码生成)

迁移将全面拥抱 **Riverpod 2.x**，并强制启用 `@riverpod` 代码生成机制，实现状态管理范式的极客级重构：

### 2.1 基础注解与应用映射
- **无副作用的同步状态** -> `@riverpod` + 继承 `_$ClassName` 的 `Notifier<T>` 类。
- **异步数据（网络拉取、I/O）** -> `@riverpod` + 继承 `_$ClassName` 的 `AsyncNotifier<T>` 类。
- **只读全局配置** -> `@Riverpod(keepAlive: true)` 注解方法。

## 3. 渐进式模块迁移路线图 (Feature-Driven)

为确保商业化版本的稳定性，迁移划分为三个阶段，从底层依赖逐级向高阶业务推演：

### 阶段 1：底层无状态配置与设置隔离
- **核心目标**：迁移 `SettingsProvider`。
- **技术细节**：利用 `keepAlive: true` 保证用户偏好常驻内存，实现即插即用。

### 阶段 2：书籍数据流与文件仓储
- **核心目标**：迁移 `BookshelfProvider`。
- **技术细节**：将 `loadBooks` 与正文解析封装在 `AsyncNotifier` 中，通过 Riverpod 的 `AutoDispose` 机制在退出书库页时自动释放正文大文件内存。

### 阶段 3：高频耦合与复合联动层
- **核心目标**：重构 `ReaderProvider`、`GameProvider` 与 `TtsEngineService`。
- **技术细节**：利用 `ref.listen` 机制，使 2048 棋盘事件可以**纯异步无 Context** 的形式唤起小说音频播放或背景音效降级。

## 4. 兼容过渡策略（Provider 与 Riverpod 并存）

在全面迁移完成之前，采用“**依赖跨越桥接模式**”实现双轨并存：

```dart
// 兼容方案：使旧版 Provider 能够消费 Riverpod 状态
class ReaderProvider extends ChangeNotifier {
  ReaderProvider(this.ref);
  final Ref ref; // 注入 Riverpod 依赖
  
  void init() {
    // 监听 Riverpod 设置状态
    ref.listen(settingsProvider, (prev, next) {
      notifyListeners();
    });
  }
}
```

## 5. 测试用例适配改造建议

Riverpod 带来的最大极客红利在于 **100% 脱离 Widget 的单元测试**：
- **测试编写模式**：
```dart
test('SettingsProvider 状态迁移覆盖', () {
  final container = ProviderContainer();
  addTearDown(container.dispose);

  expect(
    container.read(settingsProvider).sound,
    isTrue,
  );
});
```

## 6. 安全红线与交付准则
1. 禁止在一次 Commit 中执行全局迁移，每次 PR 仅允许迁移**单个独立 Feature**。
2. 迁移后各功能覆盖率严守 **90% 基准线**。
