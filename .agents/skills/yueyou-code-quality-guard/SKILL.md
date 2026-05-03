---
name: yueyou-code-quality-guard
description: 用于阅游项目的代码质量规范化约束，包括日志使用规范、硬编码检测、异常处理统一和常量管理。当修改业务逻辑、新增调试代码、处理异常或配置相关功能时使用。
---

# 阅游代码质量守卫

## 日志使用规范

### 禁止行为
- 禁止在业务代码中使用 `debugPrint()`、`print()`
- 禁止直接输出到控制台而不通过日志系统
- 禁止在循环中输出日志（避免性能问题）

### 强制要求
- 必须使用 `CyberLogger.captureMessage()` 记录业务信息
- 必须使用 `CyberLogger.captureWarning()` 记录异常和错误
- 按模块分组设置 tag：tts、reader、library、game、audio、dashboard
- 生产环境自动过滤 DEBUG 级别日志（通过 Sentry 配置）

### 日志级别规范
- `info`：关键业务节点、状态变更
- `debug`：详细调试信息（开发环境）
- `warning`：可恢复异常、降级处理
- `error`：严重错误、功能异常

## 硬编码检测

### 魔法数字禁止
- 禁止直接使用数字常量（除 0、1、-1 等明显标识）
- 动画时长必须抽取到常量
- 尺寸参数必须使用主题配置
- 超时时间必须配置化管理

### 域名配置规范
- 禁止硬编码域名和 IP 地址
- 必须通过环境变量 `--dart-define` 注入
- 本地开发默认使用 `localhost`
- 生产环境通过编译参数指定

### 常量管理
- UI 常量放在 `lib/core/constants/ui_constants.dart`
- 业务常量放在对应模块的 constants 文件
- 配置常量使用 `String.fromEnvironment()` 获取

## 异常处理统一

### 异常捕获规范
- 必须使用 `CyberLogger.captureWarning()` 上报异常
- 提供有意义的 tag 和上下文信息
- 包含相关堆栈信息（非敏感部分）

### 错误处理模式
```dart
try {
  // 业务逻辑
} catch (e, stackTrace) {
  CyberLogger.captureWarning(
    e,
    stack: stackTrace,
    tag: 'module_name',
    extra: {'context': '操作描述'},
  );
  // 降级处理或用户提示
}
```

### 容错策略
- 网络异常：自动重试 + 降级处理
- 文件异常：使用默认值或跳过
- UI 异常：展示占位符或错误提示

## 现代 Dart 质量规则

- 状态分支优先使用 Dart 3 模式匹配和穷尽 switch，避免遗漏新状态。
- 可空值必须显式收窄后使用，禁止用 `!` 掩盖生命周期或异步竞态问题。
- 异步任务必须携带 disposed、session、token 或 request id 守卫，禁止旧任务回写新状态。
- 集合转换优先使用类型安全 API，避免 `dynamic` 扩散到业务层。
- Domain 层只表达纯业务规则，不依赖 Flutter、日志系统、平台插件或本地存储实现。

## 检查方法

### 日志规范检查
```bash
# 检查非法日志使用
rg "debugPrint\(" lib --type dart
rg "print\(" lib --type dart

# 检查日志 tag 使用
rg "captureWarning\(" lib --type dart -B1 -A1
```

### 硬编码检查
```bash
# 检查魔法数字
rg "\b(15|30|60|300|800|2000|5000|10000)\b" lib --type dart

# 检查硬编码域名
rg "https?://[^']+" lib --type dart

# 检查直接 Duration
rg "Duration\(seconds:\s*[0-9]" lib --type dart
rg "Duration\(milliseconds:\s*[0-9]" lib --type dart
```

### 异常处理检查
```bash
# 检查异常捕获是否使用 CyberLogger
rg "catch.*{" lib --type dart -A5 | grep -v "captureWarning"
```

## 常见违规模式

### 日志违规
- 错误：`debugPrint('用户点击了按钮')`
- 正确：`CyberLogger.captureMessage('用户点击了按钮', tag: 'ui')`

### 硬编码违规
- 错误：`await Future.delayed(Duration(seconds: 15))`
- 正确：`await Future.delayed(AppConstants.networkTimeout)`

### 异常处理违规
- 错误：`} catch (e) { print('错误: $e'); }`
- 正确：`} catch (e, stack) { CyberLogger.captureWarning(e, stack: stack, tag: 'module'); }`

## 验证清单

在提交代码前，确保：
- [ ] 业务代码中无 `debugPrint` 或 `print`
- [ ] 所有魔法数字已抽取为常量
- [ ] 异常处理使用 `CyberLogger.captureWarning`
- [ ] 域名通过环境变量配置
- [ ] 日志 tag 按模块正确分组
- [ ] `flutter analyze` **零错误零警告（控制台完全清洁）**
- [ ] **运行时控制台无任何警告信息输出**
