import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yueyou/features/xiaoyo/domain/xiaoyo_event.dart';
import 'package:yueyou/features/xiaoyo/domain/xiaoyo_profile.dart';
import 'package:yueyou/features/xiaoyo/domain/xiaoyo_repository.dart';
import 'package:yueyou/features/xiaoyo/providers/xiaoyo_profile_notifier.dart';

class _MemoryRepository implements XiaoyoRepository {
  XiaoyoProfile profile = XiaoyoProfile.empty(
    nowUtc: DateTime.utc(2026, 7, 13),
  );

  @override
  Future<XiaoyoProfile> load() async => profile;

  @override
  Future<void> save(XiaoyoProfile value) async => profile = value;

  @override
  Future<XiaoyoExportBundle> exportBundle() async =>
      XiaoyoExportBundle(profile);

  @override
  Future<XiaoyoProfile> importBundle(XiaoyoExportBundle bundle) async {
    profile = bundle.profile;
    return profile;
  }
}

class _ProbeEvent extends XiaoyoEvent {
  _ProbeEvent()
      : super(
          eventId: 'probe',
          occurredAtUtc: DateTime.utc(2026, 7, 13),
        );
}

void main() {
  test('Profile Provider 可通过 Repository override 且不把领域规则放进 UI', () async {
    final repository = _MemoryRepository();
    final container = ProviderContainer(
      overrides: [xiaoyoRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);

    final loaded = await container.read(xiaoyoProfileProvider.future);
    final result = await container
        .read(xiaoyoProfileProvider.notifier)
        .applyEvent(_ProbeEvent());

    expect(loaded.profileId, 'local-profile');
    expect(result?.applied, isTrue);
    expect(repository.profile.lastAppliedEventIds, contains('probe'));
  });

  test('replaceProfile 写入导入快照并刷新 Provider 状态', () async {
    final repository = _MemoryRepository();
    final container = ProviderContainer(
      overrides: [xiaoyoRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);

    await container.read(xiaoyoProfileProvider.future);
    final imported = repository.profile.copyWith(
      bondXp: 128,
      growthStage: 2,
    );
    final replaced = await container
        .read(xiaoyoProfileProvider.notifier)
        .replaceProfile(imported);

    expect(replaced, isTrue);
    expect(repository.profile.bondXp, 128);
    expect(container.read(xiaoyoProfileProvider).value?.growthStage, 2);
  });
}
