import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:yueyou/core/utils/cyber_logger.dart';
import 'package:yueyou/features/xiaoyo/domain/xiaoyo_profile.dart';
import 'package:yueyou/features/xiaoyo/domain/xiaoyo_repository.dart';
import 'package:yueyou/features/xiaoyo/services/xiaoyo_backup_codec.dart';

/// Xiaoyo Profile 的本地文件实现，独立于全局 StorageService。
class XiaoyoLocalRepository implements XiaoyoRepository {
  static const String _profileDirectory = 'xiaoyo';
  static const String _profileFile = 'profile_v1.json';
  static const String _backupFile = 'profile_v1.json.bak';
  static const String _tempFile = 'profile_v1.json.tmp';

  final Future<Directory> Function() _documentsDirectory;
  final XiaoyoBackupCodec _codec;

  XiaoyoLocalRepository({
    Future<Directory> Function()? documentsDirectory,
    XiaoyoBackupCodec codec = const XiaoyoBackupCodec(),
  })  : _documentsDirectory =
            documentsDirectory ?? getApplicationDocumentsDirectory,
        _codec = codec;

  @override
  Future<XiaoyoProfile> load() async {
    final files = await _files();
    for (final file in <File>[files.primary, files.backup]) {
      if (!await file.exists()) continue;
      try {
        final raw = jsonDecode(await file.readAsString());
        if (raw is! Map<String, dynamic>) {
          throw const FormatException('Profile 根节点不是对象');
        }
        return _codec.decode(raw);
      } catch (error, stackTrace) {
        CyberLogger.captureWarning(
          error,
          stack: stackTrace,
          tag: 'dashboard',
          extra: {'context': 'Xiaoyo Profile 文件读取失败'},
        );
      }
    }
    return XiaoyoProfile.empty();
  }

  @override
  Future<void> save(XiaoyoProfile profile) async {
    final files = await _files();
    final encoded = jsonEncode(_codec.encode(profile));
    try {
      await files.temp.writeAsString(encoded, flush: true);
      if (await files.primary.exists()) {
        if (await files.backup.exists()) await files.backup.delete();
        await files.primary.copy(files.backup.path);
        await files.primary.delete();
      }
      await files.temp.rename(files.primary.path);
    } catch (error, stackTrace) {
      CyberLogger.captureWarning(
        error,
        stack: stackTrace,
        tag: 'dashboard',
        extra: {'context': 'Xiaoyo Profile 原子写入失败'},
      );
      if (await files.temp.exists()) await files.temp.delete();
      rethrow;
    }
  }

  @override
  Future<XiaoyoExportBundle> exportBundle() async =>
      XiaoyoExportBundle(await load());

  @override
  Future<XiaoyoProfile> importBundle(XiaoyoExportBundle bundle) async {
    await save(bundle.profile);
    return bundle.profile;
  }

  Future<_XiaoyoFiles> _files() async {
    final documents = await _documentsDirectory();
    final directory = Directory('${documents.path}/$_profileDirectory');
    await directory.create(recursive: true);
    return _XiaoyoFiles(
      primary: File('${directory.path}/$_profileFile'),
      backup: File('${directory.path}/$_backupFile'),
      temp: File('${directory.path}/$_tempFile'),
    );
  }
}

class _XiaoyoFiles {
  final File primary;
  final File backup;
  final File temp;

  const _XiaoyoFiles({
    required this.primary,
    required this.backup,
    required this.temp,
  });
}
