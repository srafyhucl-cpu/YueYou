import 'package:yueyou/features/xiaoyo/domain/xiaoyo_event.dart';

/// 手动或离线恢复时补记活动累计时长的本地事件。
final class ActivityProgressRecorded extends XiaoyoEvent {
  final String activityId;
  final int addedSeconds;

  const ActivityProgressRecorded({
    required super.eventId,
    required super.occurredAtUtc,
    required this.activityId,
    required this.addedSeconds,
  });
}
