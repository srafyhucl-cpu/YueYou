// TTS 音频下载与本地朗读降级子系统。
//
// 从 `tts_engine_service.dart` 抽出（PR-C）。负责：
// - 与业务服务器交互获取音频 URL；
// - 通过 OSS/CDN 下载实际音频文件；
// - 多次重试 + 区分 4xx/5xx 的重试策略；
// - 本地 [TtsFallbackEngine] 朗读降级；
// - 临时文件清理。
//
// 设计要点：与 [TtsEngineService] 通过构造器注入的 callback 解耦，downloader
// 不持有引擎可变状态，所有「写回引擎」的副作用（错误状态、降级通知、最后
// 生成路径、进度推送）都通过显式 callback 暴露，便于单元测试。

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'package:yueyou/core/config/tts_config.dart';
import 'package:yueyou/core/constants/cyber_error_messages.dart';
import 'package:yueyou/core/utils/cyber_logger.dart';
import 'package:yueyou/features/audio/domain/tts_audio_models.dart';
import 'package:yueyou/features/audio/domain/tts_engine_interfaces.dart';
import 'package:yueyou/features/audio/domain/tts_http_models.dart';
import 'package:yueyou/features/audio/domain/tts_network_interfaces.dart';

/// 下载与本地朗读子系统。
///
/// 通过构造器注入所有依赖：
/// - [httpClient]：业务侧 TTS HTTP 客户端；
/// - [fallbackEngine]：本地 TTS 降级引擎；
/// - [config] / [voiceGetter]：服务端地址与发声人；
/// - [initFuture]：硬件初始化完成 Future，下载前 `await` 守护避免清理任务
///   误删活跃下载文件；
/// - [isDisposed]：引擎是否已销毁，下载完成后回写状态前必查；
/// - [delayFn]：重试间隔注入点，便于测试加速；
/// - [playbackRateGetter]：当前倍速，用于本地朗读时长估算；
/// - [onError] / [onClearError] / [onFallbackNotification]：错误与降级提示
///   写回引擎；
/// - [onPathGenerated]：通知引擎记录最新生成路径（活跃文件保护）；
/// - [progressEmitter]：向播放进度流推送 0.0~1.0 的实时位置。
class TtsAudioDownloader {
  final TtsHttpClient httpClient;
  final TtsFallbackEngine fallbackEngine;
  final TtsConfig config;
  final String Function() voiceGetter;
  final Future<void> initFuture;
  final bool Function() isDisposed;
  final Future<void> Function(Duration) delayFn;
  final double Function() playbackRateGetter;
  final void Function(dynamic error) onError;
  final void Function() onClearError;
  final void Function(String message) onFallbackNotification;
  final void Function(String path) onPathGenerated;
  final void Function(double progress) progressEmitter;

  TtsAudioDownloader({
    required this.httpClient,
    required this.fallbackEngine,
    required this.config,
    required this.voiceGetter,
    required this.initFuture,
    required this.isDisposed,
    required this.delayFn,
    required this.playbackRateGetter,
    required this.onError,
    required this.onClearError,
    required this.onFallbackNotification,
    required this.onPathGenerated,
    required this.progressEmitter,
  });

  /// 下载 TTS 音频文件（带重试机制），返回文件路径或 null。
  Future<String?> downloadAudio(TtsAudioRequest request) async {
    // 等待硬件初始化完成，确保 cleanupOrphanedTtsFiles 不会与本次写入并行——
    // 否则在 CPU 竞争场景下，清理任务可能扫到刚下载完成、onPathGenerated 尚未
    // 回写的窗口内的文件并误删，导致 playFile 读到「文件不存在」触发
    // onComplete 抢跑、绕过 pause 守卫的并发 flake。
    await initFuture;
    for (int attempt = 0; attempt < config.maxRetries; attempt++) {
      try {
        final result = await _executeDownload(request);
        if (result != null) return result;
      } on TimeoutException catch (e, st) {
        CyberLogger.captureWarning(
          e,
          stack: st,
          tag: 'tts',
          extra: {'context': 'TTS 请求超时', 'attempt': '${attempt + 1}'},
        );
        if (attempt < config.maxRetries - 1) {
          await delayFn(config.baseRetryDelay * (1 << attempt));
        }
      } on TtsHttpStatusException catch (e, st) {
        CyberLogger.captureWarning(
          e,
          stack: st,
          tag: 'tts',
          extra: {
            'context': 'TTS HTTP 错误',
            'statusCode': '${e.statusCode}',
            'attempt': '${attempt + 1}',
          },
        );
        if (e.isClientError) {
          // 4xx 客户端错误：不可重试，立即退出
          break;
        }
        // 5xx 服务端错误：可重试
        if (attempt < config.maxRetries - 1) {
          await delayFn(config.baseRetryDelay * (1 << attempt));
        }
      } catch (e, st) {
        CyberLogger.captureWarning(
          e,
          stack: st,
          tag: 'tts',
          extra: {'context': 'TTS 下载失败', 'attempt': '${attempt + 1}'},
        );
        if (e is FormatException) {
          break;
        }
        if (attempt < config.maxRetries - 1) {
          await delayFn(config.baseRetryDelay * (1 << attempt));
        }
      }
    }
    // 所有重试均失败 → Sentry 上报
    CyberLogger.captureWarning(
      Exception('TTS download failed after ${config.maxRetries} retries'),
      tag: 'tts',
    );
    onFallbackNotification(CyberErrorMessages.ttsFallbackDisconnected);
    return null;
  }

