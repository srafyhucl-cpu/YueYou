import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:yueyou/core/theme/cyber_colors.dart';
import 'package:yueyou/core/theme/cyber_dimensions.dart';
import 'package:yueyou/features/library/providers/bookshelf_provider.dart';
import 'package:yueyou/features/library/services/file_import_service.dart';
import 'package:yueyou/features/reader/providers/reader_provider.dart';

class CyberImportButton extends StatefulWidget {
  const CyberImportButton({super.key});

  @override
  State<CyberImportButton> createState() => _CyberImportButtonState();
}

class _CyberImportButtonState extends State<CyberImportButton> {
  @override
  void dispose() {
    FileImportService.cancelImport();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ReaderProvider>(
      builder: (context, reader, child) {
        final bool isBusy = reader.isParsing;
        return ClipRRect(
          borderRadius: BorderRadius.circular(CyberDimensions.radiusL),
          child: BackdropFilter(
            filter: ImageFilter.blur(
              sigmaX: CyberDimensions.blurMedium,
              sigmaY: CyberDimensions.blurMedium,
            ),
            child: Material(
              color: CyberColors.transparent,
              child: InkWell(
                onTap: isBusy
                    ? null
                    : () async {
                        final ScaffoldMessengerState messenger =
                            ScaffoldMessenger.of(context);
                        try {
                          final result =
                              await FileImportService.importTxtFileStructured();
                          if (result == null || result.lines.isEmpty) return;
                          if (!context.mounted) return;

                          final int bookId =
                              DateTime.now().millisecondsSinceEpoch;

                          // 写入书架（对应 JS LocalDB.saveBook + shelf.unshift）
                          await context.read<BookshelfProvider>().addBook(
                                id: bookId,
                                title: result.title,
                                lines: result.lines,
                                chapters: result.chapters,
                              );
                          if (!context.mounted) return;

                          // 自动加载到提词器（对应 JS loadBookFromShelf）
                          await context.read<ReaderProvider>().loadPreparedBook(
                                result.lines,
                                bookId: bookId.toString(),
                                chapters: result.chapters,
                              );
                          if (!context.mounted) return;

                          messenger.showSnackBar(
                            const SnackBar(content: Text('档案注入成功')),
                          );
                        } catch (error) {
                          messenger.showSnackBar(
                            SnackBar(content: Text('导入失败: $error')),
                          );
                        }
                      },
                borderRadius: BorderRadius.circular(CyberDimensions.radiusL),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    borderRadius:
                        BorderRadius.circular(CyberDimensions.radiusL),
                    color: CyberColors.cardBackground.withOpacity(0.8),
                    border: Border.all(
                      color:
                          isBusy ? CyberColors.neonPink : CyberColors.neonGreen,
                      width: 1.4,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: (isBusy
                            ? CyberColors.pinkGlow
                            : CyberColors.glowShadow),
                        blurRadius: 16,
                        spreadRadius: 1,
                      ),
                      const BoxShadow(
                        color: Color(0x66000000),
                        blurRadius: 18,
                        offset: Offset(0, 8),
                      ),
                    ],
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xCC1A1B28), Color(0x9913141E)],
                    ),
                  ),
                  child: Center(
                    child: isBusy
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.2,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                CyberColors.neonPink,
                              ),
                            ),
                          )
                        : const Icon(
                            Icons.folder_open,
                            color: CyberColors.neonGreen,
                            size: 28,
                          ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
