import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:yueyou/core/utils/cyber_logger.dart';
import 'package:yueyou/features/xiaoyo/domain/xiaoyo_profile.dart';
import 'package:yueyou/features/xiaoyo/services/xiaoyo_backup_codec.dart';

const int kMaxXiaoyoTransferBytes = 1024 * 1024;

/// 本地 Profile 文件转移的结果状态。
enum XiaoyoTransferStatus {
  /// 文件已成功读写。
  completed,

  /// 用户取消了系统文件选择器。
  cancelled,

  /// 文件结构、权限或读写过程失败。
  failed,
}

/// Profile 导出结果。
final class XiaoyoExportResult {
  /// 创建导出结果。
  const XiaoyoExportResult({
    required this.status,
    this.path,
    this.message,
  });

  final XiaoyoTransferStatus status;
  final String? path;
  final String? message;
}

/// Profile 导入结果。
final class XiaoyoImportResult {
  /// 创建导入结果。
  const XiaoyoImportResult({
    required this.status,
    this.profile,
    this.message,
  });

  final XiaoyoTransferStatus status;
  final XiaoyoProfile? profile;
  final String? message;
}

/// 系统文件选择器的可替换边界。
abstract interface class XiaoyoProfileTransferFilePicker {
  /// 让用户选择导出路径并写入 JSON 内容。
  Future<String?> saveJson({
    required String fileName,
    required String content,
  });

  /// 让用户选择 JSON 文件并返回其文本内容。
  Future<String?> readJson();
}

/// 使用项目现有 file_picker 依赖完成 Profile 文件转移。
final class FilePickerXiaoyoProfileTransferAdapter
    implements XiaoyoProfileTransferFilePicker {
  /// 创建系统文件选择器适配器。
  const FilePickerXiaoyoProfileTransferAdapter();

  @override
  Future<String?> saveJson({
    required String fileName,
    required String content,
  }) {
    return FilePicker.platform.saveFile(
      dialogTitle: '导出 Xiaoyo 成长数据',
      fileName: fileName,
      type: FileType.custom,
      allowedExtensions: const ['json'],
      bytes: Uint8List.fromList(utf8.encode(content)),
      lockParentWindow: true,
    );
  }

  @override
  Future<String?> readJson() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['json'],
      allowMultiple: false,
      withData: false,
      lockParentWindow: true,
    );
    if (result == null || result.files.isEmpty) return null;
    final path = result.files.single.path;
    if (path == null || path.isEmpty) return null;
    final file = File(path);
    if (await file.length() > kMaxXiaoyoTransferBytes) {
      throw const FormatException('成长数据文件超过 1 MiB 限制');
    }
    return file.readAsString();
  }
}

/// Xiaoyo Profile 的本地导出与恢复服务。
final class XiaoyoProfileTransferService {
  /// 创建文件转移服务，可注入文件选择器和校验编解码器。
  XiaoyoProfileTransferService({
    XiaoyoProfileTransferFilePicker? filePicker,
    XiaoyoBackupCodec codec = const XiaoyoBackupCodec(),
  })  : _filePicker =
            filePicker ?? const FilePickerXiaoyoProfileTransferAdapter(),
        _codec = codec;

  final XiaoyoProfileTransferFilePicker _filePicker;
  final XiaoyoBackupCodec _codec;

  /// 将本地 Profile 导出为带校验和的 JSON 文件。
  Future<XiaoyoExportResult> exportProfile(XiaoyoProfile profile) async {
    try {
      final content = jsonEncode(_codec.encode(profile));
      final path = await _filePicker.saveJson(
        fileName: 'xiaoyo-profile-v1.json',
        content: content,
      );
      if (path == null || path.isEmpty) {
        return const XiaoyoExportResult(status: XiaoyoTransferStatus.cancelled);
      }
      return XiaoyoExportResult(
        status: XiaoyoTransferStatus.completed,
        path: path,
      );
    } on Object catch (error, stackTrace) {
      CyberLogger.captureWarning(
        error,
        stack: stackTrace,
        tag: 'dashboard',
        extra: {'context': 'Xiaoyo Profile 导出失败'},
      );
      return const XiaoyoExportResult(
        status: XiaoyoTransferStatus.failed,
        message: '成长数据导出失败，请检查文件权限后重试。',
      );
    }
  }

  /// 读取并校验用户选择的 Profile 文件。
  Future<XiaoyoImportResult> importProfile() async {
    try {
      final content = await _filePicker.readJson();
      if (content == null || content.isEmpty) {
        return const XiaoyoImportResult(status: XiaoyoTransferStatus.cancelled);
      }
      if (utf8.encode(content).length > kMaxXiaoyoTransferBytes) {
        throw const FormatException('成长数据文件超过 1 MiB 限制');
      }
      final decoded = jsonDecode(content);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('成长数据根节点不是对象');
      }
      return XiaoyoImportResult(
        status: XiaoyoTransferStatus.completed,
        profile: _codec.decode(decoded),
      );
    } on Object catch (error, stackTrace) {
      CyberLogger.captureWarning(
        error,
        stack: stackTrace,
        tag: 'dashboard',
        extra: {'context': 'Xiaoyo Profile 导入失败'},
      );
      return const XiaoyoImportResult(
        status: XiaoyoTransferStatus.failed,
        message: '成长数据无效或已损坏，当前数据没有改变。',
      );
    }
  }
}
