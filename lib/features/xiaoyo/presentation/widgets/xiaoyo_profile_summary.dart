import 'package:flutter/material.dart';
import 'package:yueyou/core/theme/cyber_colors.dart';
import 'package:yueyou/core/theme/cyber_dimensions.dart';
import 'package:yueyou/core/theme/cyber_text_styles.dart';
import 'package:yueyou/features/xiaoyo/domain/book_realm_mark.dart';
import 'package:yueyou/features/xiaoyo/domain/xiaoyo_profile.dart';

/// 只读展示本地成长、书境印记和永久荣誉。
class XiaoyoProfileSummary extends StatelessWidget {
  final XiaoyoProfile profile;

  const XiaoyoProfileSummary({
    super.key,
    required this.profile,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const Text('共读记录', style: CyberTextStyles.sectionLabel),
        const SizedBox(height: CyberDimensions.spacingS),
        Text(
          '有效听读 ${profile.validListenSeconds ~/ 60} 分钟 · 印记 ${profile.bookRealmMarks.length} · 荣誉 ${profile.unlockedHonors.length}',
          style: CyberTextStyles.bodySmall,
        ),
        const SizedBox(height: CyberDimensions.spacingM),
        const Text('书境印记', style: CyberTextStyles.sectionLabel),
        const SizedBox(height: CyberDimensions.spacingS),
        if (profile.bookRealmMarks.isEmpty)
          const Text('完成一次有效听读后生成第一枚印记。', style: CyberTextStyles.bodySmall)
        else
          ...profile.bookRealmMarks.map(_MarkTile.new),
        const SizedBox(height: CyberDimensions.spacingM),
        const Text('永久荣誉', style: CyberTextStyles.sectionLabel),
        const SizedBox(height: CyberDimensions.spacingS),
        if (profile.unlockedHonors.isEmpty)
          const Text('荣誉会在首次完本或达到成长里程碑时解锁。', style: CyberTextStyles.bodySmall)
        else
          ...profile.unlockedHonors.map(
            (honor) => Padding(
              padding: const EdgeInsets.only(bottom: CyberDimensions.spacingS),
              child: Text(
                honor.honorId,
                style: CyberTextStyles.bodySmallBold,
              ),
            ),
          ),
      ],
    );
  }
}

class _MarkTile extends StatelessWidget {
  final BookRealmMark mark;

  const _MarkTile(this.mark);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: CyberDimensions.spacingS),
      padding: const EdgeInsets.all(CyberDimensions.spacingS),
      decoration: BoxDecoration(
        border: Border.all(color: CyberColors.neonCyan.withValues(alpha: 0.32)),
        borderRadius: BorderRadius.circular(CyberDimensions.radiusXS),
        color: CyberColors.panelBackground,
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              mark.titleSnapshot,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: CyberTextStyles.bodySmallBold,
            ),
          ),
          Text(_levelLabel(mark.level), style: CyberTextStyles.captionBold),
        ],
      ),
    );
  }

  String _levelLabel(BookRealmMarkLevel level) => switch (level) {
        BookRealmMarkLevel.none => '未点亮',
        BookRealmMarkLevel.glow => '微光',
        BookRealmMarkLevel.formed => '成形',
        BookRealmMarkLevel.resonance => '共振',
        BookRealmMarkLevel.sealed => '封页',
      };
}
