/// Xiaoyo 价值系统接收的本地事件基类。
abstract class XiaoyoEvent {
  final String eventId;
  final DateTime occurredAtUtc;

  const XiaoyoEvent({
    required this.eventId,
    required this.occurredAtUtc,
  });
}
