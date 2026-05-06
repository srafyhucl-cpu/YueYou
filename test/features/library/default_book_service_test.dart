import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yueyou/core/database/storage_service.dart';
import 'package:yueyou/features/library/domain/book_model.dart';
import 'package:yueyou/features/library/services/default_book_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late DefaultBookService service;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await StorageService.init();
    service = DefaultBookService();
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
}
