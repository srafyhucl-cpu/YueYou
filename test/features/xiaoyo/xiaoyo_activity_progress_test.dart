import 'package:flutter_test/flutter_test.dart';
import 'package:yueyou/features/xiaoyo/domain/activity_definition.dart';
import 'package:yueyou/features/xiaoyo/domain/xiaoyo_activity_progress.dart';

void main() {
  const activity = XiaoyoActivityDefinitions.readingSeason;

  test('活动进度从零开始时只显示第一个待解锁里程碑', () {
    final progress = XiaoyoActivityProgress.from(
      definition: activity,
      accumulatedSeconds: 0,
    );

    expect(progress.accumulatedMinutes, 0);
    expect(progress.targetMinutes, 600);
    expect(progress.progress, 0);
    expect(progress.reachedMilestones, isEmpty);
    expect(progress.nextMilestone?.id, 'reading_season_60m');
  });

  test('活动进度跨过多个门槛时只投影已达到的里程碑', () {
    final progress = XiaoyoActivityProgress.from(
      definition: activity,
      accumulatedSeconds: 360 * 60,
    );

    expect(
      progress.reachedMilestones.map((milestone) => milestone.id),
      <String>[
        'reading_season_60m',
        'reading_season_180m',
        'reading_season_360m',
      ],
    );
    expect(progress.nextMilestone?.id, 'reading_season_600m');
    expect(progress.progress, closeTo(0.6, 0.0001));
    expect(progress.hasReached('reading_season_360m'), isTrue);
    expect(progress.hasReached('reading_season_600m'), isFalse);
  });

  test('负数和超过目标的累计值均被限制在合法展示范围', () {
    final negative = XiaoyoActivityProgress.from(
      definition: activity,
      accumulatedSeconds: -1,
    );
    final complete = XiaoyoActivityProgress.from(
      definition: activity,
      accumulatedSeconds: 999999,
    );

    expect(negative.accumulatedSeconds, 0);
    expect(negative.progress, 0);
    expect(complete.progress, 1);
    expect(complete.reachedMilestones, hasLength(4));
    expect(complete.nextMilestone, isNull);
  });
}
