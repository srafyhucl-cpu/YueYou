import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:yueyou/core/theme/cyber_colors.dart';
import 'package:yueyou/core/theme/cyber_dimensions.dart';
import 'package:yueyou/features/library/domain/book_model.dart';
import 'package:yueyou/features/library/providers/bookshelf_provider.dart';
import 'package:yueyou/features/library/presentation/widgets/cyber_import_button.dart';
import 'package:yueyou/features/reader/providers/reader_provider.dart';

/// 书库界面
/// 完整复刻旧版 modal-library：书架卡片列表、渐变封面、阅读进度条、删除、导入按钮
class LibraryScreen extends StatelessWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: CyberColors.panelBackground,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(context),
            Expanded(
              child: Consumer<BookshelfProvider>(
                builder: (context, shelf, _) {
                  if (shelf.isEmpty) {
                    return _buildEmptyState();
                  }
                  return ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 80),
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
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          height: 56,
          color: CyberColors.panelBackground.withOpacity(0.8),
          child: Row(
            children: [
              const SizedBox(width: 16),
              const Text(
                '神经档案库',
                style: TextStyle(
                  color: CyberColors.neonPink,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 2,
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
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.auto_stories_outlined,
              size: 64, color: CyberColors.whiteSubtle),
          SizedBox(height: 16),
          Text(
            '当前书架为空\n请导入 TXT 本地小说',
            textAlign: TextAlign.center,
            style: TextStyle(
                color: CyberColors.whiteMuted, fontSize: 14, height: 1.8),
          ),
        ],
      ),
    );
  }
}

class _BookCard extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final double percent =
        context.watch<BookshelfProvider>().getReadingPercent(book.id);
    final colors = _coverGradient();

    return GestureDetector(
      onTap: () => _loadBook(context),
      child: Container(
        margin: const EdgeInsets.only(bottom: 14),
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
              color: colors[0].withOpacity(0.3),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Stack(
          children: [
            // 封面水印大字
            Positioned(
              right: 16,
              top: 0,
              bottom: 0,
              child: Center(
                child: Text(
                  book.coverChar,
                  style: const TextStyle(
                    fontSize: 72,
                    fontWeight: FontWeight.bold,
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
                    color: CyberColors.background.withOpacity(0.25),
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          book.displayTitle,
                          style: const TextStyle(
                            color: Colors.white,
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
                              style: const TextStyle(
                                  color: CyberColors.whiteDim, fontSize: 12),
                            ),
                            const SizedBox(height: 4),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(2),
                              child: LinearProgressIndicator(
                                value: percent / 100,
                                backgroundColor: CyberColors.whiteSubtle,
                                valueColor:
                                    const AlwaysStoppedAnimation(Colors.white),
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
              right: 10,
              bottom: 10,
              child: GestureDetector(
                onTap: () => _confirmDelete(context),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: CyberColors.background.withOpacity(0.45),
                    borderRadius:
                        BorderRadius.circular(CyberDimensions.radiusS),
                    border:
                        Border.all(color: CyberColors.whiteSubtle, width: 0.8),
                  ),
                  child: const Text('删',
                      style:
                          TextStyle(color: CyberColors.whiteDim, fontSize: 12)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 对应 JS loadBookFromShelf(id, title, cursor)
  Future<void> _loadBook(BuildContext context) async {
    final shelf = context.read<BookshelfProvider>();
    final reader = context.read<ReaderProvider>();

    final content = await shelf.loadBookContent(book.id);
    if (content == null) return;
    if (!context.mounted) return;

    final List<dynamic> rawLines = content['lines'] as List<dynamic>? ?? [];
    final String rawText = rawLines.join('\n');

    // 从存储内容中恢复章节列表
    final List<dynamic> rawChapters =
        content['chapters'] as List<dynamic>? ?? [];
    final chapters = rawChapters
        .map((e) => ChapterModel.fromJson(e as Map<String, dynamic>))
        .toList();

    await reader.loadBook(rawText,
        bookId: book.id.toString(), chapters: chapters);
    if (!context.mounted) return;
    Navigator.of(context).pop();
  }

  /// 对应 JS deleteBook — 弹确认框再删
  Future<void> _confirmDelete(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: CyberColors.surface,
        title:
            const Text('初始化抹除？', style: TextStyle(color: CyberColors.neonPink)),
        content: const Text(
          '此操作将永久移除该档案及其所有阅读进度，确认执行？',
          style: TextStyle(color: CyberColors.whiteDim),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child:
                const Text('取消', style: TextStyle(color: CyberColors.whiteDim)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child:
                const Text('确定', style: TextStyle(color: CyberColors.neonPink)),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      await context.read<BookshelfProvider>().deleteBook(book.id);
    }
  }
}
