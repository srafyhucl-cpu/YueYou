// TTS 引擎执行层抽象接口（音频播放 / 唤醒锁 / 本地降级）。
//
// 从 `tts_engine_service.dart` 抽出（PR-A，与 `tts_network_interfaces.dart`
// 配对）。本文件属 domain 层：
// - 仅声明纯接口，不包含生产实现；
// - 唯一允许的第三方依赖是 `audioplayers`（音频 SDK，非 UI 库），用于
//   在 [TtsAudioPlayer] 接口签名中表达 `Source` 与 `AudioContext` 类型；
// - 严禁引入 `package:flutter/material.dart` 或任何 UI 库。

import 'package:audioplayers/audioplayers.dart';

/// 抽象接口，用于测试时注入 Mock。
abstract class TtsAudioPlayer {
  Future<void> setSource(Source source);
  Future<void> resume();
  Future<void> pause();
  Future<void> stop();
  Future<void> setVolume(double volume);
  Future<void> setPlaybackRate(double rate);
  Future<void> setAudioContext(AudioContext context);
  Stream<void> get onPlayerComplete;
  Stream<Duration> get onPositionChanged;
  Stream<Duration> get onDurationChanged;
  Future<void> dispose();
}

/// 抽象接口，用于测试时注入 Mock。
abstract class TtsWakeLock {
  Future<void> enable();
  Future<void> disable();
}

/// 抽象接口，用于测试时注入 Mock —— 本地 TTS 降级引擎。
abstract class TtsFallbackEngine {
  Future<void> initialize();
  Future<void> speak(String text);
  Future<void> stop();
  Future<void> dispose();
}
