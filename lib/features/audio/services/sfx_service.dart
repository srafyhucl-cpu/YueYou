import 'dart:math';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

/// 物理音效引擎
/// 完整复刻旧版 AudioManager.js 的 playEffect('merge') 触发机制
/// 使用程序化生成的 WAV 字节流，零外部音效资产依赖
class SfxService {
  static final AudioPlayer _player = AudioPlayer();
  static Uint8List? _mergeSfx;

  /// 初始化：预生成合并音效字节流（App 启动时调用一次）
  static Future<void> init() async {
    try {
      _mergeSfx = _generateBeepWav(
        frequency: 880.0,
        durationSeconds: 0.10,
        amplitude: 0.55,
      );
    } catch (e) {
      debugPrint('SfxService.init error: $e');
    }
  }

  /// 触发合并音效 —— 对应 JS: l.playEffect('merge')
  /// 仅在 settings.sound == true 时调用
  static Future<void> playMerge() async {
    if (_mergeSfx == null) return;
    try {
      await _player.stop();
      await _player.play(BytesSource(_mergeSfx!));
    } catch (e) {
      debugPrint('SfxService.playMerge error: $e');
    }
  }

  static void dispose() {
    _player.dispose();
  }

  // ── WAV 程序化生成器 ────────────────────────────────────────────────────────
  /// 生成单声道 16-bit PCM WAV 字节流（带淡入淡出包络，避免爆音）
  static Uint8List _generateBeepWav({
    int sampleRate = 22050,
    double frequency = 880.0,
    double durationSeconds = 0.10,
    double amplitude = 0.5,
  }) {
    final int numSamples = (sampleRate * durationSeconds).round();
    final ByteData pcm = ByteData(numSamples * 2);

    for (int i = 0; i < numSamples; i++) {
      final double t = i / sampleRate;
      // 淡入 10ms + 淡出 20ms 包络
      final double fadeIn = (t < 0.01) ? t / 0.01 : 1.0;
      final double fadeOut =
          (durationSeconds - t < 0.02) ? (durationSeconds - t) / 0.02 : 1.0;
      final double env = fadeIn * fadeOut;
      final double sample = sin(2 * pi * frequency * t) * amplitude * env;
      pcm.setInt16(
          i * 2, (sample * 32767).round().clamp(-32768, 32767), Endian.little);
    }

    final ByteData wav = ByteData(44 + numSamples * 2);
    // RIFF 头
    _writeAscii(wav, 0, 'RIFF');
    wav.setUint32(4, 36 + numSamples * 2, Endian.little);
    _writeAscii(wav, 8, 'WAVE');
    // fmt chunk
    _writeAscii(wav, 12, 'fmt ');
    wav.setUint32(16, 16, Endian.little);
    wav.setUint16(20, 1, Endian.little); // PCM
    wav.setUint16(22, 1, Endian.little); // mono
    wav.setUint32(24, sampleRate, Endian.little);
    wav.setUint32(28, sampleRate * 2, Endian.little); // byteRate
    wav.setUint16(32, 2, Endian.little); // blockAlign
    wav.setUint16(34, 16, Endian.little); // bitsPerSample
    // data chunk
    _writeAscii(wav, 36, 'data');
    wav.setUint32(40, numSamples * 2, Endian.little);

    final result = wav.buffer.asUint8List();
    result.setRange(44, 44 + numSamples * 2, pcm.buffer.asUint8List());
    return result;
  }

  static void _writeAscii(ByteData data, int offset, String text) {
    for (int i = 0; i < text.length; i++) {
      data.setUint8(offset + i, text.codeUnitAt(i));
    }
  }
}
