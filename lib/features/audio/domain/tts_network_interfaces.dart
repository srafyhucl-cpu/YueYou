// TTS 网络层抽象接口（业务侧 HTTP 客户端 + 底层网络能力）。
//
// 从 `tts_engine_service.dart` 抽出（PR-A，与 `tts_engine_interfaces.dart`
// 配对）。本文件属 domain 层：仅声明接口，不依赖具体网络实现；严禁
// 引入 `package:flutter/material.dart` 或任何 UI 库。

import 'tts_http_models.dart';

/// 抽象接口，用于测试时注入 Mock —— TTS 业务侧 HTTP 客户端。
///
/// 仅暴露「POST 业务服务器获取 JSON 元数据」与「GET 下载音频文件」两个能力，
/// 隔离底层 `dart:io HttpClient` 与 `http` 包等具体实现。
abstract class TtsHttpClient {
  Future<TtsHttpResponse> post(
    Uri url, {
    Map<String, String>? headers,
    Object? body,
  });
  Future<void> download(Uri url, String savePath);
}

/// 抽象 HTTP 客户端接口（底层网络能力）。
///
/// 与 [TtsHttpClient] 的区别：
/// - [TtsHttpClient] 是「业务语义」层（POST 业务 JSON + 下载音频）；
/// - [HttpClientInterface] 是「网络能力」层（generic POST/GET），由
///   [TtsHttpClient] 实现复用。
abstract class HttpClientInterface {
  Future<void> download(Uri url, String savePath);
  Future<String> postJson(Uri url, dynamic body);
}
