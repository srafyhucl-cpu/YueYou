/// 活动里程碑定义。
final class XiaoyoActivityMilestone {
  final String id;
  final int requiredSeconds;
  final String rewardId;
  final String rewardTitle;

  const XiaoyoActivityMilestone({
    required this.id,
    required this.requiredSeconds,
    required this.rewardId,
    required this.rewardTitle,
  });
}

/// 本地累计型活动定义，不包含远程配置或付费条件。
final class XiaoyoActivityDefinition {
  final String id;
  final String title;
  final int durationDays;
  final List<XiaoyoActivityMilestone> milestones;

  const XiaoyoActivityDefinition({
    required this.id,
    required this.title,
    required this.durationDays,
    required this.milestones,
  });
}

/// 首个本地活动目录。
abstract final class XiaoyoActivityDefinitions {
  static const readingSeason = XiaoyoActivityDefinition(
    id: 'reading_season_21d',
    title: '21 天书境共读季',
    durationDays: 21,
    milestones: [
      XiaoyoActivityMilestone(
        id: 'reading_season_60m',
        requiredSeconds: 60 * 60,
        rewardId: 'activity_glow_mark',
        rewardTitle: '微光印记',
      ),
      XiaoyoActivityMilestone(
        id: 'reading_season_180m',
        requiredSeconds: 180 * 60,
        rewardId: 'activity_formed_mark',
        rewardTitle: '成形印记',
      ),
      XiaoyoActivityMilestone(
        id: 'reading_season_360m',
        requiredSeconds: 360 * 60,
        rewardId: 'activity_resonance_mark',
        rewardTitle: '共振印记',
      ),
      XiaoyoActivityMilestone(
        id: 'reading_season_600m',
        requiredSeconds: 600 * 60,
        rewardId: 'activity_reading_honor',
        rewardTitle: '共读守页荣誉',
      ),
    ],
  );
}
