// TTS HTTP 与播放状态数据模型。
//
// 从 `tts_engine_service.dart` 抽出（PR-A），便于在不引入服务实现的
// 前提下被测试与状态机消费。本文件属 domain 层：
// - 不依赖任何 Flutter UI 库（material/cupertino 禁止导入）；
// - 不持有可变全局状态；
// - 不直接调用日志，错误通过返回值或异常传递。

/// TTS HTTP 响应数据模型。
///
/// 仅用于业务层与测试 mock 在「业务服务器返回 JSON 字符串」与
/// 「真实下载结果」之间传递结构化信息，避免直接暴露第三方 HTTP 库类型。
class TtsHttpResponse {
  final int statusCode;
  final String body;

  const TtsHttpResponse({required this.statusCode, required this.body});
}

/// TTS 业务 HTTP 异常，携带 HTTP 状态码，供下载/获取 URL 调用方区分：
/// - `4xx`（[isClientError] 为 true）：客户端错误，**不可重试**；
/// - `5xx`：服务端错误，**可重试**。
///
/// 从 `tts_engine_service.dart` 抽出（PR-B）。原为私有 `_TtsHttpStatusException`，
/// 为支持适配器与核心服务跨文件协作而 public 化；由于旧名带前导下划线，
/// 外部 import 从来拿不到该类型，因此无需 `export show` 向后兼容。
class TtsHttpStatusException implements Exception {
  final int statusCode;
  final Uri? uri;

  TtsHttpStatusException(this.statusCode, {this.uri});

  bool get isClientError => statusCode >= 400 && statusCode < 500;

  @override
  String toString() => '服务端返回 $statusCode';
}

/// TTS 音频播放状态机
///
/// Dart 3 模式匹配要求：所有 switch 必须穷尽以下 5 个分支：
/// - [disabled]：引擎关闭，不进行任何音频活动
/// - [paused]：已暂停，音频流挂起
/// - [buffering]：正在预加载下一句音频
/// - [playing]：正在播放音频
/// - [error]：引擎遭遇不可恢复错误（网络中断、格式异常等），
///   需用户手动恢复或等待自动降级
enum TtsPlaybackState { disabled, paused, buffering, playing, error }
