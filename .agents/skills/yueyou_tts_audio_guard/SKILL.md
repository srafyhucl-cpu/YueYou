---
name: yueyou_tts_audio_guard
description: 用于阅游 TTS、音频播放、缓存、预加载、环境音、音频焦点和朗读状态机开发。当修改 tts_engine_service、ambient_service、sfx_service、reader_provider、tts_config 或相关测试时使用。
---

# 阅游 TTS 与音频守卫

## 云端 TTS 契约

客户端必须遵守“两步下载”：

1. POST 业务服务器，只解析 JSON：`{"status":"success","url":"https://..."}`。
2. GET 上一步返回的 `url`，从 OSS/CDN 下载音频并写入本地缓存。
3. 禁止把 POST 响应体直接保存为音频文件。

## 状态机规则

- 播放、预加载、刷新、切章都必须带 session/token 防旧任务回写。
- `dispose` 后不得继续播放、下载、唤醒屏幕或通知 UI。
- 错误状态要可恢复，重试前应清理上一次错误事件。
- 云端失败后可降级到本地 `flutter_tts`，但必须避免重复朗读同一句。
- 预加载队列上限遵守 `TtsConfig.maxPrefetchQueue`。

## 音频资源规则

- TTS 是主音频流，环境音不得抢占朗读焦点。
- 背景音、音效、朗读之间的播放器实例和释放逻辑要彼此独立。
- 缓存清理遵守大小和时间阈值，不清理正在播放或即将播放的文件。
- 网络超时、5xx、无效 JSON、URL 缺失必须分别测试。

## 必跑验证

按修改范围选择：

```powershell
flutter test test/features/audio
flutter test test/features/reader
flutter analyze
```

涉及竞态或 CI 波动时使用：

```powershell
flutter test --concurrency=1
```
