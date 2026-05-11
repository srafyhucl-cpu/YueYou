// TTS 服务端连接诊断子系统。
//
// 从 `tts_engine_service.dart` 抽出（PR-C）。把「业务上的故障排查工具」
// 与「日常播放主链路」分离，让上帝类聚焦在播放/缓存核心，连接测试可以
// 独立替换、独立测试。
//
// 暴露 2 个能力：
// - [pingServer]：3 秒超时的 HEAD 探活；
// - [testConnection]：完整的 POST + 解析 + 下载五步诊断流，返回结构化结果。

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'package:yueyou/core/config/tts_config.dart';
import 'package:yueyou/core/constants/cyber_error_messages.dart';
import 'package:yueyou/core/utils/cyber_logger.dart';
import 'package:yueyou/features/audio/domain/tts_network_interfaces.dart';

/// 服务端故障诊断服务。
///
/// 通过依赖注入与主引擎解耦：
/// - [httpClient] 为业务侧 TTS HTTP 客户端（与播放主链共用）；
/// - [config] 提供 TTS 全局配置（server URL、超时等）；
/// - [voiceGetter] 在调用瞬间惰性读取当前发音人；
/// - [onError] / [onClearError] 把诊断结果回写到引擎错误状态，
///   保持原有「测试失败也要影响 UI 错误提示」的契约。
class TtsDiagnosticsService {
  final TtsHttpClient httpClient;
  final TtsConfig config;
  final String Function() voiceGetter;
  final void Function(dynamic error) onError;
  final void Function() onClearError;

  TtsDiagnosticsService({
    required this.httpClient,
    required this.config,
    required this.voiceGetter,
    required this.onError,
    required this.onClearError,
  });

  /// 轻量 ping 探测：检测 TTS 服务端是否可达（非 5xx 即视为可达）。
  ///
  /// 用于 [TtsAudioNotifier] 在降级模式下探测网络是否恢复，封装于
  /// service 层避免 providers 层直接依赖 `dart:io HttpClient`。
  Future<bool> pingServer() async {
    try {
      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 3);
      final request = await client
          .headUrl(Uri.parse('${TtsConfig.bookApiBase}/ping'))
          .timeout(const Duration(seconds: 3));
      final response =
          await request.close().timeout(const Duration(seconds: 3));
      unawaited(response.drain<void>());
      client.close(force: true);
      return response.statusCode < 500;
    } catch (_) {
      // 网络不可达，ping 失败即返回 false
      return false;
    }
  }

  /// 🛠️ TTS 连接测试工具。
  ///
  /// 返回详细的诊断信息（5 步：地址校验 / URL 解析 / POST / 解析 / 下载），
  /// 帮助排查问题。任何失败都会通过 [onError] 回写到引擎错误状态。
  Future<Map<String, dynamic>> testConnection() async {
    final String voice = voiceGetter();
    final result = <String, dynamic>{
      'success': false,
      'serverUrl': config.serverUrl,
      'timestamp': DateTime.now().toIso8601String(),
      'steps': <Map<String, dynamic>>[],
    };

    try {
      // 步骤 1：检查服务器地址格式
      result['steps'].add({
        'step': 1,
        'name': '检查服务器地址',
        'status': 'success',
        'message': '服务器地址: ${config.serverUrl}',
      });

      // 步骤 2：解析 URL
      final uri = Uri.parse(config.serverUrl);
      result['steps'].add({
        'step': 2,
        'name': '解析 URL',
        'status': 'success',
        'message': 'Host: ${uri.host}, Port: ${uri.port}, Path: ${uri.path}',
      });

      // 步骤 3：发送 HTTP 请求
      const testText = '测试文本一二三四五';

      // 使用注入的 httpClient 以确保可测试性
      final response = await httpClient
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'text': testText, 'voice': voice}),
          )
          .timeout(config.requestTimeout);

      result['statusCode'] = response.statusCode;
      result['responseSize'] = response.body.length;

      if (response.statusCode == 200) {
        final dynamic decoded = jsonDecode(response.body);
        if (decoded is! Map<String, dynamic>) {
          throw const FormatException(CyberErrorMessages.ttsNotJsonObject);
        }
        final String status = (decoded['status'] as String? ?? '').trim();
        final String audioUrl = (decoded['url'] as String? ?? '').trim();
        if (status != 'success' || audioUrl.isEmpty) {
          throw FormatException(
            CyberErrorMessages.ttsMissingUrlTest(response.body),
          );
        }

        result['steps'].add({
          'step': 3,
          'name': 'HTTP 请求',
          'status': 'success',
          'message': '状态码: ${response.statusCode}, 已获取音频 URL',
        });

        result['steps'].add({
          'step': 4,
          'name': '解析音频地址',
          'status': 'success',
          'message': 'URL: $audioUrl',
        });

        // 步骤 5：尝试下载并写入文件
        try {
          final tempDir = await getTemporaryDirectory();
          final testFile = File('${tempDir.path}/tts_test.mp3');
          await httpClient.download(Uri.parse(audioUrl), testFile.path);
          final int fileSize = await testFile.length();

          result['steps'].add({
            'step': 5,
            'name': '下载并写入文件',
            'status': fileSize < 1024 ? 'warning' : 'success',
            'message': fileSize < 1024
                ? '警告：音频文件太小 (<1KB)，可能是错误响应'
                : '成功写入: ${testFile.path}',
          });

          // 清理测试文件
          await testFile.delete();
        } catch (e, st) {
          CyberLogger.captureWarning(
            e is Exception ? e : Exception('$e'),
            stack: st,
            tag: 'tts',
            extra: {'context': 'testConnection 写入文件失败'},
          );
          result['steps'].add({
            'step': 5,
            'name': '下载并写入文件',
            'status': 'error',
            'message': '写入文件失败: $e',
          });
        }

        result['success'] = true;
        result['message'] = 'TTS 服务器连接成功！';
        onClearError();
      } else {
        result['steps'].add({
          'step': 3,
          'name': 'HTTP 请求',
          'status': 'error',
          'message': '服务器返回错误: ${response.statusCode}\n响应: ${response.body}',
        });
        result['statusCode'] = response.statusCode;
        result['message'] =
            CyberErrorMessages.ttsServerErrorCode(response.statusCode);
        onError(response.statusCode);
      }
    } on TimeoutException catch (e, st) {
      CyberLogger.captureWarning(
        e,
        stack: st,
        tag: 'tts',
        extra: {'context': 'testConnection 请求超时'},
      );
      result['steps'].add({
        'step': 3,
        'name': 'HTTP 请求',
        'status': 'error',
        'message': '请求超时: $e',
      });
      result['message'] = CyberErrorMessages.ttsRequestTimeout;
      onError(e);
    } on SocketException catch (e, st) {
      CyberLogger.captureWarning(
        e,
        stack: st,
        tag: 'tts',
        extra: {'context': 'testConnection 网络异常'},
      );
      result['steps'].add({
        'step': 3,
        'name': 'HTTP 请求',
        'status': 'error',
        'message': '网络错误: $e',
      });
      result['message'] = CyberErrorMessages.ttsConnectTimeout;
      onError(e);
    } catch (e, st) {
      CyberLogger.captureWarning(
        e is Exception ? e : Exception('$e'),
        stack: st,
        tag: 'tts',
        extra: {'context': 'testConnection 未知异常'},
      );
      result['steps'].add({
        'step': 3,
        'name': 'HTTP 请求',
        'status': 'error',
        'message': '未知错误: $e',
      });
      result['message'] = '测试失败: $e';
      onError(e);
    }

    return result;
  }
}
