import 'package:flutter/material.dart';
import 'package:yueyou/core/theme/cyber_colors.dart';
import 'package:yueyou/core/theme/cyber_dimensions.dart';
import 'package:yueyou/core/theme/cyber_text_styles.dart';

/// PROD-01-A 的陪伴页占位，仅承载产品入口位置，不承载成长业务逻辑。
class CompanionShellPage extends StatelessWidget {
  const CompanionShellPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: CyberColors.background,
      appBar: AppBar(
        title: const Text('陪伴', style: CyberTextStyles.screenTitle),
        backgroundColor: CyberColors.background,
        foregroundColor: CyberColors.neonCyan,
      ),
      body: const Padding(
        padding: EdgeInsets.all(CyberDimensions.spacingL),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('Xiaoyo', style: CyberTextStyles.sectionLabel),
            SizedBox(height: CyberDimensions.spacingS),
            Text(
              '陪伴入口已就位',
              style: CyberTextStyles.screenTitle,
            ),
            SizedBox(height: CyberDimensions.spacingM),
            Text(
              '关系、印记与活动将在后续切片接入。当前页面不读取或写入新的用户数据。',
              style: CyberTextStyles.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
