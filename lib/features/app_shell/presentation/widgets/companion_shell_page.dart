import 'package:flutter/material.dart';
import 'package:yueyou/core/config/feature_flags.dart';
import 'package:yueyou/core/theme/cyber_colors.dart';
import 'package:yueyou/core/theme/cyber_dimensions.dart';
import 'package:yueyou/core/theme/cyber_text_styles.dart';
import 'package:yueyou/features/companion/domain/xiaoyo_semantics.dart';
import 'package:yueyou/features/companion/presentation/widgets/xiaoyo_mascot.dart';

/// 陪伴页视觉入口，仅承载角色展示，不承载成长、权益或关系业务逻辑。
class CompanionShellPage extends StatelessWidget {
  const CompanionShellPage({super.key});

  @override
  Widget build(BuildContext context) {
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    return Scaffold(
      backgroundColor: CyberColors.background,
      appBar: AppBar(
        title: const Text('陪伴', style: CyberTextStyles.screenTitle),
        backgroundColor: CyberColors.background,
        foregroundColor: CyberColors.neonCyan,
      ),
      body: Padding(
        padding: const EdgeInsets.all(CyberDimensions.spacingL),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Text('XIAOYO', style: CyberTextStyles.sectionLabel),
            const SizedBox(height: CyberDimensions.spacingS),
            Center(
              child: XiaoyoMascot(
                enableRive: FeatureFlags.xiaoyoV2,
                semantics: XiaoyoSemantics(
                  reduceMotion: reduceMotion,
                ),
              ),
            ),
            const SizedBox(height: CyberDimensions.spacingM),
            const Text('安静待机', style: CyberTextStyles.screenTitle),
            const SizedBox(height: CyberDimensions.spacingS),
            const Text(
              '角色资产加载失败时自动保留静态回退。',
              style: CyberTextStyles.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
