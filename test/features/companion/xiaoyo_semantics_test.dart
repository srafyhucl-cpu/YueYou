import 'package:flutter_test/flutter_test.dart';
import 'package:yueyou/features/companion/domain/xiaoyo_semantics.dart';
import 'package:yueyou/features/companion/domain/xiaoyo_triggers.dart';
import 'package:yueyou/features/companion/presentation/xiaoyo_rive_input_adapter.dart';

class _FakeInputSink implements XiaoyoRiveInputSink {
  final List<String> numberWrites = <String>[];
  final List<String> boolWrites = <String>[];
  final List<String> triggers = <String>[];

  @override
  bool setNumber(String name, double value) {
    numberWrites.add('$name=$value');
    return true;
  }

  @override
  bool setBool(String name, bool value) {
    boolWrites.add('$name=$value');
    return true;
  }

  @override
  bool fire(String name) {
    triggers.add(name);
    return true;
  }
}

void main() {
  test('语义快照会把越界视觉值收窄到 Rive 契约范围', () {
    const semantics = XiaoyoSemantics(
      lookX: 4.0,
      lookY: -4.0,
      growthStage: 9,
      energy: -1.0,
    );

    expect(semantics.normalized.lookX, 1.0);
    expect(semantics.normalized.lookY, -1.0);
    expect(semantics.normalized.growthStage, 4);
    expect(semantics.normalized.energy, 0.0);
  });

  test('相同快照不会重复写入 Rive 输入', () {
    final sink = _FakeInputSink();
    final adapter = XiaoyoRiveInputAdapter(sink: sink);
    const semantics = XiaoyoSemantics();

    adapter
      ..apply(semantics)
      ..apply(semantics);

    expect(sink.numberWrites, hasLength(6));
    expect(sink.boolWrites, hasLength(1));
  });

  test('重大动作正在播放时重复触发不会排队，完成后才接受下一次', () {
    final sink = _FakeInputSink();
    final adapter = XiaoyoRiveInputAdapter(sink: sink);

    expect(adapter.fire(XiaoyoTrigger.bookComplete), isTrue);
    expect(adapter.fire(XiaoyoTrigger.honorUnlocked), isFalse);
    expect(sink.triggers, <String>['bookComplete']);

    adapter.completeMajorAction();
    expect(adapter.fire(XiaoyoTrigger.honorUnlocked), isTrue);
    expect(sink.triggers, <String>['bookComplete', 'honorUnlocked']);
  });

  test('缺失输入只报告一次，其他输入仍可继续映射', () {
    final missing = <String>[];
    final sink = _MissingInputSink();
    final adapter = XiaoyoRiveInputAdapter(
      sink: sink,
      onMissingInput: missing.add,
    );

    adapter
      ..apply(const XiaoyoSemantics())
      ..apply(const XiaoyoSemantics(energy: 0.8));

    expect(missing, contains('audioState'));
    expect(missing.where((name) => name == 'audioState'), hasLength(1));
    expect(sink.numberWrites, contains('energy=0.8'));
  });
}

class _MissingInputSink extends _FakeInputSink {
  @override
  bool setNumber(String name, double value) {
    if (name == 'audioState') return false;
    return super.setNumber(name, value);
  }
}
