import 'dart:convert';

import 'package:yueyou/features/xiaoyo/domain/xiaoyo_profile.dart';

/// Profile 文件的校验和编解码器。
class XiaoyoBackupCodec {
  const XiaoyoBackupCodec();

  Map<String, dynamic> encode(XiaoyoProfile profile) {
    final payload = profile.toJson();
    return {
      'profile': payload,
      'checksum': _checksum(jsonEncode(payload)),
    };
  }

  XiaoyoProfile decode(Map<String, dynamic> envelope) {
    final payload = envelope['profile'];
    final checksum = envelope['checksum'];
    if (payload is! Map<String, dynamic> || checksum is! String) {
      throw const FormatException('Xiaoyo Profile 文件结构无效');
    }
    final encoded = jsonEncode(payload);
    if (_checksum(encoded) != checksum) {
      throw const FormatException('Xiaoyo Profile 校验和不匹配');
    }
    final profile = XiaoyoProfile.fromJson(payload);
    if (profile.schemaVersion != XiaoyoProfile.currentSchemaVersion) {
      throw const FormatException('Xiaoyo Profile 版本不受支持');
    }
    return profile;
  }

  String _checksum(String value) {
    var hash = 2166136261;
    for (final codeUnit in utf8.encode(value)) {
      hash = (hash ^ codeUnit) * 16777619;
      hash &= 0x7fffffff;
    }
    return hash.toRadixString(16).padLeft(8, '0');
  }
}
