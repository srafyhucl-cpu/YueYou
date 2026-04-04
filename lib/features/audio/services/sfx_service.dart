import 'dart:math';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// 物理音效引擎 (V4 — 基于旧版 Web 端已验证音效移植)
///
/// 旧版 Web 端核心：440→880Hz 上行正弦扫频 + 0.12 音量 + 指数衰减 + 300ms
/// 本版在此基础上做 4 阶段递进，保持极简单层架构。
///
/// 零杂音保证：上行扫频使用解析式 chirp 相位公式
/// φ(t) = 2π(f₀t + (f₁-f₀)t²/2T)，连续可微，零相位突变。
class SfxService {
  static const bool _enabled = true;
  static AudioPlayer? _mergePlayer;

  /// 预生成的 4 阶段音效 WAV
  static final List<Uint8List> _tierWavs = [];

  static Future<void> init() async {
    _mergePlayer = AudioPlayer();
    await _mergePlayer!.setReleaseMode(ReleaseMode.stop);
    _tierWavs.clear();

    // 🟢 Stage 1 (≤16): 轻盈上行 — 与旧版完全一致
    // 旧版原始参数：440→880Hz, 100ms chirp, 0.12 vol, 300ms
    _tierWavs.add(_generateMergeTone(
      freqStart: 440,
      freqEnd: 880,
      chirpMs: 100,
      decayRate: 16,
      durationMs: 300,
      volume: 0.12,
    ));

    // 🔵 Stage 2 (≤128): 稍宽音域 + 略厚
    _tierWavs.add(_generateMergeTone(
      freqStart: 400,
      freqEnd: 900,
      chirpMs: 110,
      decayRate: 14,
      durationMs: 340,
      volume: 0.15,
    ));

    // 🟣 Stage 3 (≤1024): 更深沉的上行
    _tierWavs.add(_generateMergeTone(
      freqStart: 350,
      freqEnd: 950,
      chirpMs: 120,
      decayRate: 12,
      durationMs: 380,
      volume: 0.18,
    ));

    // 🟡 Stage 4 (>1024): 宽幅上行 + 最饱满
    _tierWavs.add(_generateMergeTone(
      freqStart: 330,
      freqEnd: 1000,
      chirpMs: 130,
      decayRate: 10,
      durationMs: 420,
      volume: 0.22,
    ));
  }

  static Future<void> playMoveFeedback(int mergedValue) async {
    if (!_enabled) return;

    if (mergedValue <= 16) {
      await HapticFeedback.lightImpact();
    } else if (mergedValue <= 128) {
      await HapticFeedback.mediumImpact();
    } else if (mergedValue <= 1024) {
      await HapticFeedback.heavyImpact();
    } else {
      await HapticFeedback.heavyImpact();
      await Future.delayed(const Duration(milliseconds: 40));
      await HapticFeedback.heavyImpact();
    }
  }

  /// 触发合并音效
  static Future<void> playMerge(int mergedValue) async {
    if (!_enabled) return;

    // 异步触发震动，不阻塞音频
    playMoveFeedback(mergedValue);

    if (_mergePlayer != null && _tierWavs.isNotEmpty) {
      final tier = _getTier(mergedValue);
      _mergePlayer!.stop().then((_) {
        return _mergePlayer!.play(BytesSource(_tierWavs[tier]));
      }).catchError((e) {
        debugPrint('SfxService.playMerge audio error: $e');
      });
    }
  }

  /// 4 阶段档位映射
  static int _getTier(int mergedValue) {
    if (mergedValue <= 16) return 0;
    if (mergedValue <= 128) return 1;
    if (mergedValue <= 1024) return 2;
    return 3;
  }

