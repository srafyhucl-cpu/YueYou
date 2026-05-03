---
name: yueyou-config-constants-guard
description: 用于阅游项目的配置管理、常量定义和环境变量使用规范化约束。当修改配置文件、新增硬编码值、环境配置或常量定义时使用。
---

# 阅游配置常量守卫

## 环境变量管理

### 强制使用环境变量
- 所有服务器地址必须通过 `--dart-define` 注入
- 禁止在源码中硬编码域名、IP、端口
- 使用 `String.fromEnvironment()` 获取配置值
- 为开发环境提供合理的默认值（localhost）

### 环境变量命名规范
- 使用大写字母和下划线：`TTS_SERVER_URL`、`BOOK_API_BASE`
- 按功能模块分组：`TTS_*`、`BOOK_*`、`UPDATE_*`
- 避免缩写，使用完整描述性名称

### 编译时注入示例
```dart
// 正确示例
static const String ttsServerUrl = String.fromEnvironment(
  'TTS_SERVER_URL',
  defaultValue: 'http://localhost:8081/api/v1/tts',
);

// 错误示例
static const String ttsServerUrl = 'https://hclstudio.cn/api/v1/tts';
```

## 常量分类管理

### 核心业务常量
**位置**：`lib/core/constants/`
- `app_constants.dart`：应用级通用常量
- `book_constants.dart`：书籍相关常量（已存在）
- `cyber_error_messages.dart`：错误消息常量（已存在）

### UI 常量
**位置**：`lib/core/constants/ui_constants.dart`（需创建）
- 动画时长：`kAnimationDurationMs`
- 尺寸参数：`kButtonHeight`、`kBorderRadius`
- 颜色透明度：`kPrimaryAlpha`、`kSecondaryAlpha`
- 间距常量：`kSmallGap`、`kMediumGap`、`kLargeGap`

### 网络常量
**位置**：`lib/core/constants/network_constants.dart`（需创建）
- 超时时长：`kNetworkTimeout`、`kDownloadTimeout`
- 重试次数：`kMaxRetries`
- 缓存时长：`kCacheExpiration`
- 文件大小限制：`kMaxFileSizeBytes`

### 游戏常量
**位置**：`lib/features/game_2048/constants/game_constants.dart`（需创建）
- 棋盘参数：`kBoardSize`、`kTileMargin`
- 动画参数：`kMergeAnimationDuration`
- 得分规则：`kScoreMultiplier`
- 视觉效果：`kTiltAngle`、`kParticleCount`

## 配置文件规范

### TTS 配置（TtsConfig）
- 使用环境变量获取服务器地址
- 提供本地开发默认值
- 支持多环境切换（dev/test/prod）

### 应用配置
- 版本号通过环境变量注入
- 构建类型区分开发/生产
- 功能开关可配置控制

## 硬编码检测规则

### 数值常量检查
**需要抽取的数值**：
- 大于 1 的整数（除明显标识如 2、4、8、16、32、64、128）
- 所有小数值（如 0.5、0.8、1.5）
- 所有 Duration 参数

**允许直接使用的数值**：
- 0、1、-1（标识性数值）
- 2 的幂次（2、4、8、16、32、64、128）
- 百分比数值（100、50、25）

### 字符串常量检查
**需要环境变量化**：
- URL、域名、IP 地址
- API 端点路径
- 文件路径（非相对路径）

**允许直接使用**：
- 相对路径（'assets/images/'）
- 固定标识符（'id'、'name'、'type'）
- UI 显示文本（通过国际化管理）

## 检查方法

### 环境变量检查
```bash
# 检查硬编码域名
rg "https?://[^']+" lib --type dart

# 检查环境变量使用
rg "String\.fromEnvironment" lib --type dart

# 检查配置类
rg "class.*Config" lib --type dart
```

### 常量检查
```bash
# 检查魔法数字
rg "\b(15|30|60|300|800|2000|5000|10000|15000)\b" lib --type dart

# 检查 Duration 硬编码
rg "Duration\((seconds|milliseconds):\s*[0-9]" lib --type dart

# 检查常量定义
rg "static const.*=.*[0-9]" lib --type dart
```

### 配置完整性检查
```bash
# 检查环境变量定义
rg "--dart-define=" . -r

# 检查默认值设置
rg "defaultValue:" lib --type dart
```

## 常见违规模式

### 环境变量违规
- ❌ `static const url = 'https://api.example.com';`
- ✅ `static const url = String.fromEnvironment('API_URL', defaultValue: 'http://localhost:8080');`

### 常量违规
- ❌ `await Future.delayed(Duration(seconds: 15));`
- ✅ `await Future.delayed(kNetworkTimeout);`

### 配置违规
- ❌ `if (kDebugMode) { /* 开发逻辑 */ }`
- ✅ `if (EnvironmentConfig.isDevelopment) { /* 开发逻辑 */ }`

## 创建新常量流程

1. **确定常量类型**：UI、网络、业务、游戏
2. **选择文件位置**：按分类放入对应常量文件
3. **命名规范**：使用 `k` 前缀 + 驼峰命名
4. **添加注释**：说明用途和使用场景
5. **更新引用**：替换所有硬编码使用
6. **验证测试**：确保功能正常

## 验证清单

在提交配置相关代码前，确保：
- [ ] 所有域名通过环境变量配置
- [ ] 魔法数字已抽取为常量
- [ ] 常量按分类正确放置
- [ ] 环境变量有合理默认值
- [ ] 配置类使用 `String.fromEnvironment`
- [ ] Duration 参数使用常量
- [ ] `flutter analyze` 无错误
