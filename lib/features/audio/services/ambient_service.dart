import 'dart:math';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// 环境背景音乐服务（赛博朋克氛围音）
///
/// 使用 Voss-McCartney 算法生成粉噪声（Pink Noise），
/// 再叠加 60Hz 工频嗡鸣模拟城市电子环境音，
/// 全程代码生成，无需外部音频资源。
///
/// ## 使用方式
/// ```dart
/// // 初始化（在 main.dart SfxService.init 之后）
/// await AmbientService.init();
///
/// // 根据设置启停
/// AmbientService.setEnabled(ambientEnabled);
/// AmbientService.setVolume(ambientVol);
///
/// // App 切后台时暂停（在 didChangeAppLifecycleState 中调用）
/// AmbientService.pause();
/// AmbientService.resume();
///
/// // App 退出时释放
/// AmbientService.dispose();
/// ```
///
/// ## 架构约束
/// - 本 Service 位于 `features/audio/services/`，不引入任何 UI 依赖。
/// - 音量范围：`0.0`（静音）~ `1.0`（最大），对应 `ambientVol` 持久化值。
/// - 循环播放：ReleaseMode.loop，静默恢复（App 切回前台自动续播）。
class AmbientService {
  AmbientService._();

  static AudioPlayer? _player;

  /// 当前启用状态
  static bool _enabled = true;

  /// 当前音量（0.0 ~ 1.0）
  static double _volume = 0.5;

  /// 当前风格 (wuxia | warm)
  static String _style = 'wuxia';

  /// 是否已完成初始化（_player 创建完成）
  static bool _initialized = false;

  /// 是否因 App 切后台而主动暂停（区分用户关闭和系统暂停）
  static bool _pausedByLifecycle = false;

  /// 初始化音频播放器并预生成环境音 WAV
  ///
  /// 必须在 [WidgetsFlutterBinding.ensureInitialized] 之后调用，
  /// 通常与 [SfxService.init] 并列放置。
  static Future<void> init() async {
    if (_initialized) return;
    try {
      _player = AudioPlayer();
      await _player!.setAudioContext(
        AudioContext(
          android: const AudioContextAndroid(
            // 环境音作为底层背景氛围，不参与系统焦点竞争，防止被 TTS 强行中断
            audioFocus: AndroidAudioFocus.none,
            contentType: AndroidContentType.music,
            usageType: AndroidUsageType.media,
          ),
        ),
      );
      await _player!.setReleaseMode(ReleaseMode.loop);
      _initialized = true;
    } catch (e) {
      debugPrint('AmbientService.init error: $e');
      _initialized = false;
    }
  }

  // ── 公开控制接口 ──────────────────────────────────────────────────────────

  /// 设置启用状态（对应 `ambientEnabled` 设置项）
  ///
  /// - `true`：若当前未播放，立即开始播放
  /// - `false`：立即停止播放
  static Future<void> setEnabled(bool enabled) async {
    _enabled = enabled;
    debugPrint(' AmbientService.setEnabled: $enabled');
    if (!_initialized) return;
    if (_enabled) {
      await _startIfNeeded();
    } else {
      await _player?.stop();
    }
  }

  /// 设置风格（wuxia | warm）
  static Future<void> setStyle(String style) async {
    if (_style == style) return;
    _style = style;
    if (_enabled && _initialized) {
      // 风格变更时立即重新生成并播放
      await _startIfNeeded();
    }
  }

  /// 设置音量（对应 `ambientVol` 设置项，范围 0.0–1.0）
  static Future<void> setVolume(double volume) async {
    _volume = volume.clamp(0.0, 1.0);
    await _player?.setVolume(_volume);
  }

  /// App 切后台时调用，暂停播放
  static Future<void> pause() async {
    if (!_initialized || !_enabled) return;
    _pausedByLifecycle = true;
    await _player?.pause();
  }

  /// App 切回前台时调用，恢复播放
  static Future<void> resume() async {
    if (!_initialized || !_enabled) return;
    if (_pausedByLifecycle) {
      _pausedByLifecycle = false;
      await _startIfNeeded();
    }
  }

  /// 释放资源（在 App dispose 时调用）
  static void dispose() {
    try {
      _player?.dispose();
    } catch (_) {}
    _player = null;
    _initialized = false;
    _pausedByLifecycle = false;
  }

  // ── 内部实现 ──────────────────────────────────────────────────────────────

  /// 生成并开始播放（仅在 _enabled=true 时调用）
  static Future<void> _startIfNeeded() async {
    if (_player == null) return;
    try {
      final wav = _generateAmbientWav(style: _style);
      await _player!.setVolume(_volume);
      debugPrint(' AmbientService: 正在启动背景氛围音 [$_style] (vol=${_volume.toStringAsFixed(2)}, bytes=${wav.length})');
      await _player!.play(BytesSource(wav));
    } catch (e) {
      debugPrint('AmbientService._startIfNeeded error: $e');
      if (e is MissingPluginException) return; // 测试环境静默跳过
    }
  }

