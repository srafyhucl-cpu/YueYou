import 'package:flutter/material.dart';
import 'package:yueyou/core/theme/cyber_colors.dart';
import 'package:yueyou/core/theme/cyber_dimensions.dart';
import 'package:yueyou/core/theme/cyber_text_styles.dart';
import 'package:yueyou/shared/widgets/cyber_modal.dart';

/// 赛博朋克风格确认对话框
/// 用于重置游戏等需要二次确认的操作
/// 基于 showCyberModal 封装，内部只提供确认内容（标题 + 消息 + 按钮）
Future<bool> showCyberConfirmDialog({
  required BuildContext context,
  required String title,
  required String message,
  String confirmText = '确认',
  String cancelText = '取消',
}) async {
  final result = await showCyberModal<bool>(
    context: context,
    child: Padding(
      padding: const EdgeInsets.all(CyberDimensions.spacingL),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            title,
            style: CyberTextStyles.dialogTitle.copyWith(
              color: CyberColors.whiteHigh,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: CyberDimensions.spacingM),
          Flexible(
            child: SingleChildScrollView(
              child: Text(
                message,
                textAlign: TextAlign.center,
                style: CyberTextStyles.bodySmall.copyWith(
                  color: CyberColors.whiteMedium,
                  fontSize: 14,
                  height: 1.5,
                ),
              ),
            ),
          ),
          const SizedBox(height: CyberDimensions.spacingL),
          Row(
            children: [
              Expanded(
                child: _CyberButton(
                  text: cancelText,
                  isPrimary: false,
                  onTap: () => Navigator.of(context).pop(false),
                ),
              ),
              const SizedBox(width: CyberDimensions.spacingMS),
              Expanded(
                child: _CyberButton(
                  text: confirmText,
                  isPrimary: true,
                  onTap: () => Navigator.of(context).pop(true),
                ),
              ),
            ],
          ),
        ],
      ),
    ),
  );
  return result ?? false;
}

class _CyberButton extends StatelessWidget {
  final String text;
  final bool isPrimary;
  final VoidCallback onTap;

  const _CyberButton({
    required this.text,
    required this.isPrimary,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding:
            const EdgeInsets.symmetric(vertical: CyberDimensions.spacingMS),
        decoration: BoxDecoration(
          gradient: isPrimary
              ? const LinearGradient(
                  colors: [CyberColors.hotPink, CyberColors.neonPurple],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                )
              : null,
          color: isPrimary ? null : CyberColors.whiteSubtle,
          borderRadius: BorderRadius.circular(CyberDimensions.radiusS),
          border: Border.all(
            color:
                isPrimary ? CyberColors.transparent : CyberColors.whiteSubtle,
            width: CyberDimensions.borderNormal,
          ),
        ),
        child: Center(
          child: Text(
            text,
            style: CyberTextStyles.buttonLabel.copyWith(
              color: CyberColors.whiteHigh,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      ),
    );
  }
}
