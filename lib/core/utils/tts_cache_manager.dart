import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:yueyou/core/utils/cyber_logger.dart';

/// TTS 音频缓存管理器
///
/// ## 清理策略（双重判定，任一满足即清理对应文件）
/// - **大小阈值**：扫描目录总大小超过 [maxCacheSizeBytes]（默认 500MB）
///   时，按修改时间**从旧到新**删除，直到目录大小低于阈值的 70%
/// - **时间阈值**：单个文件修改时间距今超过 [maxFileAgeHours]（默认 24 小时）
///   时，无条件删除
///
/// ## 文件匹配规则
/// 仅清理 `getTemporaryDirectory()` 下名称满足 `tts_*.mp3` 模式的文件，
/// 不影响其他 App 缓存文件。
///
/// ## 执行方式
/// - **自动定时**：调用 [startPeriodicClean] 后每隔 [intervalMinutes]（默认 30 分钟）
///   在后台自动清理
/// - **手动触发**：调用 [cleanNow] 立即执行一次扫描与清理（可在设置界面提供按钮）
///
/// ## 使用示例
/// ```dart
/// // 启动（在 TtsEngineService.init() 中调用）
/// TtsCacheManager.instance.startPeriodicClean(
///   excludeActivePath: () => tts._lastGeneratedAudioPath,
/// );
///
/// // 手动触发（在设置页「清理缓存」按钮）
/// final result = await TtsCacheManager.instance.cleanNow();
/// debugPrint('清理完成：删除 ${result.deletedCount} 个文件，释放 ${result.freedBytes} 字节');
///
/// // App 退出时停止定时器
/// TtsCacheManager.instance.stopPeriodicClean();
/// ```
///
/// ## 架构约束
/// - 本类位于 `core/utils/`，不引入任何 Flutter UI 依赖（`flutter/material.dart`）。
/// - 所有 IO 操作异步执行，不阻塞主线程。
/// - [cleanNow] 是幂等的，多次调用不会产生竞争问题（通过 `_running` 标志守护）。
class TtsCacheManager {
  TtsCacheManager._({
    int maxCacheSizeBytes = 500 * 1024 * 1024, // 500MB
    int maxFileAgeHours = 24,
    int intervalMinutes = 30,
    Future<Directory> Function()? getTempDir,
  })  : _maxCacheSize = maxCacheSizeBytes,
        _maxFileAgeMs = maxFileAgeHours * 60 * 60 * 1000,
        _intervalMinutes = intervalMinutes,
        _getTempDir = getTempDir ?? getTemporaryDirectory;

  /// 单例
  static final TtsCacheManager instance = TtsCacheManager._();

  /// 测试专用工厂（注入自定义参数，不影响单例）
  @visibleForTesting
  static TtsCacheManager testInstance({
    int maxCacheSizeBytes = 500 * 1024 * 1024,
    int maxFileAgeHours = 24,
    int intervalMinutes = 30,
    Future<Directory> Function()? getTempDir,
  }) =>
      TtsCacheManager._(
        maxCacheSizeBytes: maxCacheSizeBytes,
        maxFileAgeHours: maxFileAgeHours,
        intervalMinutes: intervalMinutes,
        getTempDir: getTempDir,
      );

  final int _maxCacheSize;
  final int _maxFileAgeMs;
  final int _intervalMinutes;
  final Future<Directory> Function() _getTempDir;

  Timer? _timer;
  bool _running = false;
  String? Function()? _excludeActivePath;

  // ── 公开控制接口 ──────────────────────────────────────────────────────────

  /// 启动定期自动清理
  ///
  /// [excludeActivePath]：返回当前正在播放的文件路径，该文件将被跳过。
  /// 重复调用无害（先停止旧定时器再启动新的）。
  void startPeriodicClean({String? Function()? excludeActivePath}) {
    _excludeActivePath = excludeActivePath;
    stopPeriodicClean(); // 防止重复定时器
    _timer = Timer.periodic(Duration(minutes: _intervalMinutes), (_) {
      unawaited(_runClean());
    });
    CyberLogger.captureMessage(
      '[TtsCacheManager] 定期清理已启动 '
      '(每 $_intervalMinutes 分钟，阈值: ${_maxCacheSize ~/ 1024 ~/ 1024}MB / ${_maxFileAgeMs ~/ 3600000}h)',
    );
  }

