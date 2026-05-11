// TTS 执行层生产环境适配器。
//
// 从 `tts_engine_service.dart` 抽出（PR-B，与 `tts_http_client.dart` 配对）。
// 把以下 3 个「包装第三方 SDK」的真实实现从上帝类里剥离：
// - [FlutterTtsFallbackEngine]：包装系统原生 FlutterTts（本地 TTS 降级引擎）
// - [RealAudioPlayer]：包装 audioplayers 的 AudioPlayer
// - [RealWakeLock]：包装 wakelock_plus 的 WakelockPlus
//
// 命名约定：原为私有 `_FlutterTtsFallbackEngine` / `_RealAudioPlayer` /
// `_RealWakeLock`。private 类对外不可见，public 化后外部 import 行为不变，
// 因此无需 `export show` 向后兼容。

import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'package:yueyou/core/config/tts_config.dart';
import 'package:yueyou/core/utils/cyber_logger.dart';
import 'package:yueyou/features/audio/domain/tts_engine_interfaces.dart';

/// 生产环境实现：包装系统原生 FlutterTts。
class FlutterTtsFallbackEngine implements TtsFallbackEngine {
  final FlutterTts _tts = FlutterTts();
  Completer<void>? _currentSpeech;

  @override
  Future<void> initialize() async {
    await _tts.setLanguage('zh-CN');
    await _tts.setSpeechRate(0.5);
    await _tts.setVolume(1.0);
    _tts.setCompletionHandler(() {
      if (_currentSpeech?.isCompleted == false) {
        _currentSpeech?.complete();
      }
      _currentSpeech = null;
    });
    _tts.setErrorHandler((dynamic msg) {
      if (_currentSpeech?.isCompleted == false) {
        _currentSpeech?.completeError(Exception('FlutterTts: $msg'));
      }
      _currentSpeech = null;
    });
  }

  @override
  Future<void> speak(String text) async {
    _currentSpeech = Completer<void>();
    try {
      await _tts.speak(text);
    } catch (e) {
      if (_currentSpeech?.isCompleted == false) {
        _currentSpeech?.complete();
      }
      _currentSpeech = null;
      rethrow;
    }
    try {
      await _currentSpeech!.future.timeout(TtsConfig.ttsLocalSpeakTimeout);
    } on TimeoutException catch (e, st) {
      CyberLogger.captureWarning(
        e,
        stack: st,
        tag: 'tts',
        extra: {'context': '本地 TTS 朗读超时'},
      );
    } catch (e, st) {
      CyberLogger.captureWarning(
        e,
        stack: st,
        tag: 'tts',
        extra: {'context': '本地 TTS 朗读错误'},
      );
    }
  }

  @override
  Future<void> stop() async {
    if (_currentSpeech?.isCompleted == false) {
      _currentSpeech?.complete();
    }
    _currentSpeech = null;
    try {
      await _tts.stop();
    } catch (_) {
      // dispose 路径允许静默失败：音频播放器可能已处于 stopped/completed 状态
    }
  }

  @override
  Future<void> dispose() async {
    await stop();
  }
}

/// 生产环境实现：包装真实 AudioPlayer。
class RealAudioPlayer implements TtsAudioPlayer {
  final AudioPlayer _player;
  RealAudioPlayer(this._player);
  @override
  Future<void> setSource(Source source) => _player.setSource(source);
  @override
  Future<void> resume() => _player.resume();
  @override
  Future<void> pause() => _player.pause();
  @override
  Future<void> stop() => _player.stop();
  @override
  Future<void> setVolume(double volume) => _player.setVolume(volume);
  @override
  Future<void> setPlaybackRate(double rate) => _player.setPlaybackRate(rate);
  @override
  Future<void> setAudioContext(AudioContext context) =>
      _player.setAudioContext(context);
  @override
  Stream<void> get onPlayerComplete => _player.onPlayerComplete;
  @override
  Stream<Duration> get onPositionChanged => _player.onPositionChanged;
  @override
  Stream<Duration> get onDurationChanged => _player.onDurationChanged;
  @override
  Future<void> dispose() => _player.dispose();
}

/// 生产环境实现：包装真实 WakelockPlus。
class RealWakeLock implements TtsWakeLock {
  @override
  Future<void> enable() async {
    try {
      await WakelockPlus.enable();
    } catch (_) {
      // 部分平台（如 Web / 桌面）可能不支持，静默降级即可。
    }
  }

  @override
  Future<void> disable() async {
    try {
      await WakelockPlus.disable();
    } catch (_) {
      // 同 enable() 的降级策略。
    }
  }
}
