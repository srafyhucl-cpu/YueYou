---
description: 代码规范化检查工作流，用于阅游项目的自动化代码质量检查和规范验证
---

# 代码规范化检查工作流

## 触发场景

在每次代码提交前、任务完成时或需要验证代码规范时使用此工作流，确保代码符合阅游项目的大厂级规范标准。

## 检查流程

### 1. 静态分析检查

```bash
flutter analyze
dart scripts/ai_code_checker.dart
```

- **确保零错误零警告（强制要求）**
- 检查代码风格和潜在问题
- 控制台必须完全清洁，无任何警告信息

### 2. 日志规范检查

```bash
# 检查非法日志使用
rg "debugPrint\(" lib --type dart
rg "print\(" lib --type dart

# 检查日志 tag 使用
rg "captureWarning\(" lib --type dart -B1 -A1

# 检查分层日志违规
rg "CyberLogger\." lib/features/*/domain
rg "captureMessage\(" lib/features/*/presentation
```

### 3. 硬编码检查

```bash
# 检查魔法数字
rg "\b(15|30|60|300|800|2000|5000|10000|15000)\b" lib --type dart

# 检查硬编码域名
rg "https?://[^']+" lib --type dart

# 检查直接 Duration
rg "Duration\(seconds:\s*[0-9]" lib --type dart
rg "Duration\(milliseconds:\s*[0-9]" lib --type dart

# 检查环境变量使用
rg "String\.fromEnvironment" lib --type dart
```

### 4. 架构边界检查

```bash
# 检查 UI 库违规导入
rg "package:flutter/material.dart" lib/features/*/domain

# 检查 Provider 使用规范
rg "context\.(watch|read)<" lib test

# 检查依赖包使用
rg "provider:" pubspec.yaml
```

### 5. 异常处理检查

```bash
# 检查异常捕获是否使用 CyberLogger
rg "catch.*{" lib --type dart -A5 | grep -v "captureWarning"
```

### 6. 测试验证（可选）

```bash
# 运行核心模块测试
flutter test test/features/audio/
flutter test test/features/reader/

# 完整测试（如需要）
flutter test --coverage
```

## 技能调用

在检查过程中，根据发现的问题调用相应技能：

### 调用代码质量守卫

当发现日志、硬编码、异常处理问题时：

```text
使用 yueyou-code-quality-guard 技能分析和修复问题
```

### 调用配置常量守卫

当发现配置管理、常量定义问题时：

```text
使用 yueyou-config-constants-guard 技能规范配置
```

### 调用架构守卫

当发现架构边界、模块依赖问题时：

```text
使用 yueyou-architecture-guard 技能检查架构合规性
```

## 常见问题处理

### 日志违规

- **问题**：发现 `debugPrint` 使用
- **处理**：替换为 `CyberLogger.captureMessage`
- **示例**：

  ```dart
  // 错误
  debugPrint('用户登录成功');
  
  // 正确
  CyberLogger.captureMessage('用户登录成功', tag: 'auth');
  ```

### 硬编码违规

- **问题**：发现魔法数字或硬编码域名
- **处理**：抽取为常量或环境变量
- **示例**：

  ```dart
  // 错误
  await Future.delayed(Duration(seconds: 15));
  
  // 正确
  await Future.delayed(kNetworkTimeout);
  ```

### 架构违规

- **问题**：domain 层导入 UI 库
- **处理**：重构代码，移除违规依赖
- **示例**：

  ```dart
  // 错误
  import 'package:flutter/material.dart';
  
  // 正确
  // domain 层不应导入任何 UI 库
  ```

## 验收标准

检查通过的标准：

- [ ] `flutter analyze` **零错误零警告（控制台完全清洁）**
- [ ] 无 `debugPrint` 或 `print` 在业务代码中
- [ ] 无硬编码域名和魔法数字
- [ ] 异常处理使用 `CyberLogger.captureWarning`
- [ ] 架构边界无违规
- [ ] 环境变量配置正确
- [ ] **控制台运行时无任何警告信息输出**

## 自动化脚本

可以创建自动化脚本执行完整检查：

```bash
#!/bin/bash
# code-check.sh

echo "🔍 开始代码规范化检查..."

# 静态分析
echo "📋 执行静态分析..."
flutter analyze
if [ $? -ne 0 ]; then
  echo "❌ 静态分析失败"
  exit 1
fi

echo "🤖 执行 AI 工程门禁..."
dart scripts/ai_code_checker.dart
if [ $? -ne 0 ]; then
  echo "❌ AI 工程门禁失败"
  exit 1
fi

# 日志检查
echo "📝 检查日志规范..."
if rg "debugPrint\(" lib --type dart; then
  echo "❌ 发现 debugPrint 使用"
  exit 1
fi

# 硬编码检查
echo "🔢 检查硬编码..."
if rg "\b(15|30|60|300|800|2000|5000|10000)\b" lib --type dart; then
  echo "❌ 发现魔法数字"
  exit 1
fi

echo "✅ 代码规范化检查通过"
```

## 使用方法

### 手动执行

1. 在项目根目录打开终端
2. 按流程执行各项检查
3. 根据结果修复发现的问题
4. 重新检查直到通过

### 集成到开发流程

- 提交代码前必须执行此工作流
- 任务完成时作为验收标准之一
- CI/CD 流程中集成自动检查

## 注意事项

1. **性能考虑**：检查过程可能需要几分钟，请耐心等待
2. **准确性**：某些检查可能存在误报，需要人工判断
3. **完整性**：建议在干净的工作目录中执行，避免未提交代码的干扰
4. **持续改进**：根据项目发展定期更新检查规则和标准
