/// 一条永久荣誉记录。
final class HonorRecord {
  final String honorId;
  final DateTime unlockedAtUtc;
  final String sourceEventId;
  final String rulesVersion;
  final String resourceId;

  const HonorRecord({
    required this.honorId,
    required this.unlockedAtUtc,
    required this.sourceEventId,
    required this.rulesVersion,
    required this.resourceId,
  });

  Map<String, dynamic> toJson() => {
        'honorId': honorId,
        'unlockedAtUtc': unlockedAtUtc.toUtc().toIso8601String(),
        'sourceEventId': sourceEventId,
        'rulesVersion': rulesVersion,
        'resourceId': resourceId,
      };

  factory HonorRecord.fromJson(Map<String, dynamic> json) => HonorRecord(
        honorId: json['honorId'] as String? ?? '',
        unlockedAtUtc: DateTime.tryParse(
              json['unlockedAtUtc'] as String? ?? '',
            )?.toUtc() ??
            DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
        sourceEventId: json['sourceEventId'] as String? ?? '',
        rulesVersion: json['rulesVersion'] as String? ?? 'v1',
        resourceId: json['resourceId'] as String? ?? 'base',
      );
}
