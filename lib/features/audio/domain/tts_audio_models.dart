import 'dart:async';

/// TTS 播放项。
///
/// 该模型用于描述已经进入播放链路的单句音频，必须绑定真实文本行号，
/// 以便阅读器可以在播放开始和结束时同步本地阅读进度。
class TtsAudioItem {
  final int id;
  final int session;
  final int lineIndex;
  final String text;
  final String title;
  final Duration estimatedDuration;

  TtsAudioItem({
    required this.id,
    required this.session,
    required this.lineIndex,
    required this.text,
    required this.title,
    required this.estimatedDuration,
  });
}

/// TTS 预取请求。
///
/// 该模型只描述需要生成音频的单句文本，不承载书籍标识、阅读进度
/// 或个性化设置，避免向服务端传递隐私数据。
class TtsAudioRequest {
  final int lineIndex;
  final String text;
  final String title;

  TtsAudioRequest({
    required this.lineIndex,
    required this.text,
    required this.title,
  });
}

/// TTS 文本源接口。
///
/// 音频状态机只依赖该接口获取下一句文本和通知播放进度，
/// 不直接依赖阅读器内部状态结构。
abstract interface class TtsSentenceSource {
  /// 获取指定会话的下一句有效朗读文本。
  Future<TtsAudioRequest?> nextTtsSentence(int session);

  /// 当前音频项开始播放。
  FutureOr<void> onTtsItemStarted(TtsAudioItem item);

  /// 当前音频项播放完成。
  FutureOr<void> onTtsItemFinished(TtsAudioItem item);
  /// 重置预取游标到当前阅读位置。
  void resetFetchIndex();
}

