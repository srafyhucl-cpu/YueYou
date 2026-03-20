import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:yueyou/core/theme/cyber_colors.dart';
import 'package:yueyou/features/library/services/file_import_service.dart';
import 'package:yueyou/features/reader/providers/reader_provider.dart';

class CyberImportButton extends StatelessWidget {
  const CyberImportButton({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<ReaderProvider>(
      builder: (context, reader, child) {
        final bool isBusy = reader.isParsing;
        return ClipRRect(
          borderRadius: BorderRadius.circular(28),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: isBusy
                    ? null
                    : () async {
                        final ScaffoldMessengerState messenger =
                            ScaffoldMessenger.of(context);
                        try {
                          final String? rawText =
                              await FileImportService.importTxtFile();
                          if (rawText == null || rawText.trim().isEmpty) {
                            return;
                          }
                          if (!context.mounted) {
                            return;
                          }
                          await context.read<ReaderProvider>().loadBook(rawText);
                          if (!context.mounted) {
                            return;
                          }
                          messenger.showSnackBar(
                            const SnackBar(content: Text('档案注入成功')),
                          );
                        } catch (error) {
                          messenger.showSnackBar(
                            SnackBar(content: Text('导入失败: $error')),
                          );
                        }
                      },
                borderRadius: BorderRadius.circular(28),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(28),
                    color: const Color(0xCC13141E),
                    border: Border.all(
                      color: isBusy ? CyberColors.neonPink : CyberColors.neonGreen,
                      width: 1.4,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: (isBusy ? CyberColors.pinkGlow : CyberColors.glowShadow),
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
