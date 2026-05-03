---
name: yueyou-architecture-guard
description: 用于阅游 Flutter/Dart 项目的架构边界、Riverpod 生命周期、模块依赖和 Clean Architecture 约束检查。当修改 lib/core、lib/features、Provider、Service、domain、presentation 或跨模块依赖时使用。
---

# 阅游架构守卫

## 核心边界

- `lib/core/`：只放全局基础设施、主题、配置、日志、存储抽象，禁止引入具体业务 feature。
- `features/*/domain/`：纯 Dart 业务逻辑，禁止导入 `package:flutter/material.dart` 或 UI 组件。
- `features/*/providers/`：状态与用例编排，禁止写 Widget 布局。
- `features/*/presentation/`：只做渲染与交互转发，不沉淀核心业务规则。
- `shared/widgets/`：可复用 UI，不引用具体 feature 的私有业务状态。

## 日志层边界

### 日志系统分层
- `lib/core/utils/cyber_logger.dart`：全局日志基础设施，禁止包含业务逻辑
- 业务模块：使用 `CyberLogger.captureMessage()` 和 `CyberLogger.captureWarning()`
- UI 层：禁止直接输出日志，通过业务层间接记录

### 日志使用约束
- 禁止在 `domain/` 层直接调用日志（通过异常传递到上层）
- `providers/` 层负责业务日志记录和异常上报
- `presentation/` 层只记录用户交互事件，不记录业务细节
- `core/` 层日志仅限于基础设施状态，不涉及具体业务

### 跨模块日志规范
- 使用统一的 tag 命名：tts、reader、library、game、audio、dashboard
- 禁止在日志中包含用户隐私数据
- 异常日志必须包含足够的上下文信息用于问题定位

## Riverpod 规则

- 当前项目使用 `flutter_riverpod`，新增状态优先使用 Riverpod Provider。
- 需要释放资源的服务必须在 provider 中使用 `ref.onDispose`。
- Provider 之间联动优先使用 `ref.listen`，避免 UI 层手动串联业务生命周期。
- 测试中通过 `ProviderScope(overrides: [...])` 注入替身。
- 不再新增 `provider` 包、`context.watch<T>()`、`context.read<T>()`。

## 代码设计

- 业务状态机要尽量使用 Dart 3 模式匹配和穷尽分支。
- 异步流程必须考虑 disposed、session、token 或 request id，避免旧任务回写新状态。
- 可替换依赖通过构造函数注入，便于单测 mock。
- 只在确实降低复杂度时引入抽象，避免为了"架构感"扩层。

## 检查方法

优先使用：

```powershell
# 架构边界检查
rg "package:flutter/material.dart" lib/features/*/domain
rg "context\.(watch|read)<" lib test
rg "provider:" pubspec.yaml

# 日志边界检查
rg "debugPrint\(" lib/features/*/domain
rg "CyberLogger\." lib/features/*/domain
rg "captureMessage\(" lib/features/*/presentation
rg "captureWarning\(" lib/features/*/domain

# 整体质量检查
flutter analyze
```
