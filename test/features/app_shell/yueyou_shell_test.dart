import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yueyou/core/config/feature_flags.dart';
import 'package:yueyou/features/audio/domain/tts_audio_state.dart';
import 'package:yueyou/features/audio/providers/tts_audio_notifier.dart';
import 'package:yueyou/features/app_shell/presentation/yueyou_shell.dart';
import 'package:yueyou/features/app_shell/providers/app_shell_provider.dart';

class _FakeTtsAudioNotifier extends Notifier<TtsAudioState>
    implements TtsAudioNotifier {
  @override
  TtsAudioState build() => const TtsAudioPlaying(
        item: TtsAudioSnapshot(
          id: 1,
          session: 7,
          lineIndex: 3,
          title: '第一章',
          textPreview: '当前句段',
        ),
        bufferedCount: 2,
        targetCount: 6,
        playbackRate: 1.0,
        fallbackMessage: null,
      );

  @override
  void noSuchMethod(Invocation invocation) {}
}

class _SessionProbe extends ConsumerWidget {
  const _SessionProbe();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(ttsAudioProvider);
    return Text(switch (state) {
      TtsAudioPlaying(:final item) =>
        'session:${item.session}:${item.lineIndex}',
      _ => 'session:unknown',
    });
  }
}

void main() {
  test('阶段性功能开关默认全部关闭', () {
    expect(FeatureFlags.readingFirstShell, isFalse);
    expect(FeatureFlags.xiaoyoV2, isFalse);
    expect(FeatureFlags.xiaoyoValueSystem, isFalse);
    expect(FeatureFlags.commercePreview, isFalse);
    expect(FeatureFlags.xiaoyo3d, isFalse);
  });

  testWidgets('三根导航只切换页签并保留 IndexedStack 页面', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: YueYouShell(
            showMiniPlayer: false,
            pages: const [
              Text('听读页面'),
              Text('书架页面'),
              Text('陪伴页面'),
            ],
          ),
        ),
      ),
    );

    expect(find.text('听读页面'), findsOneWidget);
    expect(find.byType(IndexedStack), findsOneWidget);

    await tester.tap(find.text('书架'));
    await tester.pump();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(YueYouShell)),
    );
    expect(container.read(appShellTabProvider), AppShellTab.library);
    expect(find.text('书架'), findsOneWidget);
    expect(find.text('书架页面'), findsOneWidget);
  });

  testWidgets('切换根页面不重建或改变 Mini Player 的会话与当前句', (tester) async {
    final fakeAudio = _FakeTtsAudioNotifier();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [ttsAudioProvider.overrideWith(() => fakeAudio)],
        child: MaterialApp(
          home: YueYouShell(
            pages: const [
              Text('听读页面'),
              Text('书架页面'),
              Text('陪伴页面'),
            ],
            miniPlayer: const _SessionProbe(),
          ),
        ),
      ),
    );

    expect(find.text('session:7:3'), findsOneWidget);
    await tester.tap(find.text('书架'));
    await tester.pump();
    expect(find.text('session:7:3'), findsOneWidget);
    await tester.tap(find.text('陪伴'));
    await tester.pump();
    expect(find.text('session:7:3'), findsOneWidget);
  });
}
