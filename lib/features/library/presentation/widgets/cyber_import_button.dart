import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:yueyou/core/theme/cyber_colors.dart';
import 'package:yueyou/core/theme/cyber_dimensions.dart';
import 'package:yueyou/features/library/providers/bookshelf_provider.dart';
import 'package:yueyou/features/library/services/file_import_service.dart';
import 'package:yueyou/features/reader/providers/reader_provider.dart';
import 'package:yueyou/shared/widgets/cyber_confirm_dialog.dart';
import 'package:yueyou/shared/widgets/cyber_toast.dart';
import 'package:yueyou/core/constants/cyber_error_messages.dart';

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
                        try {
                          final granted = await showCyberConfirmDialog(
                            context: context,
                            title: '存储访问授权',
                            message: '阅游需要读取您的本地存储以解析数据芯片 (TXT 文件)，是否授权？',
                            confirmText: '授权',
                            cancelText: '取消',
                          );
                          if (!granted) return;
                          if (!context.mounted) return;
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

                          CyberToast.show(context, '档案注入成功', type: ToastType.success);
                        } catch (error) {
                          final String msg = error is FileTooLargeException
                              ? error.toString()
                              : CyberErrorMessages.importFormatFailed;
                          CyberToast.show(context, msg, type: ToastType.error);
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
                      width: CyberDimensions.borderThick,
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
                        color: CyberColors.blackShadow,
                        blurRadius: 18,
                        offset: Offset(0, 8),
                      ),
                    ],
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [CyberColors.cardBackground, CyberColors.surface],
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
