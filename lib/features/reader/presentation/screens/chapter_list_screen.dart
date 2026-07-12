import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yueyou/core/theme/cyber_colors.dart';
import 'package:yueyou/core/theme/cyber_dimensions.dart';
import 'package:yueyou/core/theme/cyber_text_styles.dart';
import 'package:yueyou/core/constants/book_constants.dart';
import 'package:yueyou/features/reader/providers/reader_provider.dart';

/// 章节目录界面
/// 完整复刻旧版 modal-chapters：章节列表、正序/倒序切换、跳转、进度标注
class ChapterListScreen extends ConsumerStatefulWidget {
  const ChapterListScreen({super.key});

  @override
  ConsumerState<ChapterListScreen> createState() => _ChapterListScreenState();
}

class _ChapterListScreenState extends ConsumerState<ChapterListScreen> {
  bool _reversed = false;
  ScrollController? _scrollController;
  Timer? _pendingJumpTimer;

  @override
  void dispose() {
    _pendingJumpTimer?.cancel();
    _scrollController?.dispose();
    super.dispose();
  }

  ScrollController _createScrollController(ReaderProvider reader) {
    final chapters = reader.chapters;
    if (chapters.isEmpty) {
      return ScrollController();
    }

    // 找到当前章节索引
    int activeIdx = -1;
    for (int i = chapters.length - 1; i >= 0; i--) {
      if (reader.currentIndex >= chapters[i].lineIndex) {
        activeIdx = i;
        break;
      }
    }

    if (activeIdx == -1) {
      return ScrollController();
    }

    // O(1) 直接定位：创建时就设置初始偏移
    final targetIndex =
        _reversed ? (chapters.length - 1 - activeIdx) : activeIdx;
    const itemHeight = CyberDimensions.chapterItemHeight;
    final offset = targetIndex * itemHeight;

    return ScrollController(initialScrollOffset: offset);
  }

