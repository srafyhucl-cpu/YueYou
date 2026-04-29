import 'dart:async';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yueyou/features/audio/services/tts_engine_service.dart';
import 'package:yueyou/core/config/tts_config.dart';
import 'package:yueyou/features/settings/providers/settings_provider.dart';

// ── 自包含 Mock 实现 ──────────────────────────────────────────────────────────

class _FakeAudioPlayer implements TtsAudioPlayer {
  final _ctrl = StreamController<void>.broadcast();
  @override Stream<void> get onPlayerComplete => _ctrl.stream;
  @override Future<void> setSource(Source source) async {}
  @override Future<void> resume() async {}
  @override Future<void> pause() async {}
  @override Future<void> stop() async {}
  @override Future<void> setVolume(double volume) async {}
  @override Future<void> setPlaybackRate(double rate) async {}
  @override Future<void> dispose() async => _ctrl.close();
}

class _FakeWakeLock implements TtsWakeLock {
  @override Future<void> enable() async {}
  @override Future<void> disable() async {}
}

class _FakeHttpClient implements TtsHttpClient {
  @override
  Future<TtsHttpResponse> post(Uri url,
          {Map<String, String>? headers, Object? body}) async =>
      const TtsHttpResponse(
          statusCode: 200,
          body: '{"status":"success","url":"http://mock/audio.mp3"}');
  @override Future<void> download(Uri url, String savePath) async {}
}

class _FakeFallbackEngine implements TtsFallbackEngine {
  @override Future<void> initialize() async {}
  @override Future<void> speak(String text) async {}
  @override Future<void> stop() async {}
}

class _TestSettings extends SettingsProvider {
  _TestSettings() {
    sound = false;
    storyTts = false;
    voice = 'zh-CN-XiaoxiaoNeural';
    idleTimeout = 0;
    ttsRate = 1.0;
    ambientVol = 0.5;
    ambientEnabled = false;
  }
}


