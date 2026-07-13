import 'package:yueyou/features/xiaoyo/domain/activity_definition.dart';

/// 一个本地累计活动在当前 Profile 下的只读进度投影。
final class XiaoyoActivityProgress {
  final XiaoyoActivityDefinition definition;
  final int accumulatedSeconds;
  final int targetSeconds;
  final double progress;
  final List<XiaoyoActivityMilestone> reachedMilestones;
  final XiaoyoActivityMilestone? nextMilestone;

  const XiaoyoActivityProgress({
    required this.definition,
    required this.accumulatedSeconds,
    required this.targetSeconds,
    required this.progress,
    required this.reachedMilestones,
    required this.nextMilestone,
  });

  /// 根据本地累计秒数生成活动展示投影，不修改原始 Profile。
  factory XiaoyoActivityProgress.from({
    required XiaoyoActivityDefinition definition,
    required int accumulatedSeconds,
  }) {
    final safeSeconds = accumulatedSeconds < 0 ? 0 : accumulatedSeconds;
    final declaredTarget = definition.milestones.isEmpty
        ? 0
        : definition.milestones.last.requiredSeconds;
    final targetSeconds = declaredTarget < 0 ? 0 : declaredTarget;
    final boundedSeconds =
        safeSeconds > targetSeconds ? targetSeconds : safeSeconds;
    final reached = definition.milestones
        .where((milestone) => safeSeconds >= milestone.requiredSeconds)
        .toList(growable: false);
    XiaoyoActivityMilestone? next;
    for (final milestone in definition.milestones) {
      if (safeSeconds < milestone.requiredSeconds) {
        next = milestone;
        break;
      }
    }
    return XiaoyoActivityProgress(
      definition: definition,
      accumulatedSeconds: safeSeconds,
      targetSeconds: targetSeconds,
      progress: targetSeconds == 0 ? 0 : boundedSeconds / targetSeconds,
      reachedMilestones: reached,
      nextMilestone: next,
    );
  }

  int get accumulatedMinutes => accumulatedSeconds ~/ 60;

  int get targetMinutes => targetSeconds ~/ 60;

  bool hasReached(String milestoneId) =>
      reachedMilestones.any((milestone) => milestone.id == milestoneId);
}