  /// 下载的单一尝试，返回文件路径或 null。
  Future<String?> _executeDownload(TtsAudioRequest request) async {
    final voice = voiceGetter();
    String? filePath;
    try {
      filePath = await _mainThreadDownload(request, voice, config.serverUrl);
    } catch (_) {
      unawaited(deleteFileIfExists(filePath));
      rethrow;
    }
    if (isDisposed()) {
      unawaited(deleteFileIfExists(filePath));
      return null;
    }
    if (filePath == null) return null;
    onPathGenerated(filePath);
    onClearError();
    return filePath;
  }

  /// 主线程 HTTP 客户端下载：POST 业务服务器获取音频 URL，再 GET 下载文件。
  Future<String?> _mainThreadDownload(
    TtsAudioRequest request,
    String voice,
    String serverUrl,
  ) async {
    final uri = Uri.parse(serverUrl);
    final response = await httpClient.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'text': request.text,
        'voice': voice,
      }),
    );
    if (isDisposed()) return null;
    if (response.statusCode != 200) {
      onError(response.statusCode);
      throw TtsHttpStatusException(response.statusCode, uri: uri);
    }
    final responseBody = response.body.trim();
    if (!(responseBody.startsWith('{') || responseBody.startsWith('['))) {
      throw const FormatException(CyberErrorMessages.ttsInvalidFormat);
    }
    final decoded = jsonDecode(responseBody);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException(CyberErrorMessages.ttsNotJsonObject);
    }
    final status = (decoded['status'] as String? ?? '').trim();
    final audioUrl = (decoded['url'] as String? ?? '').trim();
    if (status != 'success' || audioUrl.isEmpty) {
      throw FormatException(CyberErrorMessages.ttsMissingUrl(responseBody));
    }
    final tempDir = await getTemporaryDirectory();
    // 并发会话可能在同一毫秒生成文件，使用微秒避免新旧会话共享路径。
    final timestamp = DateTime.now().microsecondsSinceEpoch;
    final filePath = '${tempDir.path}/tts_$timestamp.mp3';
    await httpClient.download(Uri.parse(audioUrl), filePath);
    return filePath;
  }

  /// 使用本地 TTS 引擎朗读指定文本，返回是否成功。
  ///
  /// 朗读期间按 4 字/秒的经验值估算进度，每 100ms 推送一次给 [progressEmitter]，
  /// 让提词器有最低限度的扫光反馈；朗读完成时推送 1.0 表示满进度。
  Future<bool> speakWithLocalTts(String text) async {
    try {
      progressEmitter(0.0);
      final estimatedSeconds = text.length / 4.0 / playbackRateGetter();
      final stopwatch = Stopwatch()..start();
      final progressTimer =
          Timer.periodic(const Duration(milliseconds: 100), (_) {
        final elapsed = stopwatch.elapsedMilliseconds / 1000.0;
        progressEmitter((elapsed / estimatedSeconds).clamp(0.0, 0.95));
      });
      try {
        await fallbackEngine.speak(text);
      } finally {
        progressTimer.cancel();
      }
      progressEmitter(1.0);
      onClearError();
      return true;
    } catch (e, st) {
      CyberLogger.captureWarning(
        e,
        stack: st,
        tag: 'tts',
        extra: {'context': '本地 TTS 降级朗读失败'},
      );
      return false;
    }
  }

  /// 安全删除指定路径文件（不存在或路径为空时静默忽略）。
  Future<void> deleteFileIfExists(String? path) async {
    if (path == null || path.isEmpty) return;
    try {
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {
      // 删除失败可容忍：下次清理周期会再次尝试。
    }
  }
}
