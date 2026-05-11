// TTS 暂停中断守卫。
//
// 从 `tts_audio_notifier.dart` 抽出（PR-D）。封装「记录暂停时正在播放
// 的 item id + session」状态，防止 `stopAudio` 导致的延迟 `onComplete`
// 被误判为播放完成（参见 commit 55fa28c 的暂停误切下一句修复）。
//
// 单一职责：仅持有 item id 与 session，不参与状态机。

import 'package:yueyou/features/audio/domain/tts_audio_models.dart';

/// 暂停中断守卫：标记 `pause()` 时正在播放的 item，让后续因 `stopAudio`
/// 抢跑而触发的 onComplete 回调能识别出「这是被打断的，不是自然结束」。
class TtsPausedInterruptGuard {
  int? _itemId;
  int? _session;

  /// 标记被中断的 item；传入 null 时等同于 [clear]。
  void mark(TtsAudioItem? item) {
    if (item == null) {
      clear();
      return;
    }
    _itemId = item.id;
    _session = item.session;
  }

  /// 判断 [item] 是否是被暂停中断的那一句。
  bool isInterrupt(TtsAudioItem item) =>
      _itemId == item.id && _session == item.session;

  /// 清除中断标记。
  void clear() {
    _itemId = null;
    _session = null;
  }
}
