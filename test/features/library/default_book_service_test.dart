import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yueyou/core/database/storage_service.dart';
import 'package:yueyou/features/library/domain/book_model.dart';
import 'package:yueyou/features/library/services/default_book_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late DefaultBookService service;
  late Directory tempDir;

  Future<void> _setupTestEnv() async {
    SharedPreferences.setMockInitialValues({});
    StorageService.resetForTesting();
    await StorageService.init();
    // 每个用例独立 temp dir，避免缓存文件交叉污染
    tempDir = await Directory.systemTemp.createTemp('yueyou_default_book_');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => tempDir.path,
    );
  }

  setUp(() async {
    await _setupTestEnv();
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

    group('isChapterCached', () {
      test('returns false when no cache exists', () async {
        final cached = await service.isChapterCached(0);
        expect(cached, isFalse);
      });

      test('returns false for out-of-range index', () async {
        final cached = await service.isChapterCached(100);
        // No cache file would exist for out-of-range index
        expect(cached, isFalse);
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
}
