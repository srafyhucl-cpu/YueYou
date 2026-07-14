import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:yueyou/features/xiaoyo/domain/xiaoyo_profile.dart';
import 'package:yueyou/features/xiaoyo/services/xiaoyo_backup_codec.dart';
import 'package:yueyou/features/xiaoyo/services/xiaoyo_profile_transfer_service.dart';

final class _FakeTransferPicker implements XiaoyoProfileTransferFilePicker {
  String? savedContent;
  String? importedContent;
  String? savedPath = 'D:/exports/xiaoyo-profile-v1.json';

  @override
  Future<String?> saveJson({
    required String fileName,
    required String content,
  }) async {
    savedContent = content;
    return savedPath;
  }

  @override
  Future<String?> readJson() async => importedContent;
}

void main() {
  test('导出生成带校验和的 Profile JSON，不包含正文字段', () async {
    final picker = _FakeTransferPicker();
    final service = XiaoyoProfileTransferService(filePicker: picker);

    final result = await service.exportProfile(
      XiaoyoProfile.empty(nowUtc: DateTime.utc(2026, 7, 14)),
    );

    expect(result.status, XiaoyoTransferStatus.completed);
    expect(result.path, 'D:/exports/xiaoyo-profile-v1.json');
    final decoded = jsonDecode(picker.savedContent!) as Map<String, dynamic>;
    expect(XiaoyoBackupCodec().decode(decoded).profileId, 'local-profile');
    expect(decoded.containsKey('content'), isFalse);
    expect(decoded.containsKey('path'), isFalse);
  });

  test('用户取消导出或导入时返回 cancelled', () async {
    final picker = _FakeTransferPicker()..savedPath = null;
    final service = XiaoyoProfileTransferService(filePicker: picker);

    final exportResult = await service.exportProfile(XiaoyoProfile.empty());
    final importResult = await service.importProfile();

    expect(exportResult.status, XiaoyoTransferStatus.cancelled);
    expect(importResult.status, XiaoyoTransferStatus.cancelled);
  });

  test('导入校验和正确的文件并拒绝损坏文件', () async {
    final picker = _FakeTransferPicker();
    final codec = const XiaoyoBackupCodec();
    picker.importedContent = jsonEncode(
      codec.encode(XiaoyoProfile.empty(nowUtc: DateTime.utc(2026, 7, 14))),
    );
    final service = XiaoyoProfileTransferService(filePicker: picker);

    final valid = await service.importProfile();
    picker.importedContent = '{bad json';
    final invalid = await service.importProfile();

    expect(valid.status, XiaoyoTransferStatus.completed);
    expect(valid.profile?.schemaVersion, XiaoyoProfile.currentSchemaVersion);
    expect(invalid.status, XiaoyoTransferStatus.failed);
    expect(invalid.profile, isNull);
  });
}
