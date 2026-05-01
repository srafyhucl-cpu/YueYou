---
name: yueyou_test_ci_guard
description: 用于阅游项目测试、静态分析、CI 失败排查、mock 维护和覆盖率守卫。当新增功能、修复 bug、调整异步逻辑、平台插件、GitHub Actions 或测试文件时使用。
---

# 阅游测试与 CI 守卫

## 默认验证顺序

1. 先运行最小相关测试，快速定位问题。
2. 再运行 `flutter analyze`。
3. 涉及共享服务、状态机、平台插件或收口前，运行更大范围测试。

## 测试约定

- SharedPreferences 测试必须隔离：`SharedPreferences.setMockInitialValues({})`，必要时重置 `StorageService`。
- 平台插件统一维护在 `test/utils/test_utils.dart`，不要在每个测试里复制一套 MethodChannel mock。
- Riverpod 测试使用 `ProviderScope` 和 overrides。
- 异步竞态测试优先使用 `fake_async`、可注入 delay、mock client、mock player。
- 修复 bug 时至少补一个能失败再通过的测试，除非明确说明无法自动化。

## 常用命令

```powershell
flutter analyze
flutter test
flutter test --coverage
flutter test --concurrency=1
```

## CI 排查

- 先看失败命令和首个真实错误，不被后续级联错误带偏。
- Android 构建问题优先检查 JDK、Kotlin、AGP、Gradle、跨盘缓存。
- 不为通过 CI 降低 lint 或删除测试；必须解释根因并修复。
