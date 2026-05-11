import 'package:meta/meta.dart';

/// 服务端返回的版本信息数据类
///
/// 对应 API 响应格式：
/// ```json
/// {
///   "version": "1.2.0",
///   "buildNumber": 3,
///   "forceUpdate": false,
///   "releaseNotes": "修复了 TTS 连接偶发断线问题",
///   "downloadUrl": "https://..."
/// }
/// ```
@immutable
class UpdateInfo {
  /// 服务端最新版本号（语义化版本，如 "1.2.0"）
  final String version;

  /// 服务端最新构建号（整数，对应 buildNumber）
  final int buildNumber;

  /// 是否强制更新（true 时禁用跳过按钮）
  final bool forceUpdate;

  /// 版本更新说明（可选，用于展示给用户）
  final String releaseNotes;

  /// Android APK 下载链接（跳转应用市场或自定义页）
  final String downloadUrl;

  const UpdateInfo({
    required this.version,
    required this.buildNumber,
    required this.forceUpdate,
    this.releaseNotes = '',
    this.downloadUrl = '',
  });

  /// 从 JSON 解析（宽松策略：字段缺失时使用安全默认值，不抛异常）
  factory UpdateInfo.fromJson(Map<String, dynamic> json) {
    return UpdateInfo(
      version: json['version'] as String? ?? '0.0.0',
      buildNumber: (json['buildNumber'] as num?)?.toInt() ?? 0,
      forceUpdate: json['forceUpdate'] as bool? ?? false,
      releaseNotes: json['releaseNotes'] as String? ?? '',
      downloadUrl: json['downloadUrl'] as String? ?? '',
    );
  }

  @override
  String toString() => 'UpdateInfo(version=$version, buildNumber=$buildNumber, '
      'forceUpdate=$forceUpdate)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is UpdateInfo &&
          version == other.version &&
          buildNumber == other.buildNumber &&
          forceUpdate == other.forceUpdate;

  @override
  int get hashCode => Object.hash(version, buildNumber, forceUpdate);
}
