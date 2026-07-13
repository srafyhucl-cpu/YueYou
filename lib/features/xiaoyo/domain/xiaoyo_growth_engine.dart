import 'package:yueyou/features/xiaoyo/domain/book_realm_mark.dart';
import 'package:yueyou/features/xiaoyo/domain/activity_definition.dart';
import 'package:yueyou/features/xiaoyo/domain/honor_definition.dart';
import 'package:yueyou/features/xiaoyo/domain/honor_record.dart';
import 'package:yueyou/features/xiaoyo/domain/xiaoyo_activity_event.dart';
import 'package:yueyou/features/xiaoyo/domain/xiaoyo_completion_event.dart';
import 'package:yueyou/features/xiaoyo/domain/xiaoyo_event.dart';
import 'package:yueyou/features/xiaoyo/domain/xiaoyo_listen_events.dart';
import 'package:yueyou/features/xiaoyo/domain/xiaoyo_profile.dart';

/// 一次领域事件应用结果。
final class XiaoyoGrowthResult {
  final XiaoyoProfile profile;
  final bool applied;
  final List<String> unlockedHonorIds;
  final List<String> reachedActivityMilestones;

  const XiaoyoGrowthResult({
    required this.profile,
    required this.applied,
    required this.unlockedHonorIds,
    this.reachedActivityMilestones = const [],
  });
}

/// 按首版规则计算成长、印记和永久荣誉。
final class XiaoyoGrowthEngine {
  static const int _maxHeartbeatSeconds = 90;
  static const int _eventWindowSize = 256;
  static const String _rulesVersion = 'v1';

  /// 应用单个事件；重复事件返回原 Profile，不产生副作用。
  XiaoyoGrowthResult apply(XiaoyoProfile profile, XiaoyoEvent event) {
    if (event.eventId.isEmpty ||
        profile.lastAppliedEventIds.contains(event.eventId)) {
      return XiaoyoGrowthResult(
        profile: profile,
        applied: false,
        unlockedHonorIds: const [],
      );
    }
    if (event is ListenHeartbeat &&
        (event.advancedSeconds <= 0 ||
            event.advancedSeconds > _maxHeartbeatSeconds)) {
      return XiaoyoGrowthResult(
        profile: profile,
        applied: false,
        unlockedHonorIds: const [],
      );
    }

    final next = switch (event) {
      ListenHeartbeat() => _applyHeartbeat(profile, event),
      ChapterCompleted() => _applyChapter(profile, event),
      BookCompleted() => _applyBook(profile, event),
      ActivityProgressRecorded() => _applyActivity(profile, event),
      _ => profile,
    };
    final withEvent = _rememberEvent(next, event.eventId);
    final refreshed = _refreshGrowthAndHonors(withEvent, event);
    final unlocked = refreshed.unlockedHonors
        .where(
          (honor) => !profile.unlockedHonors.any(
            (existing) => existing.honorId == honor.honorId,
          ),
        )
        .map((honor) => honor.honorId)
        .toList();
    final reachedMilestones = _activityMilestonesCrossed(profile, refreshed);
    return XiaoyoGrowthResult(
      profile: refreshed,
      applied: true,
      unlockedHonorIds: unlocked,
      reachedActivityMilestones: reachedMilestones,
    );
  }

  XiaoyoProfile _applyHeartbeat(
    XiaoyoProfile profile,
    ListenHeartbeat event,
  ) {
    final previousSeconds = profile.validListenSeconds;
    final seconds = previousSeconds + event.advancedSeconds;
    final xp = profile.bondXp + seconds ~/ 60 - previousSeconds ~/ 60;
    final marks = _updateMark(
      profile.bookRealmMarks,
      bookId: event.bookId,
      title: event.bookTitle,
      progressPercent: event.progressPercent,
      addedSeconds: event.advancedSeconds,
      completedAtUtc: null,
    );
    final activity = _addActivitySeconds(
      profile.activityProgress,
      XiaoyoActivityDefinitions.readingSeason.id,
      event.advancedSeconds,
    );
    return profile.copyWith(
      bondXp: xp,
      validListenSeconds: seconds,
      bookRealmMarks: marks,
      activityProgress: activity,
      updatedAtUtc: _eventTime(profile, event),
    );
  }

  XiaoyoProfile _applyActivity(
    XiaoyoProfile profile,
    ActivityProgressRecorded event,
  ) {
    if (event.activityId != XiaoyoActivityDefinitions.readingSeason.id ||
        event.addedSeconds <= 0 ||
        event.addedSeconds > _maxHeartbeatSeconds) {
      return profile;
    }
    return profile.copyWith(
      activityProgress: _addActivitySeconds(
        profile.activityProgress,
        event.activityId,
        event.addedSeconds,
      ),
      updatedAtUtc: _eventTime(profile, event),
    );
  }

  Map<String, int> _addActivitySeconds(
    Map<String, int> current,
    String activityId,
    int addedSeconds,
  ) =>
      {
        ...current,
        activityId: (current[activityId] ?? 0) + addedSeconds,
      };

  XiaoyoProfile _applyChapter(
    XiaoyoProfile profile,
    ChapterCompleted event,
  ) {
    final key = '${event.bookId}:${event.chapterKey}';
    if (profile.completedChapterKeys.contains(key)) return profile;
    return profile.copyWith(
      bondXp: profile.bondXp + 3,
      completedChapterKeys: [...profile.completedChapterKeys, key],
      updatedAtUtc: _eventTime(profile, event),
    );
  }