  /// 生成上行扫频合并音效 WAV（移植自旧版 Web 端）
  ///
  /// 旧版 Web Audio API 等效逻辑：
  ///   o.frequency.setValueAtTime(f0, now);
  ///   o.frequency.exponentialRampToValueAtTime(f1, now + chirpT);
  ///   g.gain.setValueAtTime(vol, now);
  ///   g.gain.exponentialRampToValueAtTime(0.001, now + duration);
  ///
  /// 本版用解析式 chirp 精确复现，零杂音：
  ///   φ(t) = 2π(f₀t + (f₁-f₀)t²/2T)  [t < chirpT]
  ///   φ(t) = φ(chirpT) + 2πf₁(t-chirpT) [t ≥ chirpT]
  static Uint8List _generateMergeTone({
    required double freqStart,
    required double freqEnd,
    required int chirpMs,
    required double decayRate,
    required int durationMs,
    required double volume,
    int sampleRate = 44100,
  }) {
    final numSamples = (sampleRate * durationMs / 1000).round();
    final dataSize = numSamples * 2;
    final buffer = ByteData(44 + dataSize);
    _writeWavHeader(buffer, sampleRate, dataSize, 36 + dataSize);

    final chirpT = chirpMs / 1000.0;
    final attackEnd = (sampleRate * 0.003).round();

    // 预计算 chirp 过渡点相位（保证连续）
    final phaseAtChirpEnd =
        2 * pi * (freqStart * chirpT + (freqEnd - freqStart) * chirpT / 2);

    for (int i = 0; i < numSamples; i++) {
      final t = i / sampleRate;

      // ---- 3ms 柔攻击 ----
      double attack = 1.0;
      if (i < attackEnd) {
        attack = 0.5 - 0.5 * cos(pi * i / attackEnd);
      }

      // ---- 解析式上行 chirp ----
      double phase;
      if (t < chirpT) {
        phase = 2 *
            pi *
            (freqStart * t + (freqEnd - freqStart) * t * t / (2 * chirpT));
      } else {
        phase = phaseAtChirpEnd + 2 * pi * freqEnd * (t - chirpT);
      }

      // ---- 指数衰减包络（复现 exponentialRampToValueAtTime）----
      final envelope = exp(-t * decayRate);

      final signal = sin(phase) * envelope * volume * attack;
      final sample = (signal * 32767).round().clamp(-32768, 32767);
      buffer.setInt16(44 + i * 2, sample, Endian.little);
    }
    return buffer.buffer.asUint8List();
  }

  /// 写入标准 16-bit mono PCM WAV 文件头
  static void _writeWavHeader(
      ByteData buffer, int sampleRate, int dataSize, int fileSize) {
    const riff = [0x52, 0x49, 0x46, 0x46];
    const wave = [0x57, 0x41, 0x56, 0x45];
    const fmt = [0x66, 0x6D, 0x74, 0x20];
    const data = [0x64, 0x61, 0x74, 0x61];
    for (int i = 0; i < 4; i++) {
      buffer.setUint8(i, riff[i]);
    }
    buffer.setUint32(4, fileSize, Endian.little);
    for (int i = 0; i < 4; i++) {
      buffer.setUint8(8 + i, wave[i]);
    }
    for (int i = 0; i < 4; i++) {
      buffer.setUint8(12 + i, fmt[i]);
    }
    buffer.setUint32(16, 16, Endian.little);
    buffer.setUint16(20, 1, Endian.little);
    buffer.setUint16(22, 1, Endian.little);
    buffer.setUint32(24, sampleRate, Endian.little);
    buffer.setUint32(28, sampleRate * 2, Endian.little);
    buffer.setUint16(32, 2, Endian.little);
    buffer.setUint16(34, 16, Endian.little);
    for (int i = 0; i < 4; i++) {
      buffer.setUint8(36 + i, data[i]);
    }
    buffer.setUint32(40, dataSize, Endian.little);
  }

  static void dispose() {
    try {
      _mergePlayer?.dispose();
    } catch (_) {
      // 忽略平台通道异常（测试环境或热重载时可能发生）
    }
    _mergePlayer = null;
    _tierWavs.clear();
  }
}
