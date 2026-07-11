import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';

import 'package:yueyou/core/constants/cyber_error_messages.dart';
import 'package:yueyou/core/utils/cyber_logger.dart';
import 'package:yueyou/features/audio/domain/tts_engine_interfaces.dart';

/// TTS 底层播放控制器。
///
/// 只负责本地音频文件播放、物理进度监听、暂停/恢复/停止和播放完成信号；
/// TTS 下载、会话状态和 Reader 进度仍由上层编排。
class TtsPlaybackController {
  TtsPlaybackController({
    required TtsAudioPlayer audioPlayer,
    required TtsFallbackEngine fallbackEngine,
    required bool Function() isDisposed,
    required void Function(dynamic error) onError,
    required void Function(double progress) progressEmitter,
  })  : _audioPlayer = audioPlayer,
        _fallbackEngine = fallbackEngine,
        _isDisposed = isDisposed,
        _onError = onError,
        _progressEmitter = progressEmitter {
    _positionSub = _audioPlayer.onPositionChanged.listen((pos) {
      if (_currentDuration.inMilliseconds > 0) {
        final progress = pos.inMilliseconds / _currentDuration.inMilliseconds;
        _progressEmitter(progress.clamp(0.0, 1.0));
      }
    });
    _durationSub = _audioPlayer.onDurationChanged.listen((dur) {
      _currentDuration = dur;
    });
  }

  final TtsAudioPlayer _audioPlayer;
  final TtsFallbackEngine _fallbackEngine;
  final bool Function() _isDisposed;
  final void Function(dynamic error) _onError;
  final void Function(double progress) _progressEmitter;

  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<Duration>? _durationSub;
  Completer<void>? _playCompleter;
  Duration _currentDuration = Duration.zero;

  Future<void> playFile(String path, {void Function()? onComplete}) async {
    try {
      _currentDuration = Duration.zero;
      _progressEmitter(0.0);

      await _audioPlayer.stop();
      final file = File(path);
      if (!await file.exists()) {
        onComplete?.call();
        return;
      }
      final fileSize = await file.length();
      if (fileSize < 1024) {
        CyberLogger.captureWarning(
          StateError('TTS 音频文件太小'),
          tag: 'tts',
          extra: {
            'context': '文件太小，跳过播放',
            'sizeBytes': '$fileSize',
            'path': path,
          },
        );
        onComplete?.call();
        return;
      }
      await _audioPlayer.setSource(DeviceFileSource(path)).timeout(
            const Duration(seconds: 5),
            onTimeout: () => throw TimeoutException('setSource 超时'),
          );
      if (_isDisposed()) return;
      _playCompleter = Completer<void>();
      final sub = _audioPlayer.onPlayerComplete.listen((_) {
        if (_playCompleter?.isCompleted == false) _playCompleter?.complete();
      });
      try {
        await _audioPlayer.resume();
        await _playCompleter!.future.timeout(
          const Duration(seconds: 30),
          onTimeout: () {
            unawaited(_audioPlayer.stop());
          },
        );
        onComplete?.call();
      } finally {
        await sub.cancel();
        _playCompleter = null;
      }
    } on TimeoutException catch (e, st) {
      CyberLogger.captureWarning(
        e,
        stack: st,
        tag: 'tts',
        extra: {'context': 'playFile 超时，播放熔断'},
      );
      await _audioPlayer.stop();
      _onError(CyberErrorMessages.ttsAudioLoadTimeout);
      onComplete?.call();
    } catch (e, st) {
      CyberLogger.captureWarning(
        e is Exception ? e : Exception('$e'),
        stack: st,
        tag: 'tts',
        extra: {'context': 'playFile 异常'},
      );
      try {
        await _audioPlayer.stop();
      } catch (_) {}
      onComplete?.call();
    }
  }

  Future<void> resumeAudio() async => _audioPlayer.resume();

  Future<void> pauseAudio() async {
    await Future.wait([
      _audioPlayer.pause(),
      _fallbackEngine.stop(),
    ]);
  }

  Future<void> stopAudio() async {
    if (_playCompleter?.isCompleted == false) {
      _playCompleter?.complete();
    }
    await Future.wait([
      _audioPlayer.stop(),
      _fallbackEngine.stop(),
    ]);
  }

  void dispose() {
    if (_playCompleter?.isCompleted == false) {
      _playCompleter?.complete();
    }
    unawaited(_positionSub?.cancel());
    unawaited(_durationSub?.cancel());
  }
}
