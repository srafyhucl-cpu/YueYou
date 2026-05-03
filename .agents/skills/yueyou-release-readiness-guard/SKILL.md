---
name: yueyou-release-readiness-guard
description: 用于阅游项目发版前验收、APK 构建、环境变量、文档收口、Git 提交推送和零警告门禁。当准备发布、打包、交付验收或合并主分支前使用。
---

# 阅游发布就绪守卫

## 触发场景

- 准备 Android APK、桌面包或生产环境交付。
- 合并主分支、创建发布提交或交付测试包。
- 修改环境变量、构建配置、服务端地址、版本号或发布文档。
- 用户要求“发版”“打包”“收口”“发布检查”“上线前检查”。

## 发布门禁

1. `flutter analyze` 必须零错误零警告，禁止用参数掩盖问题。
2. 运行与本次改动相关的最小测试集；核心链路改动需补充更大范围测试。
3. 检查 `debugPrint()`、`print()`、硬编码域名、魔法数字和异常处理违规。
4. 检查 `TTS_SERVER_URL`、`BOOK_API_BASE` 等环境变量是否由 `--dart-define` 注入。
5. 检查 TTS 两步下载契约：POST 只取 JSON URL，GET 才下载音频。
6. 检查运行时控制台必须保持清洁，无已知可复现警告。
7. 检查 `DevelopmentPlan/`、`development_log.md`、必要时 `README.md` 已更新。

## Android APK 规范

Android 发版只允许构建 arm64-v8a 轻量包：

```powershell
flutter build apk --release --target-platform android-arm64 --split-per-abi
```

产物路径：

```text
build/app/outputs/flutter-apk/app-arm64-v8a-release.apk
```

禁止使用无参数的 `flutter build apk` 作为正式发版命令。打包后如产生其他 ABI 产物，必须清理无关产物。

## 生产环境注入

生产构建必须显式注入服务端配置：

```powershell
flutter build apk --release --target-platform android-arm64 --split-per-abi --dart-define=TTS_SERVER_URL=https://hclstudio.cn/api/v1/tts --dart-define=BOOK_API_BASE=https://hclstudio.cn/api/v1
```

密钥、AK、Token、Sentry DSN 等敏感信息禁止写入源码、文档示例或提交记录。

## 发布检查命令

```powershell
flutter analyze
flutter test --concurrency=1
rg "debugPrint\(" lib --type dart
rg "print\(" lib --type dart
rg "https?://[^']+" lib --type dart
rg "Future\.delayed\(Duration" lib --type dart
git status --short
```

## Git 收口

- 提交前必须确认 `git status --short`，区分本次改动与用户已有改动。
- 只暂存与本次任务相关的文件。
- 提交信息使用中文 Conventional Commit，例如 `chore(release): 增强发布验收守卫`。
- 提交后按项目约定推送当前远程分支；网络或权限受限时明确告知用户。

## 拒绝发布条件

- `flutter analyze` 存在任何错误、警告或 info。
- 核心链路测试失败，或失败原因未被定位。
- 业务代码中残留 `debugPrint()`、`print()`。
- 生产地址、密钥或用户隐私数据硬编码。
- TTS 分离下载契约被破坏。
- 文档收口未完成或 README 与实际构建方式不一致。
