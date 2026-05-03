---
description: 环境配置工作流，用于阅游项目的多环境配置验证和部署检查
---

# 环境配置工作流

## 触发场景

当修改环境配置、切换部署环境或验证配置正确性时使用此工作流。

## 环境类型

### 开发环境（Development）

- 本地开发服务器：`localhost:8081`
- TTS 服务：`http://localhost:8081/api/v1/tts`
- 书籍 API：`http://localhost:8081/api/v1`
- 调试模式：启用详细日志

### 生产环境（Production）

- 生产服务器：`hclstudio.cn`
- TTS 服务：`https://hclstudio.cn/api/v1/tts`
- 书籍 API：`https://hclstudio.cn/api/v1`
- 调试模式：关闭详细日志

## 配置验证检查

### 1. 环境变量检查

```bash
# 检查环境变量定义
rg "String\.fromEnvironment" lib --type dart

# 验证必需的环境变量
TTS_SERVER_URL
BOOK_API_BASE
SENTRY_DSN
APP_VERSION
```

### 2. 默认值验证

```bash
# 检查开发环境默认值
rg "defaultValue.*localhost" lib/core/config/tts_config.dart

# 检查生产环境配置
flutter run --dart-define=TTS_SERVER_URL=https://hclstudio.cn/api/v1/tts --dart-define=BOOK_API_BASE=https://hclstudio.cn/api/v1
```

### 3. 配置文件完整性

```bash
# 检查配置类结构
rg "class.*Config" lib/core/config/ --type dart

# 验证常量定义
rg "static const.*=" lib/core/constants/ --type dart
```

## 技能调用

### 主要技能

- **yueyou-config-constants-guard** - 配置管理和常量验证
- **yueyou-code-quality-guard** - 硬编码检查

### 辅助技能

- **yueyou-architecture-guard** - 配置层架构验证
- **yueyou-test-ci-guard** - 配置相关测试

## 环境切换命令

### 开发环境启动

```bash
flutter run \
  --dart-define=TTS_SERVER_URL=http://localhost:8081/api/v1/tts \
  --dart-define=BOOK_API_BASE=http://localhost:8081/api/v1
```

### 生产环境构建

```bash
flutter build apk --release \
  --dart-define=TTS_SERVER_URL=https://hclstudio.cn/api/v1/tts \
  --dart-define=BOOK_API_BASE=https://hclstudio.cn/api/v1 \
  --target-platform android-arm64 \
  --split-per-abi
```

### 调试模式控制

```bash
# 开发环境（启用调试）
flutter run --debug

# 生产环境（关闭调试）
flutter build apk --release
```

## 配置文件标准

### TTS 配置（tts_config.dart）

```dart
class TtsConfig {
  static const String ttsEndpoint = String.fromEnvironment(
    'TTS_SERVER_URL',
    defaultValue: 'http://localhost:8081/api/v1/tts',
  );
  
  static const String bookApiBase = String.fromEnvironment(
    'BOOK_API_BASE',
    defaultValue: 'http://localhost:8081/api/v1',
  );
}
```

### 应用配置（app_config.dart）

```dart
class AppConfig {
  static const String appVersion = String.fromEnvironment(
    'APP_VERSION',
    defaultValue: '1.1.0',
  );
  
  static const String sentryDsn = String.fromEnvironment(
    'SENTRY_DSN',
    defaultValue: '',
  );
}
```

## 验证清单

### 开发环境

- [ ] Go 服务端在 `localhost:8081` 运行
- [ ] Flutter 应用能连接本地服务
- [ ] TTS 功能正常工作
- [ ] 日志输出详细但不影响性能

### 生产环境

- [ ] 所有环境变量已正确设置
- [ ] 网络请求指向生产服务器
- [ ] Sentry 错误上报正常
- [ ] 调试日志已关闭

### 通用检查

- [ ] 无硬编码域名或 IP
- [ ] 配置类使用 `String.fromEnvironment`
- [ ] 默认值适合开发环境
- [ ] 敏感信息通过环境变量注入

## 常见问题处理

### 连接失败

1. 检查服务端是否启动
2. 验证端口是否正确
3. 确认防火墙设置

### 配置不生效

1. 清理 Flutter 缓存：`flutter clean`
2. 重新获取依赖：`flutter pub get`
3. 重启应用

### 环境变量丢失

1. 检查编译命令是否包含 `--dart-define`
2. 验证变量名称拼写
3. 确认值格式正确

## 部署验证

### 本地验证

```bash
# 完整的环境配置测试
flutter test test/integration/environment_test.dart
```

### 生产部署

1. 设置生产环境变量
2. 执行生产构建命令
3. 验证 APK 文件生成
4. 清理其他架构产物

## 注意事项

1. **安全性**：敏感信息不得硬编码
2. **一致性**：开发、测试、生产环境配置要一致
3. **可追溯**：配置变更要记录在开发日志中
4. **回滚能力**：保留快速回滚到上一版本配置的能力