  @override
  Widget build(BuildContext context) {
    final reader = ref.watch(readerProvider);
    return Scaffold(
      backgroundColor: CyberColors.panelBackground,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(context),
            _buildStats(reader),
            Expanded(child: _buildChapterList(context, reader)),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(
          sigmaX: CyberDimensions.blurLight,
          sigmaY: CyberDimensions.blurLight,
        ),
        child: Container(
          height: CyberDimensions.headerHeight,
          color: CyberColors.panelBackground.withValues(alpha: 0.8),
          child: Row(
            children: [
              const SizedBox(width: CyberDimensions.spacingM),
              Text(
                '章节目录',
                style: CyberTextStyles.screenTitle.copyWith(
                  color: CyberColors.neonPurple,
                ),
              ),
              const Spacer(),
              // 正序/倒序切换（对应 JS btn-sort-chapters）
              TextButton.icon(
                onPressed: () => setState(() => _reversed = !_reversed),
                icon: Icon(
                  _reversed ? Icons.arrow_upward : Icons.arrow_downward,
                  size: CyberDimensions.iconXS,
                  color: CyberColors.whiteDim,
                ),
                label: Text(
                  _reversed ? '倒序' : '正序',
                  style: CyberTextStyles.bodySmall,
                ),
              ),
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

  Widget _buildStats(ReaderProvider reader) {
    final int total = reader.isDefaultBookMode
        ? BookConstants.defaultTotalChapters
        : reader.chapters.length;
    final int cursor = reader.currentIndex;
    final int totalLines = reader.sentences.length;
    final int percent =
        totalLines > 0 ? ((cursor / totalLines) * 100).floor() : 0;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: CyberDimensions.spacingM,
        vertical: CyberDimensions.spacingS,
      ),
      color: CyberColors.panelBackground.withValues(alpha: 0.13),
      child: Text(
        '共 $total 章 | 阅读进度 $percent%',
        style: CyberTextStyles.caption,
      ),
    );
  }

  Widget _buildChapterList(BuildContext context, ReaderProvider reader) {
    // ── 默认书籍（西游记）：全量100章 + 按章节索引标注当前章 ──
    if (reader.isDefaultBookMode) {
      return _buildDefaultBookChapterList(context, reader);
    }

    // ── 普通书籍：按行号索引 ──
    final chapters = reader.chapters;
    if (chapters.isEmpty) {
      return const Center(
        child: Text(
          '暂无目录数据',
          style: CyberTextStyles.labelMedium,
        ),
      );
    }

    // 找到当前活跃章节
    int activeIdx = -1;
    for (int i = chapters.length - 1; i >= 0; i--) {
      if (reader.currentIndex >= chapters[i].lineIndex) {
        activeIdx = i;
        break;
      }
    }

    final displayChapters = _reversed ? chapters.reversed.toList() : chapters;

    // O(1) 极限性能：创建时直接定位
    _scrollController ??= _createScrollController(reader);

    return ListView.builder(
      controller: _scrollController,
      itemCount: displayChapters.length,
      itemExtent: CyberDimensions.chapterItemHeight, // 固定item高度，提升性能
      padding: const EdgeInsets.symmetric(vertical: CyberDimensions.spacingS),
      itemBuilder: (ctx, i) {
        final chapter = displayChapters[i];
        final int originalIdx = _reversed ? (chapters.length - 1 - i) : i;

        final bool isActive = originalIdx == activeIdx;
        final bool isRead = originalIdx < activeIdx;

        return _ChapterItem(
          title: chapter.title,
          isActive: isActive,
          isRead: isRead,
          onTap: () {
            // 先关闭弹窗，避免动画冲突
            Navigator.of(context).pop();

            // 等待弹窗退场动画完成后，再执行数据突变
            _pendingJumpTimer?.cancel();
            _pendingJumpTimer = Timer(CyberDimensions.animFast, () {
              reader.jumpToLine(chapter.lineIndex);
            });
          },
        );
      },
    );
  }

  /// 默认书籍（西游记）的章节列表：全量100章，点击触发分章懒加载
  Widget _buildDefaultBookChapterList(
    BuildContext context,
    ReaderProvider reader,
  ) {
    const allTitles = BookConstants.xiyoujiChapterTitles;
    final int activeIdx = reader.currentChapterIndex ?? 0;

    // O(1) 初始滚动定位
    if (_scrollController == null) {
      final targetIndex =
          _reversed ? (allTitles.length - 1 - activeIdx) : activeIdx;
      _scrollController = ScrollController(
        initialScrollOffset: (targetIndex * CyberDimensions.chapterItemHeight)
            .clamp(0.0, double.infinity),
      );
    }

    return ListView.builder(
      controller: _scrollController,
      itemCount: allTitles.length,
      itemExtent: CyberDimensions.chapterItemHeight,
      padding: const EdgeInsets.symmetric(vertical: CyberDimensions.spacingS),
      itemBuilder: (ctx, i) {
        final int originalIdx = _reversed ? (allTitles.length - 1 - i) : i;
        return _ChapterItem(
          title: allTitles[originalIdx],
          isActive: originalIdx == activeIdx,
          isRead: originalIdx < activeIdx,
          onTap: () {
            Navigator.of(context).pop();
            _pendingJumpTimer?.cancel();
            _pendingJumpTimer = Timer(CyberDimensions.animFast, () {
              reader.loadChapter(originalIdx);
            });
          },
        );
      },
    );
  }
}

class _ChapterItem extends StatelessWidget {
  final String title;
  final bool isActive;
  final bool isRead;
  final VoidCallback onTap;

  const _ChapterItem({
    required this.title,
    required this.isActive,
    required this.isRead,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    Color dotColor = CyberColors.whiteSubtle;
    Color textColor = CyberColors.whiteDim;
    if (isActive) {
      dotColor = CyberColors.neonPink;
      textColor = CyberColors.neonPink;
    } else if (isRead) {
      dotColor = CyberColors.whiteMuted;
      textColor = CyberColors.whiteMuted;
    }

    return Semantics(
      button: true,
      selected: isActive,
      label: isActive ? '$title，当前章节' : title,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: CyberDimensions.spacingM,
            vertical: CyberDimensions.spacingMS,
          ),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: CyberColors.whiteFaint.withValues(alpha: 0.4),
              ),
            ),
            color: isActive
                ? CyberColors.neonPink.withValues(alpha: 0.1)
                : CyberColors.transparent,
          ),
          child: Row(
            children: [
              if (isActive)
                const Padding(
                  padding: EdgeInsets.only(right: CyberDimensions.spacingS),
                  child: Icon(
                    Icons.play_arrow,
                    color: CyberColors.neonPink,
                    size: CyberDimensions.iconS,
                  ),
                )
              else
                Container(
                  width: CyberDimensions.statusDotSize,
                  height: CyberDimensions.statusDotSize,
                  margin:
                      const EdgeInsets.only(right: CyberDimensions.spacingMS),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: dotColor,
                  ),
                ),
              Expanded(
                child: Text(
                  title,
                  style: CyberTextStyles.tileTitle.copyWith(
                    color: isActive ? CyberColors.neonPink : textColor,
                    fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
