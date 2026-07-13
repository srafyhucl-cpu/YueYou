// TTS 本地降级与恢复控制器。
//
// 从 `tts_audio_notifier.dart` 抽出（PR-D）。封装「连续网络失败 → 切到
// 本地 FlutterTts 朗读 → 每句播完探测网络 → 网络恢复退出降级」整条降级
// 流水线。本控制器：
// - 仅持有自身需要的临时字段（`isDegradedToLocal`、`fallbackMessage`）；
// - 通过构造器注入 14 个 callback / getter / setter，避免反向持有 notifier；
// - 单元测试时可以用纯 Mock 替换所有依赖。

import 'dart:async';

import 'package:yueyou/core/utils/cyber_logger.dart';
import 'package:yueyou/features/audio/domain/tts_audio_buffer.dart';
import 'package:yueyou/features/audio/domain/tts_audio_state.dart';
import 'package:yueyou/features/audio/providers/tts_paused_interrupt_guard.dart';
import 'package:yueyou/features/audio/services/tts_engine_service.dart';

/// 降级控制器：暴露两个公开方法 [degradeToLocal] / [pumpDegraded]，
/// 其余皆为通过 callback 与外部通信的副作用。
class TtsFallbackController {
  final TtsEngineService engine;
  final TtsPausedInterruptGuard pausedGuard;
  final TtsSentenceSource? Function() sentenceSourceGetter;
  final int Function() sessionGetter;
  final double Function() playbackRateGetter;
  final TtsAudioBuffer Function() bufferGetter;
  final TtsAudioItem? Function() currentItemGetter;
  final void Function(TtsAudioItem?) currentItemSetter;
  final bool Function() isDisposed;
  final void Function(TtsAudioState) applyState;
  final TtsAudioSnapshot Function(TtsAudioItem) snapshotOf;
  final void Function(int count) onConsecutiveFailuresReset;
  final void Function(String?) fallbackMessageSetter;

  /// 是否当前处于本地降级模式。
  bool isDegradedToLocal = false;

  TtsFallbackController({
    required this.engine,
    required this.pausedGuard,
    required this.sentenceSourceGetter,
    required this.sessionGetter,
    required this.playbackRateGetter,
    required this.bufferGetter,
    required this.currentItemGetter,
    required this.currentItemSetter,
    required this.isDisposed,
    required this.applyState,
    required this.snapshotOf,
    required this.onConsecutiveFailuresReset,
    required this.fallbackMessageSetter,
  });

  /// 降级到本地 TTS。
  ///
  /// 前置条件：先停用远程播放器，再启动本地降级，杜绝二重唱。
  Future<void> degradeToLocal(
    TtsAudioRequest request, {
    int? expectedSession,
  }) async {
    final session = expectedSession ?? sessionGetter();
    bool isCurrentSession() => !isDisposed() && sessionGetter() == session;

    // 停用远程播放器，确保不二重唱
    pausedGuard.clear();
    await engine.stopAudio();
    await engine.pauseAudio();
    if (!isCurrentSession()) return;

    isDegradedToLocal = true;
    const message = '网络音频加载失败，已切换至本地语音';
    fallbackMessageSetter(message);
    CyberLogger.captureWarning(
      Exception('TTS degraded to local engine'),
      tag: 'tts',
    );

    final fallbackItem = TtsAudioItem(
      id: DateTime.now().microsecondsSinceEpoch,
      session: sessionGetter(),
      lineIndex: request.lineIndex,
      endLineIndex: request.endLineIndex,
      text: request.text,
      title: request.title,
      estimatedDuration: const Duration(seconds: 5),
    );
    currentItemSetter(fallbackItem);

    final source = sentenceSourceGetter();
    if (source != null) {
      unawaited(
        Future.microtask(() async {
          try {
            source.onTtsItemStarted(fallbackItem);
          } catch (e, st) {
            CyberLogger.captureWarning(
              e,
              stack: st,
              tag: 'tts',
              extra: {'context': '降级 onTtsItemStarted 回调异常'},
            );
          }
        }),
      );
    }

    final buffer = bufferGetter();
    applyState(
      TtsAudioPlaying(
        item: snapshotOf(fallbackItem),
        bufferedCount: buffer.count,
        targetCount: buffer.maxSize,
        playbackRate: playbackRateGetter(),
        fallbackMessage: message,
      ),
    );

    final ok = await engine.speakWithLocalTts(request.text);
    if (isCurrentSession() &&
        ok &&
        currentItemGetter()?.id == fallbackItem.id) {
      currentItemSetter(null);
      if (source != null) {
        unawaited(
          Future.microtask(() async {
            try {
              source.onTtsItemFinished(fallbackItem);
            } catch (e, st) {
              CyberLogger.captureWarning(
                e,
                stack: st,
                tag: 'tts',
                extra: {'context': '降级 onTtsItemFinished 回调异常'},
              );
            }
          }),
        );
      }
    }
  }

  /// 退化模式下的纯本地循环。
  ///
  /// 每句播完后探测服务器，网络恢复则自动切回云端 TTS。
  Future<void> pumpDegraded() async {
    final source = sentenceSourceGetter();
    if (source == null) return;
    final session = sessionGetter();
    final request = await source.nextTtsSentence(session);
    if (isDisposed() || sessionGetter() != session) return;
    if (request == null) {
      // 无更多内容 → 尝试切回远程
      isDegradedToLocal = false;
      onConsecutiveFailuresReset(0);
      fallbackMessageSetter(null);
      return;
    }
    await degradeToLocal(request, expectedSession: session);
    // 每句播完后探测一次网络，恢复则退出降级
    if (!isDisposed() && sessionGetter() == session && isDegradedToLocal) {
      final reachable = await engine.pingServer();
      if (reachable) {
        isDegradedToLocal = false;
        onConsecutiveFailuresReset(0);
        fallbackMessageSetter(null);
        CyberLogger.captureMessage('[TTS] 网络已恢复，退出降级模式', tag: 'tts');
      }
    }
  }
}
