import 'package:yueyou/features/companion/domain/xiaoyo_semantics.dart';
import 'package:yueyou/features/companion/domain/xiaoyo_triggers.dart';

/// Rive 状态机输入的最小抽象，便于在不加载二进制资源的情况下测试映射。
abstract interface class XiaoyoRiveInputSink {
  /// 写入数字输入；输入不存在或类型不符时返回 false。
  bool setNumber(String name, double value);

  /// 写入布尔输入；输入不存在或类型不符时返回 false。
  bool setBool(String name, bool value);

  /// 触发一次动作；输入不存在或类型不符时返回 false。
  bool fire(String name);
}

/// 将 Xiaoyo 语义快照映射到统一 Rive 输入契约。
class XiaoyoRiveInputAdapter {
  final XiaoyoRiveInputSink sink;
  final void Function(String inputName)? onMissingInput;
  XiaoyoSemantics? _lastSemantics;
  XiaoyoTrigger? _activeMajorTrigger;
  final Set<String> _reportedMissingInputs = <String>{};

  XiaoyoRiveInputAdapter({
    required this.sink,
    this.onMissingInput,
  });

  /// 写入最新快照；相同快照不会重复触碰 Rive 输入。
  void apply(XiaoyoSemantics semantics) {
    final normalized = semantics.normalized;
    if (_lastSemantics == normalized) return;
    _lastSemantics = normalized;

    _setNumber('audioState', normalized.audioState.riveValue.toDouble());
    _setNumber('contextMode', normalized.contextMode.riveValue.toDouble());
    _setNumber('lookX', normalized.lookX);
    _setNumber('lookY', normalized.lookY);
    _setNumber('growthStage', normalized.growthStage.toDouble());
    _setNumber('energy', normalized.energy);
    _setBool('reduceMotion', normalized.reduceMotion);
  }

  /// 触发一次低频动作，重大动作正在播放时直接丢弃重复动作。
  bool fire(XiaoyoTrigger trigger) {
    if (trigger.isMajor && _activeMajorTrigger != null) return false;
    final fired = sink.fire(_inputName(trigger));
    if (fired && trigger.isMajor) _activeMajorTrigger = trigger;
    if (!fired) _reportMissing(_inputName(trigger));
    return fired;
  }

  /// 在 Rive 完成重大动作后释放动作闸门，不积压历史事件。
  void completeMajorAction() => _activeMajorTrigger = null;

  void _setNumber(String name, double value) {
    if (!sink.setNumber(name, value)) _reportMissing(name);
  }

  void _setBool(String name, bool value) {
    if (!sink.setBool(name, value)) _reportMissing(name);
  }

  void _reportMissing(String inputName) {
    if (_reportedMissingInputs.add(inputName)) onMissingInput?.call(inputName);
  }

  String _inputName(XiaoyoTrigger trigger) => switch (trigger) {
        XiaoyoTrigger.tap => 'tap',
        XiaoyoTrigger.chapterComplete => 'chapterComplete',
        XiaoyoTrigger.bookComplete => 'bookComplete',
        XiaoyoTrigger.honorUnlocked => 'honorUnlocked',
        XiaoyoTrigger.activityReward => 'activityReward',
        XiaoyoTrigger.returnAfterBreak => 'returnAfterBreak',
        XiaoyoTrigger.highTileMerged => 'highTileMerged',
      };
}

extension on XiaoyoTrigger {
  bool get isMajor => switch (this) {
        XiaoyoTrigger.bookComplete || XiaoyoTrigger.honorUnlocked => true,
        _ => false,
      };
}
