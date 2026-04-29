import 'package:flutter/material.dart';

import '../../../core/database/storage_service.dart';
import '../../../core/utils/cyber_performance_detector.dart';

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

  /// 环境音开关 — 预留字段，待环境音播放器功能实现后启用
  /// 当前无 UI 入口，也无消费方，仅持久化存档保持向后兼容
  late bool ambientEnabled;

  /// 动画质量设置：'auto' | 'high' | 'medium' | 'low'
  late String animationQualitySetting;
  CyberAnimationLevel? _autoDetectedLevel;

  /// App 启动时从 StorageService 恢复所有设置
  void loadFromStorage() {
    sound = StorageService.getSettingSound();
    storyTts = StorageService.getSettingStoryTts();
    voice = StorageService.getSettingVoice();
    idleTimeout = StorageService.getSettingIdleTimeout();
    ttsRate = StorageService.getSettingTtsRate();
    ambientVol = StorageService.getSettingAmbientVol();
    ambientEnabled = StorageService.getSettingAmbientEnabled();
    animationQualitySetting = StorageService.getSettingAnimationQuality();
    
    if (animationQualitySetting == 'auto') {
      _autoDetectedLevel = CyberPerformanceDetector.detectLevel();
    }
    
    notifyListeners();
  }

  /// 计算属性：获取当前界面应当采用的动画等级
  CyberAnimationLevel get currentAnimationLevel {
    switch (animationQualitySetting) {
      case 'high':
        return CyberAnimationLevel.high;
      case 'medium':
        return CyberAnimationLevel.medium;
      case 'low':
        return CyberAnimationLevel.low;
      case 'auto':
      default:
        return _autoDetectedLevel ??= CyberPerformanceDetector.detectLevel();
    }
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

  Future<void> setAnimationQualitySetting(String v) async {
    animationQualitySetting = v;
    if (v == 'auto') {
      _autoDetectedLevel = CyberPerformanceDetector.detectLevel();
    }
    await StorageService.setSettingAnimationQuality(v);
    notifyListeners();
  }
}