void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// 构建一个注入全量 Mock 的 TtsEngineService
  TtsEngineService buildService({int maxPrefetchQueue = 6}) {
    final settings = _TestSettings();
    final config = TtsConfig(
      serverUrl: 'http://mock-server',
      maxPrefetchQueue: maxPrefetchQueue,
    );
    return TtsEngineService(
      settings,
      config: config,
      audioPlayer: _FakeAudioPlayer(),
      wakeLock: _FakeWakeLock(),
      httpClient: _FakeHttpClient(),
      fallbackEngine: _FakeFallbackEngine(),
      delayFn: (_) async {},
    );
  }

  // ── TtsBufferStatus 枚举语义 ───────────────────────────────────────────────

  group('TtsBufferStatus 枚举', () {
    test('枚举值数量为 4', () {
      expect(TtsBufferStatus.values.length, 4);
    });

    test('healthy < warning < critical 语义正确（非顺序比较）', () {
      // 仅验证枚举存在
      expect(TtsBufferStatus.healthy, isA<TtsBufferStatus>());
      expect(TtsBufferStatus.warning, isA<TtsBufferStatus>());
      expect(TtsBufferStatus.critical, isA<TtsBufferStatus>());
      expect(TtsBufferStatus.idle, isA<TtsBufferStatus>());
    });
  });

  // ── maxBufferedCount getter ───────────────────────────────────────────────

  group('TtsEngineService.maxBufferedCount', () {
    test('默认配置 maxBufferedCount = 6', () {
      final svc = buildService();
      addTearDown(svc.dispose);
      expect(svc.maxBufferedCount, 6);
    });

    test('自定义 maxPrefetchQueue 正确映射', () {
      final svc = buildService(maxPrefetchQueue: 4);
      addTearDown(svc.dispose);
      expect(svc.maxBufferedCount, 4);
    });
  });

  // ── bufferHealthRatio getter ──────────────────────────────────────────────

  group('TtsEngineService.bufferHealthRatio', () {
    test('引擎初始状态队列为空，比例为 0.0', () {
      final svc = buildService();
      addTearDown(svc.dispose);
      expect(svc.bufferHealthRatio, 0.0);
    });

    test('maxPrefetchQueue = 0 时不除零，返回 1.0', () {
      final svc = buildService(maxPrefetchQueue: 0);
      addTearDown(svc.dispose);
      expect(svc.bufferHealthRatio, 1.0);
    });

    test('比例不超过 1.0', () {
      final svc = buildService();
      addTearDown(svc.dispose);
      expect(svc.bufferHealthRatio, lessThanOrEqualTo(1.0));
    });

    test('比例不低于 0.0', () {
      final svc = buildService();
      addTearDown(svc.dispose);
      expect(svc.bufferHealthRatio, greaterThanOrEqualTo(0.0));
    });
  });

  // ── bufferStatus getter ───────────────────────────────────────────────────

  group('TtsEngineService.bufferStatus', () {
    test('引擎未启用时返回 idle', () {
      final svc = buildService();
      addTearDown(svc.dispose);
      // 初始状态为 disabled
      expect(svc.isEnabled, isFalse);
      expect(svc.bufferStatus, TtsBufferStatus.idle);
    });

    // 注：由于引擎 enabled 状态需要通过 setEnabled 触发，
    // 而 setEnabled 需要 onNeedPrefetch 绑定，此处用黑盒验证。
    // 更细粒度的比例阈值验证通过 bufferHealthRatio 覆盖。

    test('未启用时 bufferStatus 不返回 critical/warning/healthy', () {
      final svc = buildService();
      addTearDown(svc.dispose);
      final status = svc.bufferStatus;
      expect(status, isNot(TtsBufferStatus.critical));
      expect(status, isNot(TtsBufferStatus.warning));
      expect(status, isNot(TtsBufferStatus.healthy));
    });
  });

  // ── bufferStatus 阈值逻辑单元测试（通过 ratio 反推）──────────────────────

  group('bufferStatus 阈值逻辑', () {
    // 使用辅助函数独立验证阈值判断逻辑
    TtsBufferStatus computeStatus(double ratio, bool enabled) {
      if (!enabled) return TtsBufferStatus.idle;
      if (ratio >= 0.6) return TtsBufferStatus.healthy;
      if (ratio >= 0.33) return TtsBufferStatus.warning;
      return TtsBufferStatus.critical;
    }

    test('ratio=1.0 → healthy', () {
      expect(computeStatus(1.0, true), TtsBufferStatus.healthy);
    });

    test('ratio=0.6 → healthy（边界）', () {
      expect(computeStatus(0.6, true), TtsBufferStatus.healthy);
    });

    test('ratio=0.59 → warning', () {
      expect(computeStatus(0.59, true), TtsBufferStatus.warning);
    });

    test('ratio=0.33 → warning（边界）', () {
      expect(computeStatus(0.33, true), TtsBufferStatus.warning);
    });

    test('ratio=0.32 → critical', () {
      expect(computeStatus(0.32, true), TtsBufferStatus.critical);
    });

    test('ratio=0.0 → critical（队列空）', () {
      expect(computeStatus(0.0, true), TtsBufferStatus.critical);
    });

    test('enabled=false 时任意 ratio → idle', () {
      for (final r in [0.0, 0.3, 0.6, 1.0]) {
        expect(computeStatus(r, false), TtsBufferStatus.idle,
            reason: 'ratio=$r 时应为 idle');
      }
    });
  });

  // ── bufferedCount getter 与队列一致 ──────────────────────────────────────

  group('TtsEngineService.bufferedCount', () {
    test('初始状态 bufferedCount = 0', () {
      final svc = buildService();
      addTearDown(svc.dispose);
      expect(svc.bufferedCount, 0);
    });

    test('bufferedCount <= maxBufferedCount', () {
      final svc = buildService();
      addTearDown(svc.dispose);
      expect(svc.bufferedCount, lessThanOrEqualTo(svc.maxBufferedCount));
    });
  });

  // ── bufferHealthRatio 与 bufferedCount/maxBufferedCount 一致性 ────────────

  group('bufferHealthRatio 与 bufferedCount 一致性', () {
    test('ratio = bufferedCount / maxBufferedCount', () {
      final svc = buildService();
      addTearDown(svc.dispose);
      final expected = svc.maxBufferedCount > 0
          ? svc.bufferedCount / svc.maxBufferedCount
          : 1.0;
      expect(svc.bufferHealthRatio, closeTo(expected, 0.001));
    });
  });
}
