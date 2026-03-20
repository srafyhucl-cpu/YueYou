import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:yueyou/core/theme/cyber_colors.dart';
import 'package:yueyou/features/reader/providers/reader_provider.dart';

/// 章节目录界面
/// 完整复刻旧版 modal-chapters：章节列表、正序/倒序切换、跳转、进度标注
class ChapterListScreen extends StatefulWidget {
  const ChapterListScreen({super.key});

  @override
  State<ChapterListScreen> createState() => _ChapterListScreenState();
}

class _ChapterListScreenState extends State<ChapterListScreen> {
  bool _reversed = false; // 对应 JS window._chapterReversed

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0E18),
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(context),
            _buildStats(context),
            Expanded(child: _buildChapterList(context)),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          height: 56,
          color: const Color(0xCC0D0E18),
          child: Row(
            children: [
              const SizedBox(width: 16),
              const Text(
                '章节目录',
                style: TextStyle(
                  color: CyberColors.neonPurple,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 2,
                ),
              ),
              const Spacer(),
              // 正序/倒序切换（对应 JS btn-sort-chapters）
              TextButton.icon(
                onPressed: () => setState(() => _reversed = !_reversed),
                icon: Icon(
                  _reversed ? Icons.arrow_upward : Icons.arrow_downward,
                  size: 16,
                  color: Colors.white54,
                ),
                label: Text(
                  _reversed ? '倒序' : '正序',
                  style: const TextStyle(color: Colors.white54, fontSize: 13),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, color: Colors.white70),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStats(BuildContext context) {
    return Consumer<ReaderProvider>(
      builder: (context, reader, _) {
        final int total = reader.chapters.length;
        final int cursor = reader.currentIndex;
        final int totalLines = reader.sentences.length;
        final int percent =
            totalLines > 0 ? ((cursor / totalLines) * 100).floor() : 0;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          color: const Color(0x220D0E18),
          child: Text(
            '共 $total 章 | 阅读进度 $percent%',
            style: const TextStyle(color: Colors.white38, fontSize: 12),
          ),
        );
      },
    );
  }

  Widget _buildChapterList(BuildContext context) {
    return Consumer<ReaderProvider>(
      builder: (context, reader, _) {
        final chapters = reader.chapters;
        if (chapters.isEmpty) {
          return const Center(
            child: Text(
              '暂无目录数据',
              style: TextStyle(color: Colors.white38, fontSize: 14),
            ),
          );
        }

        final currentIndex = reader.currentIndex;

        return ListView.builder(
          itemCount: chapters.length,
          itemBuilder: (context, index) {
            final chapter = chapters[index];
            final isCurrentChapter = currentIndex >= chapter.lineIndex &&
                (index == chapters.length - 1 ||
                    currentIndex < chapters[index + 1].lineIndex);

            return _buildChapterItem(
              context,
              chapter,
              index,
              reader,
              isCurrentChapter,
            );
          },
        );
      },
    );
  }

  Widget _buildChapterItem(
    BuildContext context,
    dynamic chapter,
    int index,
    ReaderProvider reader,
    bool isCurrentChapter,
  ) {
    return Consumer<ReaderProvider>(
      builder: (context, reader, _) {
        final chapters = reader.chapters;

        // 判断当前活跃章节（对应 JS activeIdx 逻辑）
        int activeIdx = -1;
        for (int i = chapters.length - 1; i >= 0; i--) {
          if (reader.currentIndex >= chapters[i].lineIndex) {
            activeIdx = i;
            break;
          }
        }

        final displayChapters =
            _reversed ? chapters.reversed.toList() : chapters;

        return ListView.builder(
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: displayChapters.length,
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
                // 对应 JS jumpTo(c.lineIndex)
                reader.jumpToLine(chapter.lineIndex);
                Navigator.of(context).pop();
              },
            );
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
    Color dotColor = Colors.white24;
    Color textColor = Colors.white54;
    if (isActive) {
      dotColor = CyberColors.neonPurple;
      textColor = CyberColors.neonPink;
    } else if (isRead) {
      dotColor = Colors.white38;
      textColor = Colors.white38;
    }

    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: Colors.white.withOpacity(0.05)),
          ),
          color: isActive
              ? CyberColors.neonPink.withOpacity(0.1)
              : Colors.transparent,
        ),
        child: Row(
          children: [
            if (isActive)
              const Padding(
                padding: EdgeInsets.only(right: 8),
                child: Icon(
                  Icons.play_arrow,
                  color: CyberColors.neonPink,
                  size: 18,
                ),
              )
            else
              Container(
                width: 6,
                height: 6,
                margin: const EdgeInsets.only(right: 12),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: dotColor,
                ),
              ),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  color: isActive ? CyberColors.neonPink : textColor,
                  fontSize: 14,
                  fontWeight: isActive ? FontWeight.w900 : FontWeight.normal,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
