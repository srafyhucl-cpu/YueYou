import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yueyou/features/xiaoyo/domain/xiaoyo_profile.dart';
import 'package:yueyou/features/xiaoyo/services/xiaoyo_backup_codec.dart';
import 'package:yueyou/features/xiaoyo/services/xiaoyo_local_repository.dart';

void main() {
  late Directory root;

  setUp(() async {
    root = Directory('D:/Temp/yueyou_xiaoyo_profile_test');
    await root.create(recursive: true);
    await _deleteIfExists(File('${root.path}/xiaoyo/profile_v1.json'));
    await _deleteIfExists(File('${root.path}/xiaoyo/profile_v1.json.bak'));
    await _deleteIfExists(File('${root.path}/xiaoyo/profile_v1.json.tmp'));
  });

  tearDown(() async {
    final directory = Directory('${root.path}/xiaoyo');
    await _deleteIfExists(File('${directory.path}/profile_v1.json'));
    await _deleteIfExists(File('${directory.path}/profile_v1.json.bak'));
    await _deleteIfExists(File('${directory.path}/profile_v1.json.tmp'));
    if (await directory.exists()) await directory.delete();
    if (await root.exists()) await root.delete();
  });

  test('Profile 主文件、备份文件和校验和可往返', () async {
    final repository = XiaoyoLocalRepository(
      documentsDirectory: () async => root,
    );
    final profile = XiaoyoProfile.empty(
      nowUtc: DateTime.utc(2026, 7, 13),
    ).copyWith(bondXp: 60);

    await repository.save(profile);

    final loaded = await repository.load();
    expect(loaded.bondXp, 60);
    expect(loaded.profileId, 'local-profile');
  });

  test('主文件损坏时回退到上一份备份，双份损坏时回到空 Profile', () async {
    final repository = XiaoyoLocalRepository(
      documentsDirectory: () async => root,
    );
    final first = XiaoyoProfile.empty(
      nowUtc: DateTime.utc(2026, 7, 13),
    ).copyWith(bondXp: 10);
    final second = first.copyWith(bondXp: 20);

    await repository.save(first);
    await repository.save(second);
    await File('${root.path}/xiaoyo/profile_v1.json')
        .writeAsString('{"broken":true}');

    expect((await repository.load()).bondXp, 10);

    await File('${root.path}/xiaoyo/profile_v1.json.bak')
        .writeAsString('{"broken":true}');
    expect((await repository.load()).bondXp, 0);
  });

  test('校验和被篡改时编解码器拒绝数据', () {
    const codec = XiaoyoBackupCodec();
    final envelope = codec.encode(XiaoyoProfile.empty(
      nowUtc: DateTime.utc(2026, 7, 13),
    ));
    envelope['checksum'] = '00000000';

    expect(() => codec.decode(envelope), throwsFormatException);
  });
}

Future<void> _deleteIfExists(File file) async {
  if (await file.exists()) await file.delete();
}
