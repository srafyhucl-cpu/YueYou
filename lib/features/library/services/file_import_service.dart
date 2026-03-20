import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:gbk_codec/gbk_codec.dart';

class FileImportService {
  static Future<String?> importTxtFile() async {
    final FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['txt'],
      allowMultiple: false,
      withData: false,
      lockParentWindow: true,
    );

    if (result == null || result.files.isEmpty) {
      return null;
    }

    final PlatformFile pickedFile = result.files.single;
    final String? filePath = pickedFile.path;
    if (filePath == null || filePath.isEmpty) {
      throw const FileSystemException('无法读取所选 TXT 文件路径');
    }

    final Uint8List rawBytes = await File(filePath).readAsBytes();
    return _decodeText(rawBytes);
  }

  static String _decodeText(Uint8List bytes) {
    try {
      return const Utf8Decoder(allowMalformed: false).convert(bytes);
    } catch (_) {
      try {
        return gbk.decode(bytes);
      } catch (_) {
        throw const FormatException('TXT 编码解析失败，仅支持 UTF-8 / GBK / GB18030');
      }
    }
  }
}
