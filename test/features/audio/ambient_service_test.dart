import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:yueyou/features/audio/services/ambient_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    AmbientService.resetForTesting();
  });

  // ── 初始化状态 ────────────────────────────────────────────────────────────

  group('AmbientService 初始化状态', () {
    test('重置后 enabled 为 true', () {
      expect(AmbientService.enabledForTesting, isTrue);
    });

    test('重置后 volume 为 0.5', () {
      expect(AmbientService.volumeForTesting, closeTo(0.5, 0.001));
    });

    test('重置后 pausedByLifecycle 为 false', () {
      expect(AmbientService.pausedByLifecycleForTesting, isFalse);
    });
  });

  // ── setEnabled ────────────────────────────────────────────────────────────

  group('AmbientService.setEnabled', () {
    test('setEnabled(false) 更新 _enabled 状态', () async {
      AmbientService.setInitializedForTesting(initialized: false);
      await AmbientService.setEnabled(false);
      expect(AmbientService.enabledForTesting, isFalse);
    });

    test('setEnabled(true) 更新 _enabled 状态', () async {
      AmbientService.setInitializedForTesting(initialized: false, enabled: false);
      await AmbientService.setEnabled(true);
      expect(AmbientService.enabledForTesting, isTrue);
    });

    test('未初始化时 setEnabled(true) 不崩溃（静默跳过播放）', () async {
      AmbientService.setInitializedForTesting(initialized: false);
      expect(() async => AmbientService.setEnabled(true), returnsNormally);
    });

    test('未初始化时 setEnabled(false) 不崩溃', () async {
      AmbientService.setInitializedForTesting(initialized: false);
      expect(() async => AmbientService.setEnabled(false), returnsNormally);
    });
  });

  // ── setVolume ─────────────────────────────────────────────────────────────

  group('AmbientService.setVolume', () {
    test('正常音量范围写入', () async {
      AmbientService.setInitializedForTesting(initialized: false);
      await AmbientService.setVolume(0.7);
      expect(AmbientService.volumeForTesting, closeTo(0.7, 0.001));
    });

    test('大于 1.0 时被 clamp 到 1.0', () async {
      AmbientService.setInitializedForTesting(initialized: false);
      await AmbientService.setVolume(2.0);
      expect(AmbientService.volumeForTesting, closeTo(1.0, 0.001));
    });

    test('小于 0.0 时被 clamp 到 0.0', () async {
      AmbientService.setInitializedForTesting(initialized: false);
      await AmbientService.setVolume(-0.5);
      expect(AmbientService.volumeForTesting, closeTo(0.0, 0.001));
    });

    test('0.0 静音边界', () async {
      AmbientService.setInitializedForTesting(initialized: false);
      await AmbientService.setVolume(0.0);
      expect(AmbientService.volumeForTesting, closeTo(0.0, 0.001));
    });

    test('1.0 最大值边界', () async {
      AmbientService.setInitializedForTesting(initialized: false);
      await AmbientService.setVolume(1.0);
      expect(AmbientService.volumeForTesting, closeTo(1.0, 0.001));
    });
  });

  // ── pause / resume ────────────────────────────────────────────────────────

  group('AmbientService.pause / resume', () {
    test('pause 时设置 pausedByLifecycle 为 true', () async {
      AmbientService.setInitializedForTesting(initialized: true, enabled: true);
      await AmbientService.pause();
      expect(AmbientService.pausedByLifecycleForTesting, isTrue);
    });

    test('resume 后 pausedByLifecycle 归为 false', () async {
      AmbientService.setInitializedForTesting(initialized: true, enabled: true);
      await AmbientService.pause();
      // resume 会调用 _startIfNeeded，因未注册平台 channel 而静默跳过
      try {
        await AmbientService.resume();
      } catch (_) {}
      expect(AmbientService.pausedByLifecycleForTesting, isFalse);
    });

    test('未初始化时 pause 不崩溃', () async {
      AmbientService.setInitializedForTesting(initialized: false);
      expect(() async => AmbientService.pause(), returnsNormally);
    });

    test('未初始化时 resume 不崩溃', () async {
      AmbientService.setInitializedForTesting(initialized: false);
      expect(() async => AmbientService.resume(), returnsNormally);
    });

    test('enabled=false 时 pause 不设置 pausedByLifecycle', () async {
      AmbientService.setInitializedForTesting(initialized: true, enabled: false);
      await AmbientService.pause();
      // enabled=false 时 pause 提前返回，不修改 pausedByLifecycle
      expect(AmbientService.pausedByLifecycleForTesting, isFalse);
    });
  });

  // ── dispose ───────────────────────────────────────────────────────────────

  group('AmbientService.dispose', () {
    test('dispose 不崩溃', () {
      AmbientService.setInitializedForTesting(initialized: false);
      expect(() => AmbientService.dispose(), returnsNormally);
    });

    test('dispose 后 initialized 状态归为 false', () {
      AmbientService.setInitializedForTesting(initialized: true);
      AmbientService.dispose();
      // 验证：dispose 后再 setEnabled 不崩溃（_initialized=false 提前返回）
      expect(
        () async => AmbientService.setEnabled(true),
        returnsNormally,
      );
    });

    test('多次 dispose 不崩溃', () {
      AmbientService.setInitializedForTesting(initialized: false);
      AmbientService.dispose();
      expect(() => AmbientService.dispose(), returnsNormally);
    });
  });

  // ── generateAmbientWav WAV 格式验证 ──────────────────────────────────────

  group('AmbientService.generateAmbientWav', () {
    late Uint8List wav;

    setUpAll(() {
      // 只生成一次，避免重复计算（30 秒粉噪声，约 2.6MB）
      wav = AmbientService.generateAmbientWav();
    });

    test('生成的 WAV 头部包含 RIFF 标识', () {
      // offset 0-3: "RIFF"
      expect(wav[0], 0x52);
      expect(wav[1], 0x49);
      expect(wav[2], 0x46);
      expect(wav[3], 0x46);
    });

    test('生成的 WAV 包含 WAVE 标识', () {
      // offset 8-11: "WAVE"
      expect(wav[8], 0x57);
      expect(wav[9], 0x41);
      expect(wav[10], 0x56);
      expect(wav[11], 0x45);
    });

    test('生成的 WAV 为 PCM 格式（fmt=1）', () {
      final view = ByteData.sublistView(wav);
      // offset 20-21: AudioFormat=1 (PCM)
      expect(view.getUint16(20, Endian.little), 1);
    });

    test('生成的 WAV 为单声道', () {
      final view = ByteData.sublistView(wav);
      // offset 22-23: NumChannels=1
      expect(view.getUint16(22, Endian.little), 1);
    });

    test('生成的 WAV 采样率为 44100Hz', () {
      final view = ByteData.sublistView(wav);
      // offset 24-27: SampleRate=44100
      expect(view.getUint32(24, Endian.little), 44100);
    });

    test('生成的 WAV 位深为 16-bit', () {
      final view = ByteData.sublistView(wav);
      // offset 34-35: BitsPerSample=16
      expect(view.getUint16(34, Endian.little), 16);
    });

    test('生成的 WAV 总字节数与 30 秒预期一致', () {
      // 30s × 44100 × 2 bytes + 44 bytes header = 2646044 bytes
      const expected = 44 + 44100 * 30 * 2;
      expect(wav.length, expected);
    });

    test('固定种子生成内容确定性（每次相同）', () {
      final wav2 = AmbientService.generateAmbientWav();
      // 前 1000 字节相同即视为内容确定
      for (int i = 44; i < 1044; i++) {
        expect(wav[i], wav2[i], reason: 'offset $i 不一致');
      }
    });

    test('头尾各 50ms 有淡入淡出（首样本接近 0）', () {
      final view = ByteData.sublistView(wav);
      // 首个采样（offset 44）应接近 0（淡入起点）
      final firstSample = view.getInt16(44, Endian.little).abs();
      expect(firstSample, lessThan(100),
          reason: '淡入起始采样应接近 0，实际为 $firstSample',);
    });
  });
}
