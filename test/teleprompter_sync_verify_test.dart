import 'package:flutter_test/flutter_test.dart';
import 'package:yueyou/features/audio/services/tts_engine_service.dart';
import 'package:yueyou/features/settings/providers/settings_provider.dart';
import 'utils/test_utils.dart'; // 修正为相对路径导入
import 'dart:async';

// 注入式 Mock 播放器，用于模拟物理进度反馈
class MockProgressAudioPlayer implements TtsAudioPlayer {
  final _posController = StreamController<Duration>.broadcast();
  final _durController = StreamController<Duration>.broadcast();

  @override
  Stream<Duration> get onPositionChanged => _posController.stream;
  @override
  Stream<Duration> get onDurationChanged => _durController.stream;

  void emitPosition(Duration pos) => _posController.add(pos);
  void emitDuration(Duration dur) => _durController.add(dur);

  @override
  Future<void> setAudioContext(dynamic context) async {}
  @override
  Future<void> setVolume(double volume) async {}
  @override
  Future<void> setPlaybackRate(double rate) async {}
  @override
  Future<void> stop() async {}
  @override
  Future<void> pause() async {}
  @override
  Future<void> dispose() async {
    await _posController.close();
    await _durController.close();
  }
  @override
  Stream<void> get onPlayerComplete => const Stream.empty();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('提词器同步验证：物理进度反馈与重置逻辑', () async {
    await initializeTestEnvironment();
    final mockPlayer = MockProgressAudioPlayer();
    final service = TtsEngineService(
      SettingsProvider(),
      audioPlayer: mockPlayer,
      externalSettingsListener: false,
    );

    // 记录进度流输出
    final List<double> progressLogs = [];
    final sub = service.progressStream.listen((p) => progressLogs.add(p));

    // --- 场景 1: 正常播放推进 ---
    mockPlayer.emitDuration(const Duration(seconds: 10));
    await Future.delayed(Duration.zero); // 等待 stream 传递
    
    mockPlayer.emitPosition(const Duration(seconds: 5));
    await Future.delayed(Duration.zero);
    
    expect(progressLogs.last, equals(0.5)); // 5s / 10s = 0.5
    print('✅ 物理进度同步正常: 0.5');

    // --- 场景 2: 切换文件重置 ---
    // 调用 playFile 触发重置
    await service.playFile('dummy_path');
    await Future.delayed(Duration.zero);
    
    expect(progressLogs.last, equals(0.0));
    print('✅ 切换文件时进度已强制回滚到 0.0');

    // --- 场景 3: 边界情况 - Duration 尚未到达时的 Position 信号 ---
    mockPlayer.emitPosition(const Duration(seconds: 1));
    await Future.delayed(Duration.zero);
    // 此时 _currentDuration 为 0，逻辑应保护不发送无效进度
    expect(progressLogs.last, equals(0.0)); 
    print('✅ 零时长保护正常：未发送无效进度');

    await sub.cancel();
    service.dispose();
  });
}
