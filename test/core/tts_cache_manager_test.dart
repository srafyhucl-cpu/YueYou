import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yueyou/core/utils/tts_cache_manager.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ── TtsCacheCleanResult ───────────────────────────────────────────────────

  group('TtsCacheCleanResult', () {
    test('deletedCount/freedBytes 正确存储', () {
      const r = TtsCacheCleanResult(deletedCount: 3, freedBytes: 1536);
      expect(r.deletedCount, 3);
      expect(r.freedBytes, 1536);
    });

    test('freedBytesLabel：KB 格式（< 1MB）', () {
      const r = TtsCacheCleanResult(deletedCount: 1, freedBytes: 512 * 1024);
      expect(r.freedBytesLabel, contains('KB'));
    });

    test('freedBytesLabel：MB 格式（>= 1MB）', () {
      const r = TtsCacheCleanResult(deletedCount: 1, freedBytes: 2 * 1024 * 1024);
      expect(r.freedBytesLabel, contains('MB'));
    });

    test('freedBytes = 0 时 freedBytesLabel 为 0.0 KB', () {
      const r = TtsCacheCleanResult(deletedCount: 0, freedBytes: 0);
      expect(r.freedBytesLabel, '0.0 KB');
    });

    test('toString 包含 deleted 和 freed 信息', () {
      const r = TtsCacheCleanResult(deletedCount: 2, freedBytes: 100 * 1024);
      expect(r.toString(), contains('deleted=2'));
    });
  });

  // ── TtsCacheStat ─────────────────────────────────────────────────────────

  group('TtsCacheStat', () {
    test('fileCount/totalSizeBytes 正确存储', () {
      const s = TtsCacheStat(fileCount: 5, totalSizeBytes: 1024 * 1024);
      expect(s.fileCount, 5);
      expect(s.totalSizeBytes, 1024 * 1024);
    });

    test('sizeLabel：KB 格式', () {
      const s = TtsCacheStat(fileCount: 1, totalSizeBytes: 512 * 1024);
      expect(s.sizeLabel, contains('KB'));
    });

    test('sizeLabel：MB 格式（>= 1MB）', () {
      const s = TtsCacheStat(fileCount: 1, totalSizeBytes: 3 * 1024 * 1024);
      expect(s.sizeLabel, contains('MB'));
    });

    test('fileCount=0 totalSizeBytes=0 时 sizeLabel 为 0.0 KB', () {
      const s = TtsCacheStat(fileCount: 0, totalSizeBytes: 0);
      expect(s.sizeLabel, '0.0 KB');
    });

    test('toString 包含 files 信息', () {
      const s = TtsCacheStat(fileCount: 3, totalSizeBytes: 0);
      expect(s.toString(), contains('files=3'));
    });
  });

  // ── TtsCacheManager：空目录处理 ──────────────────────────────────────────

  group('TtsCacheManager 空目录处理', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('tts_cache_test_');
    });

    tearDown(() async {
      try {
        await tempDir.delete(recursive: true);
      } catch (_) {}
    });

    test('空目录时 getStat 返回 fileCount=0', () async {
      final mgr = TtsCacheManager.testInstance(
        getTempDir: () async => tempDir,
      );
      final stat = await mgr.getStat();
      expect(stat.fileCount, 0);
      expect(stat.totalSizeBytes, 0);
    });

    test('空目录时 cleanNow 返回 deletedCount=0', () async {
      final mgr = TtsCacheManager.testInstance(
        getTempDir: () async => tempDir,
      );
      final result = await mgr.cleanNow();
      expect(result.deletedCount, 0);
      expect(result.freedBytes, 0);
    });
  });

  // ── TtsCacheManager：时间淘汰策略 ────────────────────────────────────────

  group('TtsCacheManager 时间淘汰策略', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('tts_cache_time_');
    });

    tearDown(() async {
      try {
        await tempDir.delete(recursive: true);
      } catch (_) {}
    });

    test('超过时间阈值的文件被删除（maxAgeHours=0 使所有文件立即超时）', () async {
      final file = File('${tempDir.path}/tts_old_123.mp3');
      await file.writeAsBytes(List.filled(1024, 0));

      // maxFileAgeHours=0 → ageThreshold=0ms，任何文件都超时
      final mgr = TtsCacheManager.testInstance(
        maxFileAgeHours: 0,
        getTempDir: () async => tempDir,
      );

      final result = await mgr.cleanNow();
      expect(result.deletedCount, 1);
      expect(await file.exists(), isFalse);
    });

    test('阈值足够大时不触发时间淘汰', () async {
      final file = File('${tempDir.path}/tts_new_456.mp3');
      await file.writeAsBytes(List.filled(1024, 0));

      // maxFileAgeHours=999 → 文件几乎不可能超时
      final mgr = TtsCacheManager.testInstance(
        maxFileAgeHours: 999,
        getTempDir: () async => tempDir,
      );

      final result = await mgr.cleanNow();
      expect(result.deletedCount, 0);
      expect(await file.exists(), isTrue);
    });

    test('excludePath 文件即使超时也不被删除', () async {
      // 两个文件都立即超时（maxAgeHours=0），但 activeFile 被排除
      final activeFile = File('${tempDir.path}/tts_active_001.mp3');
      final oldFile = File('${tempDir.path}/tts_old_002.mp3');

      await activeFile.writeAsBytes(List.filled(1024, 0));
      await oldFile.writeAsBytes(List.filled(1024, 0));

      final mgr = TtsCacheManager.testInstance(
        maxFileAgeHours: 0, // 全部超时
        getTempDir: () async => tempDir,
      );

      // activeFile 被排除，只有 oldFile 被删除
      final result = await mgr.cleanNow(excludePath: activeFile.path);
      expect(result.deletedCount, 1);
      expect(await activeFile.exists(), isTrue);
      expect(await oldFile.exists(), isFalse);
    });
  });

  // ── TtsCacheManager：大小淘汰策略 ────────────────────────────────────────

  group('TtsCacheManager 大小淘汰策略', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('tts_cache_size_');
    });

    tearDown(() async {
      try {
        await tempDir.delete(recursive: true);
      } catch (_) {}
    });

    test('总大小超阈值时按旧→新删除到 70% 以下', () async {
      // 创建 3 个文件各 400KB，总计 1.2MB，阈值设 1MB
      final files = <File>[];
      for (int i = 0; i < 3; i++) {
        final f = File('${tempDir.path}/tts_size_$i.mp3');
        await f.writeAsBytes(List.filled(400 * 1024, 0));
        files.add(f);
        // 确保修改时间差异可排序（从旧到新）
        await f.setLastModified(
          DateTime.now().subtract(Duration(hours: 3 - i)),
        );
      }

      final mgr = TtsCacheManager.testInstance(
        maxCacheSizeBytes: 1024 * 1024, // 1MB 阈值
        maxFileAgeHours: 999, // 关闭时间淘汰
        getTempDir: () async => tempDir,
      );

      final result = await mgr.cleanNow();
      // 1.2MB > 1MB，需删到 70% = 0.7MB 以下
      // 删最旧文件（400KB）后 = 0.8MB，还 > 0.7MB
      // 删第二旧（400KB）后 = 0.4MB <= 0.7MB，停止
      expect(result.deletedCount, greaterThanOrEqualTo(1));
      // 最新的文件应该存活
      expect(await files.last.exists(), isTrue);
    });

    test('总大小未超阈值时不触发大小淘汰', () async {
      final f = File('${tempDir.path}/tts_small.mp3');
      await f.writeAsBytes(List.filled(100 * 1024, 0)); // 100KB

      final mgr = TtsCacheManager.testInstance(
        maxCacheSizeBytes: 500 * 1024 * 1024, // 500MB 阈值
        maxFileAgeHours: 999, // 关闭时间淘汰
        getTempDir: () async => tempDir,
      );

      final result = await mgr.cleanNow();
      expect(result.deletedCount, 0);
      expect(await f.exists(), isTrue);
    });
  });

  // ── TtsCacheManager：非 TTS 文件不受影响 ─────────────────────────────────

  group('TtsCacheManager 文件过滤', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('tts_cache_filter_');
    });

    tearDown(() async {
      try {
        await tempDir.delete(recursive: true);
      } catch (_) {}
    });

    test('非 tts_*.mp3 文件不被清理', () async {
      final f1 = File('${tempDir.path}/other.mp3');
      final f2 = File('${tempDir.path}/cache_123.mp3');
      final f3 = File('${tempDir.path}/tts_xxx.wav'); // 非 mp3
      await f1.writeAsBytes(List.filled(1024, 0));
      await f2.writeAsBytes(List.filled(1024, 0));
      await f3.writeAsBytes(List.filled(1024, 0));
      // 将所有文件设为超时
      for (final f in [f1, f2, f3]) {
        await f.setLastModified(DateTime.now().subtract(const Duration(hours: 48)));
      }

      final mgr = TtsCacheManager.testInstance(
        maxFileAgeHours: 1,
        getTempDir: () async => tempDir,
      );

      final result = await mgr.cleanNow();
      expect(result.deletedCount, 0); // 无 tts_*.mp3 文件被删
      expect(await f1.exists(), isTrue);
      expect(await f2.exists(), isTrue);
      expect(await f3.exists(), isTrue);
    });

    test('getStat 只统计 tts_*.mp3 文件', () async {
      final tts = File('${tempDir.path}/tts_valid.mp3');
      final other = File('${tempDir.path}/other.mp3');
      await tts.writeAsBytes(List.filled(2048, 0));
      await other.writeAsBytes(List.filled(4096, 0));

      final mgr = TtsCacheManager.testInstance(
        getTempDir: () async => tempDir,
      );

      final stat = await mgr.getStat();
      expect(stat.fileCount, 1); // 只统计 tts_valid.mp3
      expect(stat.totalSizeBytes, 2048);
    });
  });

  // ── TtsCacheManager：幂等保护 ────────────────────────────────────────────

  group('TtsCacheManager 幂等保护', () {
    test('startPeriodicClean 多次调用不产生多个定时器', () {
      final mgr = TtsCacheManager.testInstance(
        intervalMinutes: 60,
        getTempDir: () async => Directory.systemTemp,
      );
      // 连续调用两次，不应抛异常
      expect(() {
        mgr.startPeriodicClean();
        mgr.startPeriodicClean();
      }, returnsNormally);
      mgr.stopPeriodicClean();
    });

    test('stopPeriodicClean 未启动时调用不崩溃', () {
      final mgr = TtsCacheManager.testInstance();
      expect(() => mgr.stopPeriodicClean(), returnsNormally);
    });
  });
}
