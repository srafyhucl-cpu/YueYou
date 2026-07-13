import 'package:flutter/material.dart';
import 'package:yueyou/core/theme/cyber_colors.dart';
import 'package:yueyou/core/theme/cyber_dimensions.dart';
import 'package:yueyou/core/theme/cyber_text_styles.dart';
import 'package:yueyou/features/xiaoyo/domain/bookscape_preview.dart';

/// 只读展示免费与主题书境的视觉差异，不承载购买或权益逻辑。
class XiaoyoBookscapePreview extends StatelessWidget {
  const XiaoyoBookscapePreview({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const Text('书境效果对比', style: CyberTextStyles.sectionLabel),
        const SizedBox(height: CyberDimensions.spacingS),
        const Text(
          '同一进度、同一荣誉，仅比较书境表现。',
          style: CyberTextStyles.bodySmall,
        ),
        const SizedBox(height: CyberDimensions.spacingS),
        ...XiaoyoBookscapePreviews.all.map(_BookscapeTile.new),
      ],
    );
  }
}

class _BookscapeTile extends StatelessWidget {
  final XiaoyoBookscapeDefinition definition;

  const _BookscapeTile(this.definition);

  @override
  Widget build(BuildContext context) {
    final isPreview = definition.previewOnly;
    final color = isPreview ? CyberColors.neonPink : CyberColors.neonCyan;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: CyberDimensions.spacingS),
      padding: const EdgeInsets.all(CyberDimensions.spacingM),
      decoration: BoxDecoration(
        color: CyberColors.panelBackground,
        border: Border.all(color: color.withValues(alpha: 0.38)),
        borderRadius: BorderRadius.circular(CyberDimensions.radiusXS),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  definition.title,
                  style: CyberTextStyles.bodySmallBold,
                ),
              ),
              Text(
                isPreview ? '仅预览' : '免费可用',
                style: CyberTextStyles.captionBold.copyWith(color: color),
              ),
            ],
          ),
          const SizedBox(height: CyberDimensions.spacingXS),
          Text(definition.sceneTitle, style: CyberTextStyles.tileSubtitle),
          const SizedBox(height: CyberDimensions.spacingS),
          Text(definition.description, style: CyberTextStyles.bodySmall),
          const SizedBox(height: CyberDimensions.spacingS),
          ...definition.visualDifferences.map(
            (item) => Padding(
              padding: const EdgeInsets.only(bottom: CyberDimensions.spacingXS),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Icon(
                    Icons.circle,
                    color: color,
                    size: CyberDimensions.iconXS,
                  ),
                  const SizedBox(width: CyberDimensions.spacingS),
                  Expanded(
                    child: Text(item, style: CyberTextStyles.captionBold),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