  /// 生成赛博朋克环境音 WAV（3 秒，44100Hz，16-bit 单声道）
  ///
  /// 音色构成：
  /// - Voss-McCartney 粉噪声（能量均匀分布在各频段，自然感）
  /// - 60Hz 工频嗡鸣（模拟城市电气设备背景音）
  /// - 柔和的低通感（通过权重衰减高频实现，无需 DSP 滤波器）
  /// - 头尾各 50ms 淡入/淡出，实现无缝循环
  @visibleForTesting
  static Uint8List generateAmbientWav() => _generateAmbientWav();

  static Uint8List _generateAmbientWav({
    String style = 'wuxia',
    int sampleRate = 44100,
    int durationMs = 30000,
  }) {
    // 根据风格动态调整声学参数
    // wuxia: 强调工频嗡鸣和重低通，模拟深邃、肃杀的古风背景感
    // warm: 降低嗡鸣，增加噪声波动，模拟炉火或呼吸的轻快感
    final bool isWarm = style == 'warm';
    final int humHz = isWarm ? 45 : 60;
    final double humVol = isWarm ? 0.08 : 0.18;
    final double noiseVol = isWarm ? 0.15 : 0.12;
    final double lowPassWeight = isWarm ? 0.8 : 0.92;

    final numSamples = (sampleRate * durationMs / 1000).round();
    final dataSize = numSamples * 2;
    final buffer = ByteData(44 + dataSize);
    _writeWavHeader(buffer, sampleRate, dataSize);

    final rand = Random(42);
    final pinkState = List<double>.filled(16, 0.0);
    double pinkRunningSum = 0.0;
    final fadeLen = (sampleRate * 0.005).round();
    double lastNoise = 0.0;

    for (int i = 0; i < numSamples; i++) {
      final t = i / sampleRate;

      for (int k = 0; k < 16; k++) {
        if (i % (1 << k) == 0) {
          final oldVal = pinkState[k];
          pinkState[k] = rand.nextDouble() * 2.0 - 1.0;
          pinkRunningSum += pinkState[k] - oldVal;
        }
      }
      
      double pink = (pinkRunningSum / 16.0).clamp(-1.0, 1.0);
      
      // 模拟微小波动 (Warm 风格增加随机抖动)
      if (isWarm && i % 4410 == 0) {
        pink *= (0.8 + rand.nextDouble() * 0.4);
      }

      pink = lastNoise * lowPassWeight + pink * (1.0 - lowPassWeight);
      lastNoise = pink;

      final hum = sin(2 * pi * humHz * t) * 0.7 + sin(4 * pi * humHz * t) * 0.3;
      double signal = pink * noiseVol + hum * humVol;

      if (i < fadeLen) {
        signal *= i / fadeLen;
      } else if (i > numSamples - fadeLen) {
        signal *= (numSamples - i) / fadeLen;
      }

      final sample = (signal * 32767).round().clamp(-32768, 32767);
      buffer.setInt16(44 + i * 2, sample, Endian.little);
    }

    return buffer.buffer.asUint8List();
  }

  /// 写入标准 16-bit mono PCM WAV 文件头（44 字节）
  static void _writeWavHeader(ByteData buf, int sampleRate, int dataSize) {
    // RIFF 块
    buf
      ..setUint8(0, 0x52) ..setUint8(1, 0x49) ..setUint8(2, 0x46) ..setUint8(3, 0x46)
      ..setUint32(4, 36 + dataSize, Endian.little)
      // WAVE
      ..setUint8(8, 0x57) ..setUint8(9, 0x41) ..setUint8(10, 0x56) ..setUint8(11, 0x45)
      // fmt 子块
      ..setUint8(12, 0x66) ..setUint8(13, 0x6D) ..setUint8(14, 0x74) ..setUint8(15, 0x20)
      ..setUint32(16, 16, Endian.little)    // fmt 块大小
      ..setUint16(20, 1, Endian.little)     // PCM 格式
      ..setUint16(22, 1, Endian.little)     // 单声道
      ..setUint32(24, sampleRate, Endian.little)
      ..setUint32(28, sampleRate * 2, Endian.little) // 字节率
      ..setUint16(32, 2, Endian.little)     // 块对齐
      ..setUint16(34, 16, Endian.little)    // 位深度
      // data 子块
      ..setUint8(36, 0x64) ..setUint8(37, 0x61) ..setUint8(38, 0x74) ..setUint8(39, 0x61)
      ..setUint32(40, dataSize, Endian.little);
  }

  // ── 测试专用 ──────────────────────────────────────────────────────────────

  /// 测试专用：重置所有状态
  @visibleForTesting
  static void resetForTesting() {
    try {
      _player?.dispose();
    } catch (_) {}
    _player = null;
    _initialized = false;
    _enabled = true;
    _volume = 0.5;
    _pausedByLifecycle = false;
  }

  /// 测试专用：注入初始化状态（避免真实平台调用）
  @visibleForTesting
  static void setInitializedForTesting({
    bool initialized = true,
    bool enabled = true,
    double volume = 0.5,
  }) {
    _initialized = initialized;
    _enabled = enabled;
    _volume = volume;
  }

  /// 当前是否处于启用状态（测试专用读取）
  @visibleForTesting
  static bool get enabledForTesting => _enabled;

  /// 当前音量（测试专用读取）
  @visibleForTesting
  static double get volumeForTesting => _volume;

  /// 是否因生命周期而暂停（测试专用读取）
  @visibleForTesting
  static bool get pausedByLifecycleForTesting => _pausedByLifecycle;
}