  /// 停止定期自动清理
  void stopPeriodicClean() {
    _timer?.cancel();
    _timer = null;
  }

  /// 立即执行一次缓存清理（可由 UI 层手动触发）
  ///
  /// 若当前正在运行中，直接返回空结果（幂等保护）。
  Future<TtsCacheCleanResult> cleanNow({
    String? excludePath,
  }) async {
    final path = excludePath ?? _excludeActivePath?.call();
    return _runClean(excludePath: path);
  }

  /// 获取当前 TTS 缓存占用信息（不执行删除）
  Future<TtsCacheStat> getStat() async {
    try {
      final dir = await _getTempDir();
      final files = await _listTtsFiles(dir);
      final totalBytes = files.fold<int>(0, (sum, f) => sum + f.sizeBytes);
      return TtsCacheStat(
        fileCount: files.length,
        totalSizeBytes: totalBytes,
      );
    } catch (e, st) {
      CyberLogger.captureWarning(
        e,
        stack: st,
        tag: 'tts',
        extra: {'context': 'TtsCacheManager.getStat 异常'},
      );
      return const TtsCacheStat(fileCount: 0, totalSizeBytes: 0);
    }
  }

  // ── 内部清理逻辑 ──────────────────────────────────────────────────────────

  /// 执行清理（受 _running 保护，防止并发）
  Future<TtsCacheCleanResult> _runClean({String? excludePath}) async {
    if (_running) {
      return const TtsCacheCleanResult(deletedCount: 0, freedBytes: 0);
    }
    _running = true;
    try {
      final dir = await _getTempDir();
      final files = await _listTtsFiles(dir);
      if (files.isEmpty) {
        return const TtsCacheCleanResult(deletedCount: 0, freedBytes: 0);
      }

      final now = DateTime.now().millisecondsSinceEpoch;
      final toDelete = <_TtsFileInfo>[];

      // ─ 策略 1：时间淘汰（修改时间超过阈值）───────────────────────────────
      // 用 URI path segments 提取文件名，规避 Windows 路径分隔符不一致
      final excludeBasename = excludePath != null
          ? File(excludePath).uri.pathSegments.last.toLowerCase()
          : null;
      for (final f in files) {
        final fBasename = File(f.path).uri.pathSegments.last.toLowerCase();
        if (excludeBasename != null && fBasename == excludeBasename) continue;
        final ageMs = now - f.modifiedAtMs;
        if (ageMs >= _maxFileAgeMs) {
          toDelete.add(f);
        }
      }

      // ─ 策略 2：大小淘汰（总大小超阈值，按旧→新排序删到 70% 以下）──────────
      final toDeletePaths = toDelete.map((f) => f.path).toSet();
      final remaining =
          files.where((f) => !toDeletePaths.contains(f.path)).toList();
      int totalBytes = remaining.fold<int>(0, (sum, f) => sum + f.sizeBytes);
      final targetBytes = (_maxCacheSize * 0.7).round();

      if (totalBytes > _maxCacheSize) {
        CyberLogger.captureWarning(
          StateError('TTS 缓存超限'),
          tag: 'tts',
          extra: {
            'context': 'TtsCacheManager 缓存超限，开始大小淘汰',
            'currentMB': '${totalBytes ~/ 1024 ~/ 1024}',
            'maxMB': '${_maxCacheSize ~/ 1024 ~/ 1024}',
          },
        );
        // 按修改时间从旧到新排序
        remaining.sort((a, b) => a.modifiedAtMs.compareTo(b.modifiedAtMs));
        for (final f in remaining) {
          if (totalBytes <= targetBytes) break;
          if (excludeBasename != null &&
              File(f.path).uri.pathSegments.last.toLowerCase() ==
                  excludeBasename) {
            continue;
          }
          toDelete.add(f);
          totalBytes -= f.sizeBytes;
        }
      }

      if (toDelete.isEmpty) {
        return const TtsCacheCleanResult(deletedCount: 0, freedBytes: 0);
      }

      // ─ 执行删除 ──────────────────────────────────────────────────────────
      int deletedCount = 0;
      int freedBytes = 0;
      for (final f in toDelete) {
        try {
          final file = File(f.path);
          if (await file.exists()) {
            await file.delete();
            deletedCount++;
            freedBytes += f.sizeBytes;
          }
        } catch (e, st) {
          CyberLogger.captureWarning(
            e,
            stack: st,
            tag: 'tts',
            extra: {'context': 'TtsCacheManager 删除文件失败', 'path': f.path},
          );
        }
      }

      CyberLogger.captureMessage(
        '[TtsCacheManager] 清理完成：删除 $deletedCount 个文件，释放 ${freedBytes ~/ 1024} KB',
      );

      return TtsCacheCleanResult(
        deletedCount: deletedCount,
        freedBytes: freedBytes,
      );
    } catch (e, st) {
      CyberLogger.captureWarning(
        e,
        stack: st,
        tag: 'tts',
        extra: {'context': 'TtsCacheManager._runClean 异常'},
      );
      return const TtsCacheCleanResult(deletedCount: 0, freedBytes: 0);
    } finally {
      _running = false;
    }
  }

