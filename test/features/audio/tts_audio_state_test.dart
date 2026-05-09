// 阶段 1 推进：TtsAudioState sealed class 全分支单元测试。
//
// 该文件验证 [TtsAudioState] 的：
//   1. isActive getter 在 5 种状态下的正确分类；
//   2. 各 final class（Idle / Buffering / Playing / Paused / Error）的
//      字段读取与类型守卫；
//   3. TtsAudioSnapshot 与 TtsAudioErrorType 的常量构造。
//
// 大厂级要求：sealed 状态机的每个分支必须有显式断言，避免新增状态时
// 隐式破坏 UI 穷尽 switch。

import 'package:flutter_test/flutter_test.dart';
import 'package:yueyou/features/audio/domain/tts_audio_state.dart';

void main() {
  group('TtsAudioState - sealed 类型与字段', () {
    test('TtsAudioIdle 默认字段 + isActive=false', () {
      const state = TtsAudioIdle(
        playbackRate: 1.0,
        fallbackMessage: null,
      );
      expect(state.playbackRate, 1.0);
      expect(state.fallbackMessage, isNull);
      expect(state.isActive, isFalse, reason: 'Idle 不可视为活跃态');
    });

    test('TtsAudioBuffering 字段读取 + isActive=true', () {
      const state = TtsAudioBuffering(
        bufferedCount: 1,
        targetCount: 3,
        progress: 0.33,
        session: 7,
        playbackRate: 1.25,
        fallbackMessage: '降级提示',
      );
      expect(state.bufferedCount, 1);
      expect(state.targetCount, 3);
      expect(state.progress, closeTo(0.33, 1e-9));
      expect(state.session, 7);
      expect(state.playbackRate, 1.25);
      expect(state.fallbackMessage, '降级提示');
      expect(state.isActive, isTrue, reason: 'Buffering 必须为活跃态');
    });

    test('TtsAudioPlaying 携带 snapshot + isActive=true', () {
      const snap = TtsAudioSnapshot(
        id: 42,
        session: 1,
        lineIndex: 5,
        title: '第三章',
        textPreview: '这是一段预览',
      );
      const state = TtsAudioPlaying(
        item: snap,
        bufferedCount: 2,
        targetCount: 3,
        playbackRate: 1.0,
        fallbackMessage: null,
      );
      expect(state.item, same(snap));
      expect(state.item.id, 42);
      expect(state.item.lineIndex, 5);
      expect(state.item.title, '第三章');
      expect(state.bufferedCount, 2);
      expect(state.targetCount, 3);
      expect(state.isActive, isTrue, reason: 'Playing 必须为活跃态');
    });

    test('TtsAudioPaused snapshot 可空 + isActive=false', () {
      const state = TtsAudioPaused(
        item: null,
        bufferedCount: 0,
        targetCount: 3,
        session: 9,
        playbackRate: 1.5,
        fallbackMessage: null,
      );
      expect(state.item, isNull);
      expect(state.session, 9);
      expect(state.playbackRate, 1.5);
      expect(state.isActive, isFalse,
          reason: 'Paused 不再持续播放，isActive 必须为 false');
    });

    test('TtsAudioError 全字段 + isActive=false', () {
      const state = TtsAudioError(
        type: TtsAudioErrorType.network,
        message: '网络错误',
        timestamp: 1234567890,
        recoverable: true,
        session: 1,
        playbackRate: 1.0,
        fallbackMessage: '已切到本地降级',
      );
      expect(state.type, TtsAudioErrorType.network);
      expect(state.message, '网络错误');
      expect(state.timestamp, 1234567890);
      expect(state.recoverable, isTrue);
      expect(state.session, 1);
      expect(state.fallbackMessage, '已切到本地降级');
      expect(state.isActive, isFalse, reason: 'Error 状态必须停止播放');
    });

    test('TtsAudioErrorType 枚举完备性：5 种类型必须各自可构造', () {
      // 防回归：UI 层穷尽 switch 必须覆盖全部 5 个枚举值。
      const allTypes = <TtsAudioErrorType>[
        TtsAudioErrorType.network,
        TtsAudioErrorType.contract,
        TtsAudioErrorType.playback,
        TtsAudioErrorType.lifecycle,
        TtsAudioErrorType.unknown,
      ];
      expect(TtsAudioErrorType.values, equals(allTypes),
          reason: '新增 / 删除枚举值时必须同步更新 UI 与本测试');
    });

    test('TtsAudioSnapshot 字段不可变 + 同一数据可比较', () {
      const a = TtsAudioSnapshot(
        id: 1,
        session: 1,
        lineIndex: 0,
        title: 'X',
        textPreview: 'Y',
      );
      const b = TtsAudioSnapshot(
        id: 1,
        session: 1,
        lineIndex: 0,
        title: 'X',
        textPreview: 'Y',
      );
      // 默认 Object 等价（identity）：两个常量 const 字面量会被 dart 复用。
      expect(identical(a, b), isTrue,
          reason: 'const 构造的 TtsAudioSnapshot 必须被 Dart 常量池复用');
      expect(a.id, b.id);
      expect(a.textPreview, b.textPreview);
    });
  });

  // ── 穷尽 switch 防回归：sealed class 必须可被 5 分支 switch 消费 ──
  group('TtsAudioState - 穷尽 switch 守卫', () {
    String describe(TtsAudioState s) => switch (s) {
          TtsAudioIdle() => 'idle',
          TtsAudioBuffering() => 'buffering',
          TtsAudioPlaying() => 'playing',
          TtsAudioPaused() => 'paused',
          TtsAudioError() => 'error',
        };

    test('5 状态分支均可被 switch 表达式正确分派', () {
      const idle = TtsAudioIdle(playbackRate: 1.0, fallbackMessage: null);
      const buffering = TtsAudioBuffering(
        bufferedCount: 0,
        targetCount: 3,
        progress: 0,
        session: 0,
        playbackRate: 1.0,
        fallbackMessage: null,
      );
      const playing = TtsAudioPlaying(
        item: TtsAudioSnapshot(
          id: 1,
          session: 0,
          lineIndex: 0,
          title: '',
          textPreview: '',
        ),
        bufferedCount: 1,
        targetCount: 3,
        playbackRate: 1.0,
        fallbackMessage: null,
      );
      const paused = TtsAudioPaused(
        item: null,
        bufferedCount: 0,
        targetCount: 0,
        session: 0,
        playbackRate: 1.0,
        fallbackMessage: null,
      );
      const error = TtsAudioError(
        type: TtsAudioErrorType.unknown,
        message: '',
        timestamp: 0,
        recoverable: false,
        session: 0,
        playbackRate: 1.0,
        fallbackMessage: null,
      );
      expect(describe(idle), 'idle');
      expect(describe(buffering), 'buffering');
      expect(describe(playing), 'playing');
      expect(describe(paused), 'paused');
      expect(describe(error), 'error');
    });
  });
}
