// TTS 音频状态机辅助纯函数。
//
// 从 `tts_audio_notifier.dart` 抽出（PR-D）。本文件属 domain 层：
// - 仅暴露顶层纯函数，零状态、零副作用；
// - 不依赖任何 Flutter UI 库；
// - 输入输出都是 [TtsAudioState] / [TtsAudioItem] / [TtsAudioSnapshot]
//   等业务数据模型。

import 'package:yueyou/features/audio/domain/tts_audio_models.dart';
import 'package:yueyou/features/audio/domain/tts_audio_state.dart';
import 'package:yueyou/features/audio/domain/tts_http_models.dart';

/// 原地重建 [current] 状态，仅替换 [rate]，其余字段保持不变。
///
/// 用于 `cycleSpeed` 等只改倍速的操作，避免手写 5 个分支的复制粘贴。
TtsAudioState copyStateWithRate(TtsAudioState current, double rate) =>
    switch (current) {
      TtsAudioIdle() => TtsAudioIdle(
          playbackRate: rate,
          fallbackMessage: current.fallbackMessage,
        ),
      TtsAudioBuffering() => TtsAudioBuffering(
          bufferedCount: current.bufferedCount,
          targetCount: current.targetCount,
          progress: current.progress,
          session: current.session,
          playbackRate: rate,
          fallbackMessage: current.fallbackMessage,
        ),
      TtsAudioPlaying() => TtsAudioPlaying(
          item: current.item,
          bufferedCount: current.bufferedCount,
          targetCount: current.targetCount,
          playbackRate: rate,
          fallbackMessage: current.fallbackMessage,
        ),
      TtsAudioPaused() => TtsAudioPaused(
          item: current.item,
          bufferedCount: current.bufferedCount,
          targetCount: current.targetCount,
          session: current.session,
          playbackRate: rate,
          fallbackMessage: current.fallbackMessage,
        ),
      TtsAudioError() => TtsAudioError(
          type: current.type,
          message: current.message,
          timestamp: current.timestamp,
          recoverable: current.recoverable,
          session: current.session,
          playbackRate: rate,
          fallbackMessage: current.fallbackMessage,
        ),
    };

/// 把音频状态机当前状态映射成 [TtsEngineService] 影子状态机的等价值，
/// 便于引擎通过 `syncShadow` 向下游 ReaderProvider 透传播放进度。
TtsPlaybackState audioStateToEngineState(TtsAudioState audioState) {
  return switch (audioState) {
    TtsAudioIdle() => TtsPlaybackState.disabled,
    TtsAudioBuffering() => TtsPlaybackState.buffering,
    TtsAudioPlaying() => TtsPlaybackState.playing,
    TtsAudioPaused() => TtsPlaybackState.paused,
    TtsAudioError() => TtsPlaybackState.error,
  };
}

/// 把 [TtsAudioItem] 投影成 UI 友好的快照。
///
/// 提词器需要完整朗读文本（合并短句时常远超 20 字），故 `textPreview`
/// 直接复用 `item.text`，不再做长度截断。
TtsAudioSnapshot snapshotOf(TtsAudioItem item) {
  return TtsAudioSnapshot(
    id: item.id,
    session: item.session,
    lineIndex: item.lineIndex,
    title: item.title,
    textPreview: item.text,
  );
}