  /// 遍历临时目录，收集所有 tts_*.mp3 文件信息
  Future<List<_TtsFileInfo>> _listTtsFiles(Directory dir) async {
    final result = <_TtsFileInfo>[];
    try {
      if (!await dir.exists()) return result;
      final entities = dir.listSync();
      for (final entity in entities) {
        if (entity is File) {
          final name = entity.path.split(Platform.pathSeparator).last;
          if (name.startsWith('tts_') && name.endsWith('.mp3')) {
            try {
              final stat = await entity.stat();
              result.add(
                _TtsFileInfo(
                  path: entity.path,
                  sizeBytes: stat.size,
                  modifiedAtMs: stat.modified.millisecondsSinceEpoch,
                ),
              );
            } catch (_) {}
          }
        }
      }
    } catch (e, st) {
      CyberLogger.captureWarning(
        e,
        stack: st,
        tag: 'tts',
        extra: {'context': 'TtsCacheManager._listTtsFiles 异常'},
      );
    }
    return result;
  }
}

// ── 数据类 ────────────────────────────────────────────────────────────────────

/// 缓存清理结果
class TtsCacheCleanResult {
  /// 本次删除的文件数量
  final int deletedCount;

  /// 本次释放的字节数
  final int freedBytes;

  const TtsCacheCleanResult({
    required this.deletedCount,
    required this.freedBytes,
  });

  /// 释放空间的人类可读字符串（KB/MB 自适应）
  String get freedBytesLabel {
    if (freedBytes < 1024 * 1024) {
      return '${(freedBytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(freedBytes / 1024 / 1024).toStringAsFixed(1)} MB';
  }

  @override
  String toString() =>
      'TtsCacheCleanResult(deleted=$deletedCount, freed=$freedBytesLabel)';
}

/// 缓存占用统计（不执行清理）
class TtsCacheStat {
  /// 当前 tts_*.mp3 文件数量
  final int fileCount;

  /// 当前占用总字节数
  final int totalSizeBytes;

  const TtsCacheStat({
    required this.fileCount,
    required this.totalSizeBytes,
  });

  /// 人类可读的大小字符串
  String get sizeLabel {
    if (totalSizeBytes < 1024 * 1024) {
      return '${(totalSizeBytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(totalSizeBytes / 1024 / 1024).toStringAsFixed(1)} MB';
  }

  @override
  String toString() => 'TtsCacheStat(files=$fileCount, size=$sizeLabel)';
}

/// 内部文件信息（仅在本类内部使用）
class _TtsFileInfo {
  final String path;
  final int sizeBytes;
  final int modifiedAtMs;

  const _TtsFileInfo({
    required this.path,
    required this.sizeBytes,
    required this.modifiedAtMs,
  });
}
