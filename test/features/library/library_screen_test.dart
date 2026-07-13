import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yueyou/core/database/storage_service.dart';
import 'package:yueyou/features/audio/services/tts_engine_service.dart';
import 'package:yueyou/features/library/domain/book_model.dart';
import 'package:yueyou/features/library/presentation/screens/library_root_screen.dart';
import 'package:yueyou/features/library/presentation/screens/library_screen.dart';
import 'package:yueyou/features/library/providers/bookshelf_provider.dart';
import 'package:yueyou/features/reader/providers/reader_provider.dart';

import '../../utils/test_utils.dart';

/// LibraryScreen widget 烟测，目标覆盖：
///   * 空书架占位文本渲染（line 33-34, 88-110）
///   * 非空书架 ListView + _BookCard（line 36-46, 113-256）
///   * Header 区域（line 57-86）
///   * _coverGradient 计算与 LinearProgressIndicator 渲染（line 119-220）
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  TtsEngineService? activeEngine;

  setUp(() async {
    await initializeTestEnvironment();
  });

  tearDown(() {
    activeEngine?.dispose();
    activeEngine = null;
  });

  /// 用 ProviderScope override 注入受控 BookshelfProvider 与新建的 ReaderProvider。
  ///
  /// 必须显式 override readerProvider，否则默认 provider 会在 setUp/tearDown
  /// 之间被 ProviderScope 容器 dispose 后误用，触发
  /// `A ReaderProvider was used after being disposed`。
  Widget _wrap(BookshelfProvider shelf,
      {Widget screen = const LibraryScreen()}) {
    final settings = makeSettings();
    final engine = makeTtsEngine(settings);
    activeEngine = engine;
    final reader = ReaderProvider(engine);

    return ProviderScope(
      overrides: [
        bookshelfProvider.overrideWith((ref) => shelf),
        readerProvider.overrideWith((ref) => reader),
      ],
      child: MaterialApp(home: screen),
    );
  }

  testWidgets('LibraryRootScreen 复用书架内容但不显示 Modal 关闭按钮', (tester) async {
    final shelf = BookshelfProvider()..setShelfForTesting(const []);
    await tester.pumpWidget(_wrap(shelf, screen: const LibraryRootScreen()));

    expect(find.byType(LibraryScreen), findsOneWidget);
    expect(find.text('神经档案库'), findsOneWidget);
    expect(find.byIcon(Icons.close), findsNothing);
  });

  testWidgets('LibraryScreen 在书架为空时必须显示「当前书架为空」占位', (tester) async {
    // hasSelectedBook=true 阻止 BookshelfProvider 自动注入西游记
    SharedPreferences.setMockInitialValues({'has_selected_book': true});
    StorageService.resetForTesting();
    await StorageService.init();

    final shelf = BookshelfProvider()..loadFromStorage();
    expect(shelf.isEmpty, isTrue, reason: '前置：测试环境下书架必须为空');

    await tester.pumpWidget(_wrap(shelf));

    expect(find.text('神经档案库'), findsOneWidget, reason: 'Header 标题必须渲染');
    expect(find.textContaining('当前书架为空'), findsOneWidget, reason: '空状态占位必须出现');
    expect(find.byIcon(Icons.auto_stories_outlined), findsOneWidget,
        reason: '空状态 Icon 必须渲染');
    expect(find.byIcon(Icons.close), findsOneWidget, reason: 'Header 必须有关闭按钮');
  });

  testWidgets('LibraryScreen 在书架非空时必须渲染 BookCard 与阅读进度', (tester) async {
    // 注入一本受控 BookModel 到 SharedPreferences
    final book = const BookModel(
      id: 99,
      title: '云端存档.txt',
      total: 100,
      cursor: 30,
    );
    SharedPreferences.setMockInitialValues({
      'has_selected_book': true,
      'local_bookshelf': jsonEncode([book.toJson()]),
      'reading_records': jsonEncode({
        '99': {'percent': 30.5, 'cursor': 30},
      }),
    });
    StorageService.resetForTesting();
    await StorageService.init();

    final shelf = BookshelfProvider()..loadFromStorage();
    expect(shelf.shelf.length, 1, reason: '前置：注入 1 本测试书');

    await tester.pumpWidget(_wrap(shelf));

    // 显示标题（去掉 .txt 后缀）
    expect(find.text('云端存档'), findsOneWidget,
        reason: 'BookModel.displayTitle 必须渲染（已剥离 .txt）');
    // 封面首字（coverChar）
    expect(find.text('云'), findsOneWidget,
        reason: 'BookModel.coverChar 必须渲染（首字符）');
    // 阅读进度文本
    expect(find.textContaining('已读 30.5%'), findsOneWidget,
        reason: '阅读进度百分比必须渲染');
    // 删除按钮
    expect(find.text('删'), findsOneWidget, reason: '删除按钮必须渲染');
    // 进度条
    expect(find.byType(LinearProgressIndicator), findsOneWidget,
        reason: 'LinearProgressIndicator 必须渲染');
  });

  testWidgets('LibraryScreen 多本书时必须渲染 ListView.builder 多个 BookCard',
      (tester) async {
    final books = const [
      BookModel(id: 1, title: '档案 A.txt', total: 50, cursor: 10),
      BookModel(id: 2, title: '档案 B.txt', total: 80, cursor: 40),
      BookModel(id: 3, title: '档案 C.txt', total: 120, cursor: 60),
    ];
    SharedPreferences.setMockInitialValues({
      'has_selected_book': true,
      'local_bookshelf': jsonEncode(books.map((b) => b.toJson()).toList()),
    });
    StorageService.resetForTesting();
    await StorageService.init();

    final shelf = BookshelfProvider()..loadFromStorage();
    expect(shelf.shelf.length, 3);

    await tester.pumpWidget(_wrap(shelf));

    expect(find.text('档案 A'), findsOneWidget);
    expect(find.text('档案 B'), findsOneWidget);
    expect(find.text('档案 C'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNWidgets(3));
  });

  testWidgets('LibraryScreen 必须挂载 CyberImportButton', (tester) async {
    SharedPreferences.setMockInitialValues({'has_selected_book': true});
    StorageService.resetForTesting();
    await StorageService.init();

    final shelf = BookshelfProvider()..loadFromStorage();
    await tester.pumpWidget(_wrap(shelf));

    // CyberImportButton 是 ConsumerStatefulWidget，不是 FAB；以类型查找
    expect(
      find.byWidgetPredicate(
        (w) => w.runtimeType.toString() == 'CyberImportButton',
      ),
      findsOneWidget,
      reason: 'CyberImportButton 必须挂载到 Scaffold.floatingActionButton',
    );
  });

  // ── tap 删除按钮 → 弹 CyberConfirmDialog → tap 取消保留书籍 ─────────────
  // 覆盖 lib/features/library/presentation/screens/library_screen.dart：
  //   * line 232-251 GestureDetector 删除按钮 onTap
  //   * line 297-310 _confirmDelete 内 showCyberConfirmDialog 调用 + cancel 路径
  testWidgets('LibraryScreen tap 删除按钮必须弹出 CyberConfirmDialog 并支持取消',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final book = const BookModel(
      id: 42,
      title: '待删档案.txt',
      total: 50,
      cursor: 5,
    );
    SharedPreferences.setMockInitialValues({
      'has_selected_book': true,
      'local_bookshelf': jsonEncode([book.toJson()]),
    });
    StorageService.resetForTesting();
    await StorageService.init();

    final shelf = BookshelfProvider()..loadFromStorage();
    await tester.pumpWidget(_wrap(shelf));

    // tap 删除按钮（每个 BookCard 内的「删」字按钮）
    await tester.tap(find.text('删'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    // CyberConfirmDialog 弹出
    expect(find.text('初始化抹除？'), findsOneWidget,
        reason: 'tap 删除按钮必须弹出确认对话框「初始化抹除？」');
    expect(find.text('确定'), findsOneWidget);
    expect(find.text('取消'), findsOneWidget);

    // tap 取消 → 关闭 dialog 不删除
    await tester.tap(find.text('取消'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    // 书架仍有这本书
    expect(shelf.shelf.length, 1, reason: 'tap 取消后书籍必须保留');
  });
}
