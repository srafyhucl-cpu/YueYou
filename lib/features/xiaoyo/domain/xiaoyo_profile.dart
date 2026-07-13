import 'package:yueyou/features/xiaoyo/domain/book_realm_mark.dart';
import 'package:yueyou/features/xiaoyo/domain/honor_record.dart';

/// Xiaoyo 本地 Profile V1，所有列表和映射均为业务快照而非 UI 状态。
final class XiaoyoProfile {
  static const int currentSchemaVersion = 1;

  final int schemaVersion;
  final String profileId;
  final DateTime createdAtUtc;
  final int bondXp;
  final int growthStage;
  final int validListenSeconds;
  final List<String> completedChapterKeys;
  final List<String> completedBookIds;
  final List<BookRealmMark> bookRealmMarks;
  final List<HonorRecord> unlockedHonors;
  final Map<String, int> activityProgress;
  final String selectedAppearanceId;
  final List<String> lastAppliedEventIds;
  final DateTime updatedAtUtc;

  const XiaoyoProfile({
    required this.schemaVersion,
    required this.profileId,
    required this.createdAtUtc,
    required this.bondXp,
    required this.growthStage,
    required this.validListenSeconds,
    required this.completedChapterKeys,
    required this.completedBookIds,
    required this.bookRealmMarks,
    required this.unlockedHonors,
    required this.activityProgress,
    required this.selectedAppearanceId,
    required this.lastAppliedEventIds,
    required this.updatedAtUtc,
  });

  factory XiaoyoProfile.empty({DateTime? nowUtc}) {
    final now = (nowUtc ?? DateTime.now()).toUtc();
    return XiaoyoProfile(
      schemaVersion: currentSchemaVersion,
      profileId: 'local-profile',
      createdAtUtc: now,
      bondXp: 0,
      growthStage: 0,
      validListenSeconds: 0,
      completedChapterKeys: const [],
      completedBookIds: const [],
      bookRealmMarks: const [],
      unlockedHonors: const [],
      activityProgress: const {},
      selectedAppearanceId: 'base',
      lastAppliedEventIds: const [],
      updatedAtUtc: now,
    );
  }

  XiaoyoProfile copyWith({
    int? bondXp,
    int? growthStage,
    int? validListenSeconds,
    List<String>? completedChapterKeys,
    List<String>? completedBookIds,
    List<BookRealmMark>? bookRealmMarks,
    List<HonorRecord>? unlockedHonors,
    Map<String, int>? activityProgress,
    String? selectedAppearanceId,
    List<String>? lastAppliedEventIds,
    DateTime? updatedAtUtc,
  }) =>
      XiaoyoProfile(
        schemaVersion: schemaVersion,
        profileId: profileId,
        createdAtUtc: createdAtUtc,
        bondXp: bondXp ?? this.bondXp,
        growthStage: growthStage ?? this.growthStage,
        validListenSeconds: validListenSeconds ?? this.validListenSeconds,
        completedChapterKeys: completedChapterKeys ?? this.completedChapterKeys,
        completedBookIds: completedBookIds ?? this.completedBookIds,
        bookRealmMarks: bookRealmMarks ?? this.bookRealmMarks,
        unlockedHonors: unlockedHonors ?? this.unlockedHonors,
        activityProgress: activityProgress ?? this.activityProgress,
        selectedAppearanceId: selectedAppearanceId ?? this.selectedAppearanceId,
        lastAppliedEventIds: lastAppliedEventIds ?? this.lastAppliedEventIds,
        updatedAtUtc: (updatedAtUtc ?? this.updatedAtUtc).toUtc(),
      );

  Map<String, dynamic> toJson() => {
        'schemaVersion': schemaVersion,
        'profileId': profileId,
        'createdAtUtc': createdAtUtc.toUtc().toIso8601String(),
        'bondXp': bondXp,
        'growthStage': growthStage,
        'validListenSeconds': validListenSeconds,
        'completedChapterKeys': completedChapterKeys,
        'completedBookIds': completedBookIds,
        'bookRealmMarks': bookRealmMarks.map((mark) => mark.toJson()).toList(),
        'unlockedHonors':
            unlockedHonors.map((honor) => honor.toJson()).toList(),
        'activityProgress': activityProgress,
        'selectedAppearanceId': selectedAppearanceId,
        'lastAppliedEventIds': lastAppliedEventIds,
        'updatedAtUtc': updatedAtUtc.toUtc().toIso8601String(),
      };

  factory XiaoyoProfile.fromJson(Map<String, dynamic> json) {
    final created = DateTime.tryParse(json['createdAtUtc'] as String? ?? '');
    final updated = DateTime.tryParse(json['updatedAtUtc'] as String? ?? '');
    final marks = (json['bookRealmMarks'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(BookRealmMark.fromJson)
        .where((mark) => mark.bookId.isNotEmpty)
        .toList();
    final honors = (json['unlockedHonors'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(HonorRecord.fromJson)
        .where((honor) => honor.honorId.isNotEmpty)
        .toList();
    return XiaoyoProfile(
      schemaVersion: (json['schemaVersion'] as num?)?.toInt() ?? 1,
      profileId: json['profileId'] as String? ?? 'local-profile',
      createdAtUtc: created?.toUtc() ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      bondXp: (json['bondXp'] as num?)?.toInt() ?? 0,
      growthStage: (json['growthStage'] as num?)?.toInt() ?? 0,
      validListenSeconds: (json['validListenSeconds'] as num?)?.toInt() ?? 0,
      completedChapterKeys:
          (json['completedChapterKeys'] as List<dynamic>? ?? const [])
              .whereType<String>()
              .toList(),
      completedBookIds: (json['completedBookIds'] as List<dynamic>? ?? const [])
          .whereType<String>()
          .toList(),
      bookRealmMarks: marks,
      unlockedHonors: honors,
      activityProgress:
          (json['activityProgress'] as Map<dynamic, dynamic>? ?? {}).map(
        (key, value) => MapEntry(key.toString(), (value as num).toInt()),
      ),
      selectedAppearanceId: json['selectedAppearanceId'] as String? ?? 'base',
      lastAppliedEventIds:
          (json['lastAppliedEventIds'] as List<dynamic>? ?? const [])
              .whereType<String>()
              .toList(),
      updatedAtUtc: updated?.toUtc() ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    );
  }
}
