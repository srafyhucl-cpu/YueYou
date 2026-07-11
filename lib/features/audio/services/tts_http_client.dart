// TTS 业务 HTTP 客户端生产环境实现。
//
// 从 `tts_engine_service.dart` 抽出（PR-B，与 `tts_audio_adapters.dart` 配对）。
// 把 2 个「真实 HTTP」实现从上帝类里剥离：
// - [RealHttpClient]：底层 `dart:io HttpClient` 包装，提供流式下载与 JSON POST
// - [RealTtsHttpClient]：业务语义层，复用 [RealHttpClient]，暴露 `TtsHttpClient`
//
// 命名约定：原为私有 `_RealHttpClient` / `_RealTtsHttpClient`。private 类对
// 外不可见，public 化后外部 import 行为不变，因此无需 `export show` 向后兼容。

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:yueyou/core/config/tts_config.dart';
import 'package:yueyou/features/audio/domain/tts_http_models.dart';
import 'package:yueyou/features/audio/domain/tts_network_interfaces.dart';

/// 真实 HTTP 客户端实现：基于 `dart:io HttpClient`，支持重定向、超时与
/// 流式落盘。对 4xx/5xx 统一抛出 [TtsHttpStatusException]，便于上层区分
/// 可重试（5xx）与不可重试（4xx）路径。
class RealHttpClient implements HttpClientInterface {
  @override
  Future<void> download(Uri url, String savePath) async {
    final File targetFile = File(savePath);
    await targetFile.parent.create(recursive: true);

    final client = HttpClient();
    client.connectionTimeout = TtsConfig.ttsDownloadTimeout;
    try {
      var currentUrl = url;
      HttpClientRequest request = await client.getUrl(currentUrl);
      HttpClientResponse response;
      int redirectCount = 0;
      const int maxRedirects = 5;
      do {
        response = await request.close().timeout(
          TtsConfig.ttsDownloadTimeout,
          onTimeout: () {
            throw TimeoutException('TTS 下载超时 (15秒)');
          },
        );
        if (response.statusCode >= 300 &&
            response.statusCode < 400 &&
            response.headers.value('location') != null &&
            redirectCount < maxRedirects) {
          currentUrl = Uri.parse(response.headers.value('location')!);
          request = await client.getUrl(currentUrl);
          redirectCount++;
        } else {
          break;
        }
      } while (true);
      final int statusCode = response.statusCode;
      if (statusCode >= 400) {
        throw TtsHttpStatusException(statusCode, uri: url);
      }
      // P1-6：流式落盘。
      // 旧实现：先 bytes.addAll(chunk) 累积全部字节，再 writeAsBytes —— 对一段
      // 长句子的 mp3（数百 KB ~ 数 MB）瞬时占用 2x 内存，且对低端机型 GC 压力陡增。
      // 现改为打开 IOSink 边读边写；任何异常都删除半成品文件，避免
      // 损坏的缓存被后续 playFile 误认为可播放。
      final IOSink sink = targetFile.openWrite();
      int totalBytes = 0;
      try {
        try {
          await for (final chunk in response) {
            totalBytes += chunk.length;
            sink.add(chunk);
          }
          await sink.flush();
        } finally {
          // 无论成败都只关一次 sink，避免重复关闭抛 StateError。
          try {
            await sink.close();
          } catch (_) {
            // 关闭失败可容忍：sink 可能已在异常路径被关闭。
          }
        }
      } catch (_) {
        // 流读取/写入失败：清理半成品后让异常继续向上传播。
        try {
          if (await targetFile.exists()) await targetFile.delete();
        } catch (_) {
          // 清理失败可容忍：系统会在下次启动清理孤儿文件。
        }
        rethrow;
      }
      if (totalBytes == 0) {
        // 写入了 0 字节：清理空文件并按原契约抛 HttpException
        try {
          if (await targetFile.exists()) await targetFile.delete();
        } catch (_) {
          // 清理失败可容忍：同上。
        }
        throw const HttpException('下载音频失败: 响应体为空');
      }
    } finally {
      client.close();
    }
  }

  @override
  Future<String> postJson(
    Uri url,
    dynamic body, {
    Map<String, String>? headers,
  }) async {
    final client = HttpClient();
    client.connectionTimeout = TtsConfig.ttsPostConnectionTimeout;
    try {
      final request = await client.postUrl(url);
      request.headers.set(
        HttpHeaders.contentTypeHeader,
        'application/json; charset=utf-8',
      );
      headers?.forEach(request.headers.set);
      final Map<String, dynamic> bodyMap = body is Map<String, dynamic>
          ? body
          : (body is String ? jsonDecode(body) as Map<String, dynamic> : {});
      final jsonBody = jsonEncode(bodyMap);
      request.write(jsonBody);
      final response = await request.close().timeout(
        TtsConfig.ttsPostResponseTimeout,
        onTimeout: () {
          throw TimeoutException('TTS POST 请求超时 (15秒)');
        },
      );
      final statusCode = response.statusCode;
      final responseBody = await response.transform(utf8.decoder).join();
      if (statusCode >= 400) {
        throw TtsHttpStatusException(statusCode, uri: url);
      }
      return responseBody;
    } finally {
      client.close();
    }
  }
}

/// 生产环境实现：包装 [RealHttpClient]，在业务语义层完成「POST 获取 TTS
/// 元数据 JSON」与「GET 下载 TTS 音频」两件事。
class RealTtsHttpClient implements TtsHttpClient {
  final HttpClientInterface _httpClient;

  RealTtsHttpClient(this._httpClient);

  @override
  Future<TtsHttpResponse> post(
    Uri url, {
    Map<String, String>? headers,
    Object? body,
  }) async {
    final responseBody = await _httpClient.postJson(
      url,
      body,
      headers: headers,
    );
    final dynamic data = jsonDecode(responseBody);
    return TtsHttpResponse(
      statusCode: 200,
      body: data is String ? data : jsonEncode(data),
    );
  }

  @override
  Future<void> download(Uri url, String savePath) async {
    await _httpClient.download(url, savePath);
  }
}
