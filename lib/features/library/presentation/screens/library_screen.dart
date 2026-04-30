import 'dart:ui';
import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yueyou/core/theme/cyber_colors.dart';
import 'package:yueyou/core/theme/cyber_dimensions.dart';
import 'package:yueyou/core/theme/cyber_text_styles.dart';
import 'package:yueyou/features/library/domain/book_model.dart';
import 'package:yueyou/features/library/providers/bookshelf_provider.dart';
import 'package:yueyou/features/library/presentation/widgets/cyber_import_button.dart';
import 'package:yueyou/features/reader/providers/reader_provider.dart';
import 'package:yueyou/shared/widgets/cyber_confirm_dialog.dart';

/// 书库界面
/// 完整复刻旧版 modal-library：书架卡片列表、渐变封面、阅读进度条、删除、导入按钮
class LibraryScreen extends ConsumerWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final shelf = ref.watch(bookshelfProvider);
    return Scaffold(
      backgroundColor: CyberColors.panelBackground,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(context),
            Expanded(
              child: Builder(
                builder: (context) {
                  if (shelf.isEmpty) {
                    return _buildEmptyState();
                  }
                  return ListView.builder(
                    padding: const EdgeInsets.fromLTRB(CyberDimensions.spacingM,
                        CyberDimensions.spacingS, CyberDimensions.spacingM, 80,),
                    itemCount: shelf.shelf.length,
                    itemBuilder: (ctx, i) =>
                        _BookCard(book: shelf.shelf[i], index: i),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: const CyberImportButton(),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(
            sigmaX: CyberDimensions.blurLight,
            sigmaY: CyberDimensions.blurLight,),
        child: Container(
          height: CyberDimensions.headerHeight,
          color: CyberColors.panelBackground.withValues(alpha: 0.8),
          child: Row(
            children: [
              const SizedBox(width: CyberDimensions.spacingM),
              Text(
                '神经档案库',
                style: CyberTextStyles.screenTitle.copyWith(
                  color: CyberColors.neonPink,
                ),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.close, color: CyberColors.whiteDim),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.auto_stories_outlined,
              size: 64, color: CyberColors.whiteSubtle,),
          const SizedBox(height: CyberDimensions.spacingM),
          Text(
            '当前书架为空\n请导入 TXT 本地小说',
            textAlign: TextAlign.center,
            style: CyberTextStyles.tileTitle.copyWith(
              color: CyberColors.whiteMuted,
              height: 1.8,
            ),
          ),
        ],
      ),
    );
  }
}

class _BookCard extends ConsumerWidget {
  final BookModel book;
  final int index;

  const _BookCard({required this.book, required this.index});

  /// 对应 JS generateCoverGradient(title)
  List<Color> _coverGradient() {
    int hash = 0;
    for (int i = 0; i < book.displayTitle.length; i++) {
      hash = book.displayTitle.codeUnitAt(i) + ((hash << 5) - hash);
    }
    final int h1 = hash.abs() % 360;
    final int h2 = (h1 + 40) % 360;
    return [
      HSLColor.fromAHSL(1, h1.toDouble(), 0.8, 0.6).toColor(),
      HSLColor.fromAHSL(1, h2.toDouble(), 0.8, 0.4).toColor(),
    ];
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final double percent =
        ref.watch(bookshelfProvider).getReadingPercent(book.id);
    final colors = _coverGradient();

    return GestureDetector(
      onTap: () => _loadBook(context, ref),
      child: Container(
        margin: const EdgeInsets.only(bottom: CyberDimensions.spacingMS),
        height: 110,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(CyberDimensions.radiusM),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: colors,
          ),
          boxShadow: [
            BoxShadow(
              color: colors[0].withValues(alpha: 0.3),
              blurRadius: CyberDimensions.spacingM,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Stack(
          children: [
            // 封面水印大字
            Positioned(
              right: CyberDimensions.spacingM,
              top: 0,
              bottom: 0,
              child: Center(
                child: Text(
                  book.coverChar,
                  style: CyberTextStyles.screenTitle.copyWith(
                    fontSize: 72,
                    color: CyberColors.whiteFaint,
                    height: 1,
                  ),
                ),
              ),
            ),
            // 信息 overlay
            Positioned.fill(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(CyberDimensions.radiusM),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 0, sigmaY: 0),
                  child: Container(
                    color: CyberColors.background.withValues(alpha: 0.25),
                    padding: const EdgeInsets.all(CyberDimensions.spacingMS),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          book.displayTitle,
                          style: CyberTextStyles.tileTitle.copyWith(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '已读 ${percent.toStringAsFixed(1)}%',
                              style: CyberTextStyles.caption,
                            ),
                            const SizedBox(height: 4),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(CyberDimensions.radiusXS),
                              child: LinearProgressIndicator(
                                value: percent / 100,
                                backgroundColor: CyberColors.whiteSubtle,
                                valueColor: const AlwaysStoppedAnimation(
                                    CyberColors.whiteHigh,),
                                minHeight: 4,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            // 删除按钮
            Positioned(
              right: CyberDimensions.spacingMS,
              bottom: CyberDimensions.spacingMS,
              child: GestureDetector(
                onTap: () => _confirmDelete(context, ref),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: CyberDimensions.spacingMS,
                      vertical: CyberDimensions.spacingXS,),
                  decoration: BoxDecoration(
                    color: CyberColors.background.withValues(alpha: 0.45),
                    borderRadius:
                        BorderRadius.circular(CyberDimensions.radiusS),
                    border: Border.all(
                        color: CyberColors.whiteSubtle,
                        width: CyberDimensions.borderNormal,),
                  ),
                  child: const Text('删', style: CyberTextStyles.caption),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 对应 JS loadBookFromShelf(id, title, cursor)
  Future<void> _loadBook(BuildContext context, WidgetRef ref) async {
    final shelf = ref.read(bookshelfProvider);
    final reader = ref.read(readerProvider);

    final content = await shelf.loadBookContent(book.id);
    if (content == null) return;
    if (!context.mounted) return;

    final List<dynamic> rawLines = content['lines'] as List<dynamic>? ?? [];
    final lines = rawLines.map((e) => e.toString()).toList();

    // 从存储内容中恢复章节列表
    final List<dynamic> rawChapters =
        content['chapters'] as List<dynamic>? ?? [];
    final chapters = rawChapters
        .map((e) => ChapterModel.fromJson(e as Map<String, dynamic>))
        .toList();

    await reader.loadPreparedBook(lines,
        bookId: book.id.toString(), chapters: chapters,);
    if (!context.mounted) return;
    Navigator.of(context).pop();
  }

  /// 对应 JS deleteBook — 弹确认框再删
  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final confirmed = await showCyberConfirmDialog(
      context: context,
      title: '初始化抹除？',
      message: '此操作将永久移除该档案及其所有阅读进度，确认执行？',
      confirmText: '确定',
      cancelText: '取消',
    );
    if (confirmed == true && context.mounted) {
      final reader = ref.read(readerProvider);
      await ref.read(bookshelfProvider).deleteBook(book.id, reader: reader);
    }
  }
}