  XiaoyoProfile _applyBook(
    XiaoyoProfile profile,
    BookCompleted event,
  ) {
    if (profile.completedBookIds.contains(event.bookId)) return profile;
    final marks = _updateMark(
      profile.bookRealmMarks,
      bookId: event.bookId,
      title: event.bookTitle,
      progressPercent: 100.0,
      addedSeconds: 0,
      completedAtUtc: _eventTime(profile, event),
    );
    return profile.copyWith(
      bondXp: profile.bondXp + 60,
      completedBookIds: [...profile.completedBookIds, event.bookId],
      bookRealmMarks: marks,
      updatedAtUtc: _eventTime(profile, event),
    );
  }

  List<BookRealmMark> _updateMark(
    List<BookRealmMark> current, {
    required String bookId,
    required String title,
    required double progressPercent,
    required int addedSeconds,
    required DateTime? completedAtUtc,
  }) {
    if (bookId.isEmpty) return current;
    final index = current.indexWhere((mark) => mark.bookId == bookId);
    final old = index == -1 ? null : current[index];
    final safeProgress = progressPercent.clamp(0.0, 100.0).toDouble();
    final candidate = BookRealmMarkLevel.values.reversed.firstWhere(
      (level) => safeProgress >= level.thresholdPercent,
      orElse: () => BookRealmMarkLevel.none,
    );
    final level = old == null || candidate.index > old.level.index
        ? candidate
        : old.level;
    final mark = (old ??
            BookRealmMark(
              bookId: bookId,
              titleSnapshot: title,
              level: BookRealmMarkLevel.none,
              completedAtUtc: null,
              validListenSeconds: 0,
              visualSeed: _visualSeed(bookId),
            ))
        .copyWith(
      titleSnapshot: title.isEmpty ? null : title,
      level: level,
      completedAtUtc: completedAtUtc,
      validListenSeconds: (old?.validListenSeconds ?? 0) + addedSeconds,
    );
    final result = [...current];
    if (index == -1) {
      result.add(mark);
    } else {
      result[index] = mark;
    }
    return result;
  }

  XiaoyoProfile _rememberEvent(XiaoyoProfile profile, String eventId) {
    final ids = [...profile.lastAppliedEventIds, eventId];
    final start =
        ids.length > _eventWindowSize ? ids.length - _eventWindowSize : 0;
    return profile.copyWith(lastAppliedEventIds: ids.sublist(start));
  }

  XiaoyoProfile _refreshGrowthAndHonors(
    XiaoyoProfile profile,
    XiaoyoEvent event,
  ) {
    final stage = _growthStage(profile);
    var refreshed = profile.copyWith(growthStage: stage);
    final time = _eventTime(profile, event);
    final honors = <HonorRecord>[...refreshed.unlockedHonors];

    void unlock(String id) {
      if (honors.any((honor) => honor.honorId == id)) return;
      honors.add(
        HonorRecord(
          honorId: id,
          unlockedAtUtc: time,
          sourceEventId: event.eventId,
          rulesVersion: _rulesVersion,
          resourceId: 'base',
        ),
      );
    }

    final books = refreshed.completedBookIds.length;
    if (books >= 1) unlock(XiaoyoHonorIds.firstBook);
    if (books >= 5) unlock(XiaoyoHonorIds.fifthBook);
    if (books >= 10) unlock(XiaoyoHonorIds.tenthBook);
    final seconds = refreshed.validListenSeconds;
    if (seconds >= 10 * 60 * 60) unlock(XiaoyoHonorIds.tenHours);
    if (seconds >= 50 * 60 * 60) unlock(XiaoyoHonorIds.fiftyHours);
    if (seconds >= 100 * 60 * 60) unlock(XiaoyoHonorIds.oneHundredHours);
    if (stage >= 2) unlock(XiaoyoHonorIds.companion);
    if (stage >= 3) unlock(XiaoyoHonorIds.guardian);
    if (stage >= 4) unlock(XiaoyoHonorIds.resonance);
    final activitySeconds = refreshed
            .activityProgress[XiaoyoActivityDefinitions.readingSeason.id] ??
        0;
    if (activitySeconds >= 600 * 60) {
      unlock(XiaoyoHonorIds.readingSeason);
    }
    refreshed = refreshed.copyWith(unlockedHonors: honors);
    return refreshed;
  }

  List<String> _activityMilestonesCrossed(
    XiaoyoProfile before,
    XiaoyoProfile after,
  ) {
    const definition = XiaoyoActivityDefinitions.readingSeason;
    final oldSeconds = before.activityProgress[definition.id] ?? 0;
    final newSeconds = after.activityProgress[definition.id] ?? 0;
    return definition.milestones
        .where(
          (milestone) =>
              oldSeconds < milestone.requiredSeconds &&
              newSeconds >= milestone.requiredSeconds,
        )
        .map((milestone) => milestone.id)
        .toList();
  }

  int _growthStage(XiaoyoProfile profile) {
    final xp = profile.bondXp;
    final books = profile.completedBookIds.length;
    if (xp >= 7200 && books >= 10) return 4;
    if (xp >= 2400 && books >= 3) return 3;
    if (xp >= 600 && books >= 1) return 2;
    if (xp >= 60) return 1;
    return 0;
  }

  DateTime _eventTime(XiaoyoProfile profile, XiaoyoEvent event) {
    final occurred = event.occurredAtUtc.toUtc();
    return occurred.isAfter(profile.updatedAtUtc)
        ? occurred
        : profile.updatedAtUtc;
  }

  int _visualSeed(String value) {
    var hash = 2166136261;
    for (final codeUnit in value.codeUnits) {
      hash = (hash ^ codeUnit) * 16777619;
      hash &= 0x7fffffff;
    }
    return hash;
  }
}
