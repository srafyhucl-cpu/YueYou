import 'package:flutter_test/flutter_test.dart';
import 'package:yueyou/features/settings/providers/settings_provider.dart';
import 'package:yueyou/core/database/storage_service.dart';
import 'package:yueyou/core/utils/cyber_performance_detector.dart';
import '../../utils/test_utils.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

void main() {
  setUp(() async {
    await initializeTestEnvironment();
  });

  group('SettingsProvider', () {
    test('loadFromStorage 能加载默认值', () {
      final container = ProviderContainer();
      final p = container.read(settingsProvider.notifier);
      p.loadFromStorage();

      expect(p.sound, isTrue);
      expect(p.storyTts, isTrue);
      expect(p.voice, isNotEmpty);
      expect(p.idleTimeout, greaterThanOrEqualTo(0));
      expect(p.ttsRate, greaterThan(0));
      expect(p.ambientVol, inInclusiveRange(0.0, 1.0));
      expect(p.ambientEnabled, isTrue);
      expect(p.showGame, isTrue);
    });

    test('setSound 持久化并 notifyListeners', () async {
      final container = ProviderContainer();
      final p = container.read(settingsProvider.notifier);
      p.loadFromStorage();

      int notified = 0;
      p.addListener(() => notified++);

      await p.setSound(false);
      expect(p.sound, isFalse);
      expect(StorageService.getSettingSound(), isFalse);
      expect(notified, greaterThan(0));
    });

    test('setStoryTts 持久化并 notifyListeners', () async {
      final container = ProviderContainer();
      final p = container.read(settingsProvider.notifier);
      p.loadFromStorage();

      int notified = 0;
      p.addListener(() => notified++);

      await p.setStoryTts(false);
      expect(p.storyTts, isFalse);
      expect(StorageService.getSettingStoryTts(), isFalse);
      expect(notified, greaterThan(0));
    });

    test('setVoice 非白名单音色回退为默认值', () async {
      final container = ProviderContainer();
      final p = container.read(settingsProvider.notifier);
      p.loadFromStorage();

      await p.setVoice('zh-CN-InvalidVoice');
      expect(p.voice, 'zh-CN-XiaoxiaoNeural');
      expect(StorageService.getSettingVoice(), 'zh-CN-XiaoxiaoNeural');
    });

    test('loadFromStorage 读到残留非法音色时自动修正为默认值', () async {
      // 直接写入一个非法音色到存储层，模拟旧版数据残留
      await StorageService.setSettingVoice('zh-CN-ObsoleteVoice');

      final container = ProviderContainer();
      final p = container.read(settingsProvider.notifier);
      p.loadFromStorage();

      expect(p.voice, 'zh-CN-XiaoxiaoNeural');
    });

    test('setVoice 白名单内所有有效音色均可设置', () async {
      final container = ProviderContainer();
      final p = container.read(settingsProvider.notifier);
      p.loadFromStorage();

      final validVoices = [
        'zh-CN-XiaoxiaoNeural',
        'zh-CN-YunxiNeural',
        'zh-CN-YunjianNeural',
        'zh-CN-XiaoyiNeural',
        'zh-CN-XiaomengNeural',
      ];
      for (final v in validVoices) {
        await p.setVoice(v);
        expect(p.voice, v, reason: '$v 应可成功设置');
        expect(StorageService.getSettingVoice(), v);
      }
    });

    test(
        'setVoice / setIdleTimeout / setTtsRate / setAmbientVol / setAmbientEnabled 持久化',
        () async {
      final container = ProviderContainer();
      final p = container.read(settingsProvider.notifier);
      p.loadFromStorage();

      await p.setVoice('zh-CN-YunxiNeural');
      expect(StorageService.getSettingVoice(), 'zh-CN-YunxiNeural');

      await p.setIdleTimeout(12);
      expect(StorageService.getSettingIdleTimeout(), 12);

      await p.setTtsRate(1.2);
      expect(StorageService.getSettingTtsRate(), closeTo(1.2, 0.0001));

      await p.setAmbientVol(0.9);
      expect(StorageService.getSettingAmbientVol(), closeTo(0.9, 0.0001));

      await p.setAmbientEnabled(false);
      expect(StorageService.getSettingAmbientEnabled(), isFalse);

      await p.setShowGame(false);
      expect(p.showGame, isFalse);
      expect(StorageService.getSettingShowGame(), isFalse);

      // 验证动画性能配置
      expect(p.animationQualitySetting, 'auto');
      expect(p.currentAnimationLevel, isNotNull);

      await p.setAnimationQualitySetting('low');
      expect(p.animationQualitySetting, 'low');
      expect(p.currentAnimationLevel, CyberAnimationLevel.low);
      expect(StorageService.getSettingAnimationQuality(), 'low');
    });
  });
}
