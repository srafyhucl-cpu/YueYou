import 'package:flutter/material.dart';

import '../../../core/database/storage_service.dart';

/// 全局设置 Provider
/// 完整复刻旧版 main.js 的 `t` 设置对象 + localStorage 持久化逻辑
/// 键名与 JS setting_* 前缀完全对齐
class SettingsProvider with ChangeNotifier {
  late bool sound;
  late bool storyTts;
  late String voice;
  late int idleTimeout;
  late double ttsRate;
  late double ambientVol;
  late bool ambientEnabled;

  /// App 启动时从 StorageService 恢复所有设置
  void loadFromStorage() {
    sound          = StorageService.getSettingSound();
    storyTts       = StorageService.getSettingStoryTts();
    voice          = StorageService.getSettingVoice();
    idleTimeout    = StorageService.getSettingIdleTimeout();
    ttsRate        = StorageService.getSettingTtsRate();
    ambientVol     = StorageService.getSettingAmbientVol();
    ambientEnabled = StorageService.getSettingAmbientEnabled();
    notifyListeners();
  }

  Future<void> setSound(bool v) async {
    sound = v;
    await StorageService.setSettingSound(v);
    notifyListeners();
  }

  Future<void> setStoryTts(bool v) async {
    storyTts = v;
    await StorageService.setSettingStoryTts(v);
    notifyListeners();
  }

  Future<void> setVoice(String v) async {
    voice = v;
    await StorageService.setSettingVoice(v);
    notifyListeners();
  }

  Future<void> setIdleTimeout(int v) async {
    idleTimeout = v;
    await StorageService.setSettingIdleTimeout(v);
    notifyListeners();
  }

  Future<void> setTtsRate(double v) async {
    ttsRate = v;
    await StorageService.setSettingTtsRate(v);
    notifyListeners();
  }

  Future<void> setAmbientVol(double v) async {
    ambientVol = v;
    await StorageService.setSettingAmbientVol(v);
    notifyListeners();
  }

  Future<void> setAmbientEnabled(bool v) async {
    ambientEnabled = v;
    await StorageService.setSettingAmbientEnabled(v);
    notifyListeners();
  }
}
