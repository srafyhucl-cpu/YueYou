import 'dart:ui';

import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yueyou/core/theme/cyber_colors.dart';
import 'package:yueyou/core/theme/cyber_dimensions.dart';
import 'package:yueyou/features/library/providers/bookshelf_provider.dart';
import 'package:yueyou/features/library/services/file_import_service.dart';
import 'package:yueyou/features/reader/providers/reader_provider.dart';
import 'package:yueyou/shared/widgets/cyber_toast.dart';
import 'package:yueyou/core/constants/cyber_error_messages.dart';
import 'package:yueyou/features/settings/providers/settings_provider.dart';

class CyberImportButton extends ConsumerStatefulWidget {
  const CyberImportButton({super.key});

  @override
  ConsumerState<CyberImportButton> createState() => _CyberImportButtonState();
}

class _CyberImportButtonState extends ConsumerState<CyberImportButton> {
  @override
  void dispose() {
    FileImportService.cancelImport();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reader = ref.watch(readerProvider);
    final bool isBusy = reader.isParsing;
    return Semantics(
      button: true,
      enabled: !isBusy,
      label: isBusy ? '正在导入书籍' : '导入 TXT 书籍',
      child: Tooltip(
        message: isBusy ? '正在导入' : '导入 TXT 书籍',
        child: ClipRRect(
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
                          final result =
                              await FileImportService.importTxtFileStructured();
                          if (result == null || result.lines.isEmpty) return;
                          if (!context.mounted) return;

                          final int bookId =
                              DateTime.now().millisecondsSinceEpoch;

                          // 写入书架（对应 JS LocalDB.saveBook + shelf.unshift）
                          await ref.read(bookshelfProvider).addBook(
                                id: bookId,
                                title: result.title,
                                lines: result.lines,
                                chapters: result.chapters,
                              );
                          if (!context.mounted) return;

                          // 自动加载到提词器（对应 JS loadBookFromShelf）
                          await ref.read(readerProvider).loadPreparedBook(
                                result.lines,
                                bookId: bookId.toString(),
                                chapters: result.chapters,
                              );
                          if (!context.mounted) return;

                          // 文件选择本身已经是用户主动授权；自动朗读开启时直接进入听读。
                          if (ref.read(settingsProvider).storyTts) {
                            ref.read(readerProvider).toggleTTS();
                          }

                          CyberToast.show(
                            '档案注入成功',
                            context: context,
                            type: ToastType.success,
                          );
                        } catch (error) {
                          final String msg = error is FileTooLargeException
                              ? error.toString()
                              : CyberErrorMessages.importFormatFailed;
                          CyberToast.show(
                            msg,
                            context: context,
                            type: ToastType.error,
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
                    color: CyberColors.cardBackground.withValues(alpha: 0.8),
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
                        blurRadius: CyberDimensions.shadowBlurM,
                        spreadRadius: 1,
                      ),
                      const BoxShadow(
                        color: CyberColors.blackShadow,
                        blurRadius: CyberDimensions.shadowBlurL,
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
        ),
      ),
    );
  }
}
