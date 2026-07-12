import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:yueyou/core/database/storage_service.dart';
import 'package:yueyou/core/utils/cyber_performance_detector.dart';

/// 供 Riverpod 使用的全局设置 Provider
final settingsProvider = ChangeNotifierProvider<SettingsProvider>((ref) {
  final p = SettingsProvider();
  p.loadFromStorage();
  return p;
});

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
  late String ambientStyle;

  /// 环境音开关 — 预留字段，待环境音播放器功能实现后启用
  /// 当前无 UI 入口，也无消费方，仅持久化存档保持向后兼容
  late bool ambientEnabled;

  /// 动画质量设置：'auto' | 'high' | 'medium' | 'low'
  late String animationQualitySetting;

  /// 是否展示 2048 陪伴模式；关闭后主界面只保留听读内容。
  late bool showGame;
  CyberAnimationLevel? _autoDetectedLevel;

  /// App 启动时从 StorageService 恢复所有设置
  void loadFromStorage() {
    sound = StorageService.getSettingSound();
    storyTts = StorageService.getSettingStoryTts();
    voice = StorageService.getSettingVoice();
    // 校验音色有效性，无效则回退默认（防止 storage 残留无效音色名）
    // 注意：此白名单须与 server/handler_tts.go allowedVoices 保持同步。
    if (voice != 'zh-CN-XiaoxiaoNeural' &&
        voice != 'zh-CN-YunxiNeural' &&
        voice != 'zh-CN-YunjianNeural' &&
        voice != 'zh-CN-XiaoyiNeural' &&
        voice != 'zh-CN-XiaomengNeural') {
      voice = 'zh-CN-XiaoxiaoNeural';
    }
    idleTimeout = StorageService.getSettingIdleTimeout();
    ttsRate = StorageService.getSettingTtsRate();
    ambientVol = StorageService.getSettingAmbientVol();
    ambientEnabled = StorageService.getSettingAmbientEnabled();
    ambientStyle = StorageService.getSettingAmbientStyle();
    animationQualitySetting = StorageService.getSettingAnimationQuality();
    showGame = StorageService.getSettingShowGame();

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
    if (v != 'zh-CN-XiaoxiaoNeural' &&
        v != 'zh-CN-YunxiNeural' &&
        v != 'zh-CN-YunjianNeural' &&
        v != 'zh-CN-XiaoyiNeural' &&
        v != 'zh-CN-XiaomengNeural') {
      v = 'zh-CN-XiaoxiaoNeural';
    }
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

  Future<void> setAmbientStyle(String v) async {
    ambientStyle = v;
    await StorageService.setSettingAmbientStyle(v);
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

  /// 持久化 2048 陪伴模式开关。
  Future<void> setShowGame(bool v) async {
    showGame = v;
    await StorageService.setSettingShowGame(v);
    notifyListeners();
  }
}
