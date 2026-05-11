// TTS 临时音频文件清理器。
//
// 从 `tts_engine_service.dart` 抽出（PR-C）。只暴露顶层函数
// [cleanupOrphanedTtsFiles]，零状态、零字段，便于单元测试直接调用。
//
// 设计要点：
// - 仅扫描应用临时目录中的 `tts_*.mp3` 文件；
// - 跳过 60 秒内被修改过的活跃文件（保护并行 isolate 的下载产物）；
// - 跳过调用方通过 [activePathGetter] 上报的当前播放文件；
// - 任何异常都通过 [CyberLogger.captureWarning] 上报，永不抛出。

import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'package:yueyou/core/utils/cyber_logger.dart';

/// 临时目录孤儿 TTS 文件清理器。
///
/// [activePathGetter] 返回当前会话正在使用的文件路径（可为 null）。
/// 该路径会被无条件跳过，避免误删活跃下载。
///
/// 同时，对所有被扫描到的文件，若 `mtime` 在最近 60 秒内，也会被跳过——
/// 这一窗口防御覆盖并行 isolate / 跨进程场景下的活跃写入。
Future<void> cleanupOrphanedTtsFiles({
  required String? Function() activePathGetter,
}) async {
  try {
    final tempDir = await getTemporaryDirectory();
    final dir = Directory(tempDir.path);
    if (!await dir.exists()) return;

    final activeWindow = DateTime.now().subtract(const Duration(seconds: 60));
    final entities = dir.listSync();
    int cleaned = 0;
    for (final entity in entities) {
      if (entity is! File) continue;
      final name = entity.path.split(Platform.pathSeparator).last;
      // 匹配 tts_*.mp3 模式
      if (!(name.startsWith('tts_') && name.endsWith('.mp3'))) continue;
      // 跳过当前 Session 正在使用的文件
      if (entity.path == activePathGetter()) continue;
      // 跳过近 60s 内被修改过的文件（活跃下载窗口）
      try {
        final mtime = entity.statSync().modified;
        if (mtime.isAfter(activeWindow)) continue;
      } catch (_) {
        // stat 失败时保守跳过，避免误删
        continue;
      }
      try {
        await entity.delete();
        cleaned++;
      } catch (_) {
        // 单个缓存文件删除失败不阻塞清理流程
      }
    }
    if (cleaned > 0) {
      CyberLogger.captureMessage('已回收 $cleaned 个残留 TTS 临时文件', tag: 'tts');
    }
  } catch (e, st) {
    CyberLogger.captureWarning(
      e,
      stack: st,
      tag: 'tts',
      extra: {'context': '清理残留 TTS 文件失败'},
    );
  }
}
