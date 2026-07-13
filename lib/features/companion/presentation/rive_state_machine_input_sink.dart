import 'package:rive/rive.dart';
import 'package:yueyou/features/companion/presentation/xiaoyo_rive_input_adapter.dart';

/// 将统一 Xiaoyo 输入契约桥接到 Rive 状态机实例。
class RiveStateMachineInputSink implements XiaoyoRiveInputSink {
  final StateMachineController controller;

  const RiveStateMachineInputSink(this.controller);

  @override
  bool setNumber(String name, double value) {
    final input = controller.getNumberInput(name);
    if (input == null) return false;
    input.value = value;
    return true;
  }

  @override
  bool setBool(String name, bool value) {
    final input = controller.getBoolInput(name);
    if (input == null) return false;
    input.value = value;
    return true;
  }

  @override
  bool fire(String name) {
    final input = controller.getTriggerInput(name);
    if (input == null) return false;
    input.fire();
    return true;
  }
}
