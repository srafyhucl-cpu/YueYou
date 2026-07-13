import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yueyou/core/database/storage_service.dart';
import 'package:yueyou/features/library/domain/book_model.dart';
import 'package:yueyou/features/library/providers/bookshelf_provider.dart';
import 'package:yueyou/features/library/providers/library_view_provider.dart';

import '../../utils/test_utils.dart';

void main() {
  test('搜索和排序只派生可见列表，不修改书架原始顺序', () async {
    const bookOne = BookModel(id: 1, title: '第一本.txt', total: 10);
    const bookTwo = BookModel(id: 2, title: '第二本.txt', total: 10);
    await initializeTestEnvironment();
    SharedPreferences.setMockInitialValues({
      'has_selected_book': true,
      'local_bookshelf': jsonEncode([
        bookOne.toJson(),
        bookTwo.toJson(),
      ]),
    });
    StorageService.resetForTesting();
    await StorageService.init();
    await StorageService.updateReadingRecord('1', 1, 10);
    await StorageService.updateReadingRecord('2', 8, 10);

    final shelf = BookshelfProvider()..loadFromStorage();
    final container = ProviderContainer(
      overrides: [bookshelfProvider.overrideWith((ref) => shelf)],
    );
    addTearDown(container.dispose);

    expect(
      container.read(libraryVisibleBooksProvider).map((book) => book.id),
      [1, 2],
    );

    container.read(libraryViewProvider.notifier).setQuery('第二');
    expect(
      container.read(libraryVisibleBooksProvider).map((book) => book.id),
      [2],
    );

    container.read(libraryViewProvider.notifier).clearQuery();
    container
        .read(libraryViewProvider.notifier)
        .setSortMode(LibrarySortMode.progress);
    expect(
      container.read(libraryVisibleBooksProvider).map((book) => book.id),
      [2, 1],
    );
    expect(shelf.shelf.map((book) => book.id), [1, 2]);
  });
}
