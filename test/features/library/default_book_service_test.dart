import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:yueyou/core/database/storage_service.dart';
import 'package:yueyou/features/library/domain/book_model.dart';
import 'package:yueyou/features/library/services/default_book_service.dart';

import '../../utils/test_utils.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late DefaultBookService service;
  late Directory tempDir;

  setUp(() async {
    // 复用工具方法：基础初始化 + StorageService 重置 + 独立 temp dir + path_provider 重写
    tempDir = await initializeTestEnvironmentWithIsolatedTempDir(
        'yueyou_default_book_');
    service = DefaultBookService();
  });

  tearDown(() async {
    try {
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  group('DefaultBookService', () {
    // ── Catalog tests ────────────────────────────────────────────────

    group('getCatalog', () {
      test('returns built-in fallback when network is unavailable', () async {
        final catalog = await service.getCatalog();

        expect(catalog, isNotEmpty);
        expect(catalog, isA<List<ChapterModel>>());
        // Built-in fallback should have 100 chapters
        expect(catalog.length, 100);
      });

      test('built-in fallback titles are non-empty', () async {
        final catalog = await service.getCatalog();

        for (final chapter in catalog) {
          expect(chapter.title, isNotEmpty);
        }
      });
    });

    // ── Chapter fetch tests ──────────────────────────────────────────

    group('fetchChapter', () {
      test('returns null for negative index', () async {
        final result = await service.fetchChapter(-1);
        expect(result, isNull);
      });

      test('returns null for out-of-range index', () async {
        final result = await service.fetchChapter(100);
        expect(result, isNull);
      });

      test('returns null for index at maximum boundary', () async {
        // 100 chapters means valid indices are 0-99
        final result = await service.fetchChapter(99);
        // Network will fail in test, so null is expected
        expect(result, isNull);
      });

      test('concurrent calls deduplicate — both await same future', () async {
        // Two simultaneous calls to the same chapter should share the in-flight
        // completer, preventing duplicate network requests.
        final future1 = service.fetchChapter(0);
        final future2 = service.fetchChapter(0);

        final results = await Future.wait([future1, future2]);
        expect(results[0], results[1]);
      });
    });

    // ── Cache check tests ────────────────────────────────────────────

    group('hasChapterOnDisk / hasChapterInMemory', () {
      test('hasChapterOnDisk returns false when no cache exists', () async {
        expect(await service.hasChapterOnDisk(0), isFalse);
      });

      test('hasChapterOnDisk returns false for out-of-range index', () async {
        // No cache file would exist for out-of-range index
        expect(await service.hasChapterOnDisk(100), isFalse);
      });

      test('hasChapterInMemory returns false on fresh service', () {
        expect(service.hasChapterInMemory(0), isFalse);
      });
    });

    // ── Prefetch tests ───────────────────────────────────────────────

    group('prefetchNextChapter', () {
      test('does not throw at boundary chapter 99', () {
        // Should not crash or throw
        expect(() => service.prefetchNextChapter(99), returnsNormally);
      });

      test('does not throw for negative index', () {
        expect(() => service.prefetchNextChapter(-1), returnsNormally);
      });

      test('does not throw for valid chapter 0', () {
        expect(() => service.prefetchNextChapter(0), returnsNormally);
      });
    });

    // ── Concurrent dedup isolates per chapter ───────────────────────

    test('different chapters create separate in-flight entries', () async {
      // Two different chapters should NOT share the same completer.
      final future0 = service.fetchChapter(0);
      final future5 = service.fetchChapter(5);

      final results = await Future.wait([future0, future5]);
      // Both fail due to no network in test environment
      expect(results[0], isNull);
      expect(results[1], isNull);
    });
  });

  // ── 网络路径覆盖：通过 MockClient 注入受控响应 ────────────────────────────
  // 覆盖 lib/features/library/services/default_book_service.dart：
  //   * getCatalog 网络成功 → JSON 解析 → 缓存写入（line 49-74）
  //   * getCatalog 缓存命中早返（line 44-46）
  //   * fetchChapter 缓存命中早返（line 109-110）
  //   * _downloadChapter POST 200 → success → CDN GET 200 → utf8 解码（line 195-245）
  //   * _downloadChapter POST 非 200 → captureWarning + null（line 205-209）
  //   * _downloadChapter POST 200 但 status != success（line 211-222）
  //   * _downloadChapter cdnUrl 为空（line 224-225）
  //   * _downloadChapter CDN GET 非 200（line 232-241）
  //   * prefetchNextChapter 越界早返（line 162）
  group('DefaultBookService - 网络路径（MockClient 注入）', () {
    test('getCatalog 缓存命中时不发任何网络请求', () async {
      int requestCount = 0;
      final mock = MockClient((req) async {
        requestCount++;
        return http.Response('should not be called', 500);
      });
      final svc = DefaultBookService(httpClient: mock);

      // 写入缓存
      await StorageService.saveBookCatalog(
        svc.bookKey,
        [
          ChapterModel(title: '缓存章 1', lineIndex: 0).toJson(),
          ChapterModel(title: '缓存章 2', lineIndex: 0).toJson(),
        ],
      );

      final catalog = await svc.getCatalog();
      expect(catalog.length, 2);
      expect(catalog.first.title, '缓存章 1');
      expect(requestCount, 0, reason: '本地缓存命中时禁止发起网络请求');
    });

    test('getCatalog 网络成功 status=success 必须返回服务端章节并写入缓存', () async {
      int mockCalls = 0;
      final mock = MockClient((req) async {
        mockCalls++;
        return http.Response(
          // 关键：必须用 utf8 字节而非 Latin-1 默认编码，否则中文章节标题会被
          // http.Response.body getter 按 Latin-1 解析回来 jsonDecode 直接挂。
          jsonEncode({
            'status': 'success',
            'chapters': [
              {'title': 'NetA'},
              {'title': 'NetB'},
              {'title': 'NetC'},
            ],
          }),
          200,
          headers: {'Content-Type': 'application/json; charset=utf-8'},
        );
      });
      final svc = DefaultBookService(httpClient: mock);

      final catalog = await svc.getCatalog();
      expect(mockCalls, 1, reason: 'MockClient 必须被 _httpClient.get 真实调用');
      expect(catalog.length, 3);
      expect(catalog.map((c) => c.title),
          equals(<String>['NetA', 'NetB', 'NetC']));

      // 等异步缓存写入完成（fire-and-forget）
      await Future<void>.delayed(const Duration(milliseconds: 50));
      final cached = await StorageService.loadBookCatalog(svc.bookKey);
      expect(cached, isNotNull, reason: '网络成功后必须把章节列表异步写入本地缓存');
    });

    test('getCatalog 网络异常时降级返回内置常量（100 章）', () async {
      final mock = MockClient((req) async {
        throw http.ClientException('connection refused');
      });
      final svc = DefaultBookService(httpClient: mock);

      final catalog = await svc.getCatalog();
      // 内置常量降级：BookConstants.xiyoujiChapterTitles 共 100 章
      expect(catalog.length, 100, reason: '网络异常 → 降级到内置 100 章 BookConstants');
    });

    test('getCatalog 网络成功但 chapters 字段缺失时必须降级返回内置 100 章', () async {
      final mock = MockClient((req) async {
        return http.Response(
          jsonEncode({'status': 'success'}), // 故意不带 chapters 字段
          200,
          headers: {'Content-Type': 'application/json; charset=utf-8'},
        );
      });
      final svc = DefaultBookService(httpClient: mock);

      final catalog = await svc.getCatalog();
      expect(catalog.length, 100,
          reason: 'P3 修复：chapters 字段缺失必须走 _fallbackBuiltinCatalog 兜底');
    });

    test('getCatalog 网络成功但 chapters 字段为 null 时必须降级', () async {
      final mock = MockClient((req) async {
        return http.Response(
          jsonEncode({'status': 'success', 'chapters': null}),
          200,
          headers: {'Content-Type': 'application/json; charset=utf-8'},
        );
      });
      final svc = DefaultBookService(httpClient: mock);

      final catalog = await svc.getCatalog();
      expect(catalog.length, 100, reason: 'P3 修复：chapters=null 必须走降级路径而非崩溃');
    });

    test('fetchChapter 缓存命中时不发任何网络请求', () async {
      int requestCount = 0;
      final mock = MockClient((req) async {
        requestCount++;
        return http.Response('should not be called', 500);
      });
      final svc = DefaultBookService(httpClient: mock);
      await StorageService.saveChapterCache(svc.bookKey, 0, '缓存章节正文');

      final text = await svc.fetchChapter(0);
      expect(text, '缓存章节正文');
      expect(requestCount, 0, reason: '本地缓存命中时禁止发起 POST 请求');
    });

    test('fetchChapter 完整 happy path：POST 200 + GET 200 → utf8 解码', () async {
      final mock = MockClient((req) async {
        if (req.method == 'POST') {
          return http.Response(
            jsonEncode({
              'status': 'success',
              'url': 'https://cdn.test/chapter_0.txt',
            }),
            200,
            headers: {'Content-Type': 'application/json; charset=utf-8'},
          );
        }
        // GET CDN：返回 UTF-8 字节
        return http.Response.bytes(
          utf8.encode('章节正文：唐僧师徒西行'),
          200,
        );
      });
      final svc = DefaultBookService(httpClient: mock);

      final text = await svc.fetchChapter(0);
      expect(text, '章节正文：唐僧师徒西行',
          reason: 'happy path 必须经 POST → GET 链路并 utf8 解码返回章节正文');

      // 验证缓存已写入（fire-and-forget）
      await Future<void>.delayed(const Duration(milliseconds: 50));
      final cached = await StorageService.loadChapterCache(svc.bookKey, 0);
      expect(cached, '章节正文：唐僧师徒西行');
    });

    test('fetchChapter POST 非 200 时返回 null', () async {
      final mock = MockClient((req) async {
        return http.Response('server error', 500);
      });
      final svc = DefaultBookService(httpClient: mock);

      final text = await svc.fetchChapter(0);
      expect(text, isNull, reason: 'POST 非 200 必须返回 null（line 205-209）');
    });

    test('fetchChapter POST 200 但 status != success 时返回 null', () async {
      final mock = MockClient((req) async {
        return http.Response(
          jsonEncode({'status': 'error', 'message': 'chapter not found'}),
          200,
          headers: {'Content-Type': 'application/json; charset=utf-8'},
        );
      });
      final svc = DefaultBookService(httpClient: mock);

      final text = await svc.fetchChapter(0);
      expect(text, isNull,
          reason: 'POST 200 但 status=error 必须返回 null（line 211-222）');
    });

    test('fetchChapter POST 200 但 url 为空时返回 null', () async {
      final mock = MockClient((req) async {
        return http.Response(
          jsonEncode({'status': 'success', 'url': ''}),
          200,
          headers: {'Content-Type': 'application/json; charset=utf-8'},
        );
      });
      final svc = DefaultBookService(httpClient: mock);

      final text = await svc.fetchChapter(0);
      expect(text, isNull, reason: 'cdnUrl 为空字符串必须返回 null（line 224-225）');
    });

    test('fetchChapter POST 成功但 CDN GET 非 200 时返回 null', () async {
      final mock = MockClient((req) async {
        if (req.method == 'POST') {
          return http.Response(
            jsonEncode({
              'status': 'success',
              'url': 'https://cdn.test/missing.txt',
            }),
            200,
            headers: {'Content-Type': 'application/json; charset=utf-8'},
          );
        }
        return http.Response('not found', 404);
      });
      final svc = DefaultBookService(httpClient: mock);

      final text = await svc.fetchChapter(0);
      expect(text, isNull,
          reason: 'POST 成功但 CDN GET 404 必须返回 null（line 232-241）');
    });

    test('prefetchNextChapter 在 currentIndex+1 越界时早返不抛', () {
      // currentIndex+1 == 100（>= defaultTotalChapters）→ 早返
      final svc = DefaultBookService(httpClient: MockClient((_) async {
        throw StateError('should not be reached');
      }));
      expect(() => svc.prefetchNextChapter(99), returnsNormally,
          reason: 'currentIndex+1 越界必须 line 162 早返不抛');
    });

    test(
        'prefetchNextChapter 在合法 currentIndex 时触发 fetchChapter（fire-and-forget）',
        () async {
      int postCalls = 0;
      final mock = MockClient((req) async {
        if (req.method == 'POST') postCalls++;
        return http.Response('error', 500);
      });
      final svc = DefaultBookService(httpClient: mock);

      svc.prefetchNextChapter(0); // 触发 fetchChapter(1)
      await Future<void>.delayed(const Duration(milliseconds: 100));

      expect(postCalls, greaterThanOrEqualTo(1),
          reason: 'prefetchNextChapter 必须 fire-and-forget 调 fetchChapter');
    });
  });

  // ── P3 回归：进程内内存缓存（in-process memory cache fallback）────────────
  // 覆盖 lib/features/library/services/default_book_service.dart：
  //   * getCatalog 网络成功后填充 _catalogMemCache（line 108-109）
  //   * getCatalog 第二次调用走 _catalogMemCache 早返（line 62-65）
  //   * fetchChapter 网络成功后填充 _chapterMemCache（line 184-185）
  //   * fetchChapter 第二次调用走 _chapterMemCache 早返（line 163-165）
  //   * hasChapterInMemory / hasChapterOnDisk 双层语义边界
  //   * clearMemoryCacheForTesting 清空两层缓存
  group('DefaultBookService - P3 进程内内存缓存', () {
    test('getCatalog 网络成功后第二次调用必须命中 _catalogMemCache 不再发请求', () async {
      int requestCount = 0;
      final mock = MockClient((req) async {
        requestCount++;
        return http.Response(
          jsonEncode({
            'status': 'success',
            'chapters': [
              {'title': 'MemA'},
              {'title': 'MemB'},
            ],
          }),
          200,
          headers: {'Content-Type': 'application/json; charset=utf-8'},
        );
      });
      final svc = DefaultBookService(httpClient: mock);

      // 第一次：走网络
      final first = await svc.getCatalog();
      expect(requestCount, 1);
      expect(first.length, 2);

      // 第二次：必须命中内存缓存，requestCount 不增加
      final second = await svc.getCatalog();
      expect(requestCount, 1, reason: 'P3 内存缓存命中后禁止再发网络请求');
      expect(second.map((c) => c.title), equals(<String>['MemA', 'MemB']));
    });

    test('getCatalog 内存缓存优先级高于磁盘缓存（同会话不读盘）', () async {
      int requestCount = 0;
      final mock = MockClient((req) async {
        requestCount++;
        return http.Response(
          jsonEncode({
            'status': 'success',
            'chapters': [
              {'title': 'NetOnly'},
            ],
          }),
          200,
          headers: {'Content-Type': 'application/json; charset=utf-8'},
        );
      });
      final svc = DefaultBookService(httpClient: mock);

      await svc.getCatalog();
      // 即使把磁盘缓存改写成 ['DiskOverride']，下次 getCatalog 仍应返回内存版本
      await StorageService.saveBookCatalog(
        svc.bookKey,
        [ChapterModel(title: 'DiskOverride', lineIndex: 0).toJson()],
      );
      final second = await svc.getCatalog();
      expect(second.first.title, 'NetOnly',
          reason: 'P3 优先级：内存 > 磁盘，确保即便磁盘有更新也以内存为准');
    });

    test('getCatalog 降级到内置常量时不写入 _catalogMemCache（保留下次重试机会）', () async {
      int callCount = 0;
      final mock = MockClient((req) async {
        callCount++;
        if (callCount == 1) {
          throw http.ClientException('first call fails');
        }
        // 第二次成功
        return http.Response(
          jsonEncode({
            'status': 'success',
            'chapters': [
              {'title': 'RetrySuccess'},
            ],
          }),
          200,
          headers: {'Content-Type': 'application/json; charset=utf-8'},
        );
      });
      final svc = DefaultBookService(httpClient: mock);

      // 第一次：网络异常 → 降级 100 章内置常量，但内存缓存保持空
      final first = await svc.getCatalog();
      expect(first.length, 100, reason: '第一次降级到内置 100 章');

      // 第二次：内存缓存为空 → 走网络 → 成功
      final second = await svc.getCatalog();
      expect(second.length, 1, reason: 'P3 关键：降级时不写内存缓存，下次必须仍能重试网络');
      expect(second.first.title, 'RetrySuccess');
    });

    test('fetchChapter 网络成功后第二次调用必须命中 _chapterMemCache 不再发请求', () async {
      int postCalls = 0;
      final mock = MockClient((req) async {
        if (req.method == 'POST') {
          postCalls++;
          return http.Response(
            jsonEncode({
              'status': 'success',
              'url': 'https://cdn.test/ch_0.txt',
            }),
            200,
            headers: {'Content-Type': 'application/json; charset=utf-8'},
          );
        }
        return http.Response.bytes(utf8.encode('章节正文 mem'), 200);
      });
      final svc = DefaultBookService(httpClient: mock);

      // 第一次：走完整 POST → GET 链路
      final first = await svc.fetchChapter(0);
      expect(first, '章节正文 mem');
      expect(postCalls, 1);

      // 第二次：命中内存缓存，不再发任何 POST
      final second = await svc.fetchChapter(0);
      expect(second, '章节正文 mem');
      expect(postCalls, 1, reason: 'P3 内存缓存命中后禁止重复 POST');
    });

    test('getCatalog 并发调用必须共享 in-flight Completer，仅触发一次网络拉取', () async {
      // 模拟慢网络：100ms 延迟，让两次并发调用都来得及汇合到 in-flight。
      int requestCount = 0;
      final mock = MockClient((req) async {
        requestCount++;
        await Future<void>.delayed(const Duration(milliseconds: 100));
        return http.Response(
          jsonEncode({
            'status': 'success',
            'chapters': [
              {'title': 'Concurrent'},
            ],
          }),
          200,
          headers: {'Content-Type': 'application/json; charset=utf-8'},
        );
      });
      final svc = DefaultBookService(httpClient: mock);

      // 同时发起两次 getCatalog（不 await 第一次）
      final f1 = svc.getCatalog();
      final f2 = svc.getCatalog();
      final results = await Future.wait([f1, f2]);

      expect(requestCount, 1, reason: 'in-flight 去重：并发调用必须共享同一次网络请求');
      expect(results[0].first.title, 'Concurrent');
      expect(results[1].first.title, 'Concurrent');
      // 两个 future 解析到完全相同的 list 实例（来自内存缓存）
      expect(identical(results[0], results[1]), isTrue,
          reason: '两次并发调用应返回同一个 List 实例');
    });

    test('getCatalog in-flight 失败降级后第二次调用仍可触发网络重试', () async {
      // 第一次调用：模拟网络异常 → 降级 100 章。
      // 第二次调用（in-flight 已结束）：必须能重新发请求。
      int callCount = 0;
      final mock = MockClient((req) async {
        callCount++;
        await Future<void>.delayed(const Duration(milliseconds: 30));
        if (callCount == 1) {
          throw http.ClientException('first call fails');
        }
        return http.Response(
          jsonEncode({
            'status': 'success',
            'chapters': [
              {'title': 'RetryAfterInFlight'},
            ],
          }),
          200,
          headers: {'Content-Type': 'application/json; charset=utf-8'},
        );
      });
      final svc = DefaultBookService(httpClient: mock);

      final first = await svc.getCatalog();
      expect(first.length, 100, reason: '第一次降级到 100 章');
      expect(callCount, 1);

      // 第二次：in-flight 已清空，且降级路径未污染内存 → 必须重发请求
      final second = await svc.getCatalog();
      expect(second.first.title, 'RetryAfterInFlight');
      expect(callCount, 2, reason: 'in-flight 完成后必须释放，下次允许重新发请求');
    });

    test('hasChapterInMemory / hasChapterOnDisk 双层语义边界正确', () async {
      int postCalls = 0;
      final mock = MockClient((req) async {
        if (req.method == 'POST') {
          postCalls++;
          return http.Response(
            jsonEncode({
              'status': 'success',
              'url': 'https://cdn.test/ch_0.txt',
            }),
            200,
            headers: {'Content-Type': 'application/json; charset=utf-8'},
          );
        }
        return http.Response.bytes(utf8.encode('cached body'), 200);
      });
      final svc = DefaultBookService(httpClient: mock);

      // 初始两层都空
      expect(svc.hasChapterInMemory(0), isFalse, reason: '初始内存空');
      expect(await svc.hasChapterOnDisk(0), isFalse, reason: '初始磁盘空');

      // 拉一次让内存 + 磁盘都填充
      await svc.fetchChapter(0);
      expect(postCalls, 1);
      // 等待 fire-and-forget 写盘完成（saveChapterCache + pruneChapterCache 链）
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(svc.hasChapterInMemory(0), isTrue,
          reason: 'P3 双层 API：内存层应命中（同步无 IO）');
      expect(await svc.hasChapterOnDisk(0), isTrue,
          reason: 'P3 双层 API：磁盘层应命中（持久化保证）');

      // clearMemoryCacheForTesting 后内存清空，但磁盘仍在
      svc.clearMemoryCacheForTesting();
      expect(svc.hasChapterInMemory(0), isFalse,
          reason: 'P3 语义边界：clear 后内存层必须为 false');
      expect(await svc.hasChapterOnDisk(0), isTrue,
          reason: 'P3 语义边界：clear 不影响磁盘持久化');
    });

    test('clearMemoryCacheForTesting 必须同时清空 catalog + chapter 两级缓存', () async {
      // 设计思路：通过「改写磁盘数据」观察内存被清空。
      // - 第一次 seed 磁盘 V1 → getCatalog 命中磁盘 → 同时 seed 内存 V1。
      // - 把磁盘改写为 V2，但不触发 service。getCatalog 应仍命中内存 → V1。
      // - clearMemoryCacheForTesting 后内存空 → 下次必须重读磁盘 → V2。
      //   （回避 Windows 上 tempDir.delete 因后台 IO 文件锁失败的脆弱性）
      final mock = MockClient((req) async {
        throw http.ClientException('always offline');
      });
      final svc = DefaultBookService(httpClient: mock);

      await StorageService.saveBookCatalog(
        svc.bookKey,
        [ChapterModel(title: 'V1', lineIndex: 0).toJson()],
      );
      final first = await svc.getCatalog();
      expect(first.first.title, 'V1', reason: '磁盘命中后必须把数据 seed 到内存缓存');

      // 直接改写磁盘到 V2；service 内存仍持有 V1。
      await StorageService.saveBookCatalog(
        svc.bookKey,
        [ChapterModel(title: 'V2', lineIndex: 0).toJson()],
      );
      final memHit = await svc.getCatalog();
      expect(memHit.first.title, 'V1', reason: '内存优先于磁盘 → 即便磁盘已改 V2 仍命中内存 V1');

      // 清空内存 → 下次必须从磁盘 V2 重新读取
      svc.clearMemoryCacheForTesting();
      final afterClear = await svc.getCatalog();
      expect(afterClear.first.title, 'V2',
          reason: 'clearMemoryCacheForTesting 后内存清空，必须读到磁盘 V2 版本');
    });
  });
}
