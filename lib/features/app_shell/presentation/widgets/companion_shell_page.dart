import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yueyou/core/config/feature_flags.dart';
import 'package:yueyou/core/theme/cyber_colors.dart';
import 'package:yueyou/core/theme/cyber_dimensions.dart';
import 'package:yueyou/core/theme/cyber_text_styles.dart';
import 'package:yueyou/features/companion/domain/xiaoyo_semantics.dart';
import 'package:yueyou/features/companion/presentation/widgets/xiaoyo_mascot.dart';
import 'package:yueyou/features/xiaoyo/providers/xiaoyo_profile_notifier.dart';
import 'package:yueyou/features/xiaoyo/presentation/widgets/xiaoyo_profile_summary.dart';

/// 陪伴页视觉入口，仅承载角色展示，不承载成长、权益或关系业务逻辑。
class CompanionShellPage extends ConsumerWidget {
  const CompanionShellPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final profileState = FeatureFlags.xiaoyoValueSystem
        ? ref.watch(xiaoyoProfileProvider)
        : null;
    final profile = switch (profileState) {
      AsyncData(value: final value) => value,
      _ => null,
    };
    final growthStage = profile?.growthStage ?? 0;
    final growthSummary =
        profile == null ? '安静待机' : '共读成长 ${profile.bondXp} · 阶段 $growthStage';
    return Scaffold(
      backgroundColor: CyberColors.background,
      appBar: AppBar(
        title: const Text('陪伴', style: CyberTextStyles.screenTitle),
        backgroundColor: CyberColors.background,
        foregroundColor: CyberColors.neonCyan,
      ),
      body: SingleChildScrollView(
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
                  growthStage: growthStage,
                  reduceMotion: reduceMotion,
                ),
              ),
            ),
            const SizedBox(height: CyberDimensions.spacingM),
            Text(growthSummary, style: CyberTextStyles.screenTitle),
            const SizedBox(height: CyberDimensions.spacingS),
            const Text(
              '角色资产加载失败时自动保留静态回退。',
              style: CyberTextStyles.bodySmall,
            ),
            if (profile != null) ...[
              const SizedBox(height: CyberDimensions.spacingS),
              XiaoyoProfileSummary(profile: profile),
            ],
          ],
        ),
      ),
    );
  }
}
