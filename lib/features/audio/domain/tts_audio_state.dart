/// TTS 音频状态机的错误分类。
///
/// 该枚举只表达可用于业务决策的错误类型，不承载原始异常文本，
/// 避免把用户内容、阅读进度或本地路径带入 UI 与日志系统。
enum TtsAudioErrorType {
  /// 网络请求超时或连接失败。
  network,

  /// 服务端响应格式不符合 TTS 契约。
  contract,

  /// 本地音频文件下载、写入或播放失败。
  playback,

  /// 资源释放、生命周期竞争等内部状态错误。
  lifecycle,

  /// 暂未归类的可恢复异常。
  unknown,
}

/// TTS 当前播放项的脱敏快照。
///
/// [textPreview] 只允许保存短预览文本，严禁保存完整正文。
class TtsAudioSnapshot {
  final int id;
  final int session;
  final int lineIndex;
  final String title;
  final String textPreview;

  const TtsAudioSnapshot({
    required this.id,
    required this.session,
    required this.lineIndex,
    required this.title,
    required this.textPreview,
  });
}

/// TTS 音频流状态树。
///
/// UI 层必须使用 Dart 3 的穷尽 `switch` 消费该状态，避免遗漏新增状态。
sealed class TtsAudioState {
  const TtsAudioState();

  /// 当前播放倍速，用于 UI 展示，不触发任何播放副作用。
  double get playbackRate;

  /// TTS 降级提示，当前仅供全局提示层消费。
  String? get fallbackMessage;

  /// 是否代表音频流处于活跃态。
  bool get isActive => switch (this) {
        TtsAudioIdle() => false,
        TtsAudioBuffering() => true,
        TtsAudioPlaying() => true,
        TtsAudioPaused() => false,
        TtsAudioError() => false,
      };
}

/// 空闲状态：尚未启动或已完全停止。
final class TtsAudioIdle extends TtsAudioState {
  @override
  final double playbackRate;
  @override
  final String? fallbackMessage;

  const TtsAudioIdle({
    required this.playbackRate,
    required this.fallbackMessage,
  });
}

/// 缓冲状态：正在预取音频或等待队列达到可播放水位。
final class TtsAudioBuffering extends TtsAudioState {
  final int bufferedCount;
  final int targetCount;
  final double progress;
  final int session;
  @override
  final double playbackRate;
  @override
  final String? fallbackMessage;

  const TtsAudioBuffering({
    required this.bufferedCount,
    required this.targetCount,
    required this.progress,
    required this.session,
    required this.playbackRate,
    required this.fallbackMessage,
  });
}

/// 播放状态：播放器正在消费某个已下载的音频项。
final class TtsAudioPlaying extends TtsAudioState {
  final TtsAudioSnapshot item;
  final int bufferedCount;
  final int targetCount;
  @override
  final double playbackRate;
  @override
  final String? fallbackMessage;

  const TtsAudioPlaying({
    required this.item,
    required this.bufferedCount,
    required this.targetCount,
    required this.playbackRate,
    required this.fallbackMessage,
  });
}

/// 暂停状态：保留当前播放快照，等待恢复。
final class TtsAudioPaused extends TtsAudioState {
  final TtsAudioSnapshot? item;
  final int bufferedCount;
  final int targetCount;
  final int session;
  @override
  final double playbackRate;
  @override
  final String? fallbackMessage;

  const TtsAudioPaused({
    required this.item,
    required this.bufferedCount,
    required this.targetCount,
    required this.session,
    required this.playbackRate,
    required this.fallbackMessage,
  });
}

/// 错误状态：播放链路出现可恢复或不可恢复异常。
final class TtsAudioError extends TtsAudioState {
  final TtsAudioErrorType type;
  final String message;
  final int timestamp;
  final bool recoverable;
  final int session;
  @override
  final double playbackRate;
  @override
  final String? fallbackMessage;

  const TtsAudioError({
    required this.type,
    required this.message,
    required this.timestamp,
    required this.recoverable,
    required this.session,
    required this.playbackRate,
    required this.fallbackMessage,
  });
}
