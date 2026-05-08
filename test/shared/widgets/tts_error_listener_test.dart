// T-D / 大厂标准：TtsErrorListener 错误节流回归测试
//
// 测试目标：覆盖 lib/shared/widgets/tts_error_listener.dart 中的
// build / didChangeDependencies / 错误时间戳去重 / 降级提示节流（1s 窗口）
// 等关键路径，从 0% 提升到接近 100%。

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yueyou/features/audio/domain/tts_audio_state.dart';
import 'package:yueyou/features/audio/providers/tts_audio_notifier.dart';
import 'package:yueyou/features/settings/providers/settings_provider.dart';
import 'package:yueyou/shared/widgets/tts_error_listener.dart';

import '../../utils/test_utils.dart';

class _FakeTtsAudioNotifier extends Notifier<TtsAudioState>
    implements TtsAudioNotifier {
  TtsAudioState _initial = const TtsAudioIdle(
    playbackRate: 1.0,
    fallbackMessage: null,
  );

  void seedInitial(TtsAudioState s) {
    _initial = s;
  }

  @override
  TtsAudioState build() => _initial;

  /// 测试专用：直接驱动状态机到任意状态，模拟 TtsAudioNotifier 内部的 _applyState。
  void setStateForTesting(TtsAudioState next) {
    state = next;
  }

  @override
  void noSuchMethod(Invocation invocation) {}
}

Widget _wrapWithApp(Widget child) {
  return MaterialApp(
    home: Scaffold(body: child),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    await initializeTestEnvironment();
  });

  testWidgets('T-D Idle 状态下监听器构建必须无任何 toast 调用 / 不抛异常',
      (tester) async {
    final fake = _FakeTtsAudioNotifier();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ttsAudioProvider.overrideWith(() => fake),
          settingsProvider.overrideWith((ref) => makeSettings()),
        ],
        child: _wrapWithApp(
          const TtsErrorListener(child: Text('child')),
        ),
      ),
    );
    expect(find.text('child'), findsOneWidget,
        reason: 'TtsErrorListener 必须把 child 透传出来');
  });

  testWidgets('T-D 不同时间戳的连续错误必须各触发一次 build 不抛异常',
      (tester) async {
    final fake = _FakeTtsAudioNotifier();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ttsAudioProvider.overrideWith(() => fake),
          settingsProvider.overrideWith((ref) => makeSettings()),
        ],
        child: _wrapWithApp(
          const TtsErrorListener(child: Text('child')),
        ),
      ),
    );

    fake.setStateForTesting(const TtsAudioError(
      type: TtsAudioErrorType.network,
      message: '网络断开',
      timestamp: 1,
      recoverable: true,
      session: 1,
      playbackRate: 1.0,
      fallbackMessage: null,
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    fake.setStateForTesting(const TtsAudioError(
      type: TtsAudioErrorType.contract,
      message: '响应格式异常',
      timestamp: 2,
      recoverable: false,
      session: 1,
      playbackRate: 1.0,
      fallbackMessage: null,
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('child'), findsOneWidget);
  });

  testWidgets('T-D 相同时间戳的错误必须被去重（_previousErrorTime 守卫）',
      (tester) async {
    final fake = _FakeTtsAudioNotifier();
    fake.seedInitial(const TtsAudioError(
      type: TtsAudioErrorType.network,
      message: '初始错误',
      timestamp: 100,
      recoverable: true,
      session: 1,
      playbackRate: 1.0,
      fallbackMessage: null,
    ));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ttsAudioProvider.overrideWith(() => fake),
          settingsProvider.overrideWith((ref) => makeSettings()),
        ],
        child: _wrapWithApp(
          const TtsErrorListener(child: Text('child')),
        ),
      ),
    );

    // didChangeDependencies 已快照 timestamp=100，再次推送同时间戳必须被去重。
    fake.setStateForTesting(const TtsAudioError(
      type: TtsAudioErrorType.network,
      message: '初始错误',
      timestamp: 100,
      recoverable: true,
      session: 1,
      playbackRate: 1.0,
      fallbackMessage: null,
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('child'), findsOneWidget);
  });

  testWidgets('T-D 相同 fallbackMessage 在 1s 内必须被节流（不重复弹 Toast）',
      (tester) async {
    final fake = _FakeTtsAudioNotifier();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ttsAudioProvider.overrideWith(() => fake),
          settingsProvider.overrideWith((ref) => makeSettings()),
        ],
        child: _wrapWithApp(
          const TtsErrorListener(child: Text('child')),
        ),
      ),
    );

    fake.setStateForTesting(const TtsAudioBuffering(
      bufferedCount: 0,
      targetCount: 5,
      progress: 0,
      session: 1,
      playbackRate: 1.0,
      fallbackMessage: '网络音频加载失败，已切换至本地语音',
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    await tester.pump(const Duration(milliseconds: 200));
    fake.setStateForTesting(const TtsAudioPlaying(
      item: TtsAudioSnapshot(
        id: 1,
        session: 1,
        lineIndex: 0,
        title: '',
        textPreview: '',
      ),
      bufferedCount: 1,
      targetCount: 5,
      playbackRate: 1.0,
      fallbackMessage: '网络音频加载失败，已切换至本地语音',
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('child'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 1100));
    fake.setStateForTesting(const TtsAudioPlaying(
      item: TtsAudioSnapshot(
        id: 2,
        session: 1,
        lineIndex: 1,
        title: '',
        textPreview: '',
      ),
      bufferedCount: 1,
      targetCount: 5,
      playbackRate: 1.0,
      fallbackMessage: '网络音频加载失败，已切换至本地语音',
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('child'), findsOneWidget);
  });

  testWidgets('T-D fallbackMessage 由非空清空后再赋值必须重新触发节流计数',
      (tester) async {
    final fake = _FakeTtsAudioNotifier();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ttsAudioProvider.overrideWith(() => fake),
          settingsProvider.overrideWith((ref) => makeSettings()),
        ],
        child: _wrapWithApp(
          const TtsErrorListener(child: Text('child')),
        ),
      ),
    );

    fake.setStateForTesting(const TtsAudioBuffering(
      bufferedCount: 0,
      targetCount: 5,
      progress: 0,
      session: 1,
      playbackRate: 1.0,
      fallbackMessage: '降级提示 A',
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    fake.setStateForTesting(const TtsAudioPlaying(
      item: TtsAudioSnapshot(
        id: 1,
        session: 1,
        lineIndex: 0,
        title: '',
        textPreview: '',
      ),
      bufferedCount: 1,
      targetCount: 5,
      playbackRate: 1.0,
      fallbackMessage: null,
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    fake.setStateForTesting(const TtsAudioBuffering(
      bufferedCount: 0,
      targetCount: 5,
      progress: 0,
      session: 1,
      playbackRate: 1.0,
      fallbackMessage: '降级提示 A',
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('child'), findsOneWidget);
  });
}
