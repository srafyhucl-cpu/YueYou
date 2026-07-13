import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yueyou/core/database/storage_service.dart';
import 'package:yueyou/features/library/domain/book_model.dart';
import 'package:yueyou/features/library/providers/bookshelf_provider.dart';

/// 书架排序模式。
enum LibrarySortMode {
  /// 保持书架最近操作顺序。
  recent,

  /// 保持导入顺序；当前书架列表本身就是该顺序。
  imported,

  /// 按本地阅读进度从高到低排列。
  progress,
}

/// 书架视图状态，正文和元数据仍由 [bookshelfProvider] 持有。
typedef LibraryViewState = ({
  String query,
  LibrarySortMode sortMode,
});

/// 书架搜索词与排序选择。
final libraryViewProvider =
    NotifierProvider<LibraryViewNotifier, LibraryViewState>(
  LibraryViewNotifier.new,
);

/// 根据书架真值派生当前可见书籍，不修改持久化顺序。
final libraryVisibleBooksProvider = Provider<List<BookModel>>((ref) {
  final shelf = ref.watch(bookshelfProvider);
  final view = ref.watch(libraryViewProvider);
  final query = view.query.trim().toLowerCase();
  final visible = shelf.shelf
      .where(
        (book) =>
            query.isEmpty || book.displayTitle.toLowerCase().contains(query),
      )
      .toList(growable: true);

  if (view.sortMode == LibrarySortMode.progress) {
    visible.sort(
      (left, right) => readingPercentForLibrarySort(right.id)
          .compareTo(readingPercentForLibrarySort(left.id)),
    );
  }

  return List<BookModel>.unmodifiable(visible);
});

/// 书架视图状态 Provider 的唯一写入口。
class LibraryViewNotifier extends Notifier<LibraryViewState> {
  @override
  LibraryViewState build() => (
        query: '',
        sortMode: LibrarySortMode.recent,
      );

  /// 更新搜索词；不会触碰书架存储。
  void setQuery(String query) {
    state = (query: query, sortMode: state.sortMode);
  }

  /// 更新排序模式；不会改变书架原始列表。
  void setSortMode(LibrarySortMode sortMode) {
    state = (query: state.query, sortMode: sortMode);
  }

  /// 清空搜索词并恢复全部书籍可见。
  void clearQuery() {
    setQuery('');
  }
}

/// 供排序 Provider 使用的本地阅读进度读取适配点。
///
/// 保留为独立函数，便于后续把阅读记录 selector 化时替换，不改变现有存储契约。
double readingPercentForLibrarySort(int bookId) {
  final record = StorageService.getReadingRecord(bookId.toString());
  return (record['percent'] as num?)?.toDouble() ?? 0.0;
}
