/// Xiaoyo 向视觉层暴露的音频状态。
enum XiaoyoAudioState {
  idle(0),
  buffering(1),
  playing(2),
  paused(3),
  error(4);

  final int riveValue;

  const XiaoyoAudioState(this.riveValue);
}

/// Xiaoyo 当前所在的产品场景。
enum XiaoyoContextMode {
  reading(0),
  library(1),
  companion(2),
  storyWorld(3);

  final int riveValue;

  const XiaoyoContextMode(this.riveValue);
}

/// Xiaoyo 的视觉语义快照。
///
/// 该模型不读取正文、不保存业务真值，也不依赖 Flutter、Riverpod 或
/// Rive。数值范围由适配器在写入视觉层前再次收窄，避免外部状态污染动画。
class XiaoyoSemantics {
  final XiaoyoAudioState audioState;
  final XiaoyoContextMode contextMode;
  final double lookX;
  final double lookY;
  final int growthStage;
  final double energy;
  final bool reduceMotion;

  const XiaoyoSemantics({
    this.audioState = XiaoyoAudioState.idle,
    this.contextMode = XiaoyoContextMode.companion,
    this.lookX = 0.0,
    this.lookY = 0.0,
    this.growthStage = 0,
    this.energy = 0.5,
    this.reduceMotion = false,
  });

  /// 将外部数值限制在 Rive 契约允许的范围内。
  XiaoyoSemantics get normalized => XiaoyoSemantics(
        audioState: audioState,
        contextMode: contextMode,
        lookX: lookX.clamp(-1.0, 1.0).toDouble(),
        lookY: lookY.clamp(-1.0, 1.0).toDouble(),
        growthStage: growthStage.clamp(0, 4),
        energy: energy.clamp(0.0, 1.0).toDouble(),
        reduceMotion: reduceMotion,
      );

  @override
  bool operator ==(Object other) =>
      other is XiaoyoSemantics &&
      other.audioState == audioState &&
      other.contextMode == contextMode &&
      other.lookX == lookX &&
      other.lookY == lookY &&
      other.growthStage == growthStage &&
      other.energy == energy &&
      other.reduceMotion == reduceMotion;

  @override
  int get hashCode => Object.hash(
        audioState,
        contextMode,
        lookX,
        lookY,
        growthStage,
        energy,
        reduceMotion,
      );
}
