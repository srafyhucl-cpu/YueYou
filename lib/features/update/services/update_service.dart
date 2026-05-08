import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:yueyou/core/utils/cyber_logger.dart';

import 'package:yueyou/features/update/domain/update_info.dart';

/// 热更新版本检测服务
///
/// ## 工作流程
/// 1. 通过 `PackageInfo.fromPlatform()` 获取本地版本信息
/// 2. 向 `_versionApi` 发送 GET 请求，获取服务端最新版本
/// 3. 对比本地与服务端的 buildNumber（更精确，不受多位语义版本影响）
/// 4. 若服务端版本较新，返回 [UpdateInfo]；否则返回 null
///
/// ## 版本对比策略
/// 优先以 `buildNumber` 整数对比（简单可靠）；
/// 若服务端响应无 `buildNumber`，退级为语义版本字符串对比。
///
/// ## API 接口约定
/// - 请求：`GET https://<host>/version`（无鉴权，公开端点）
/// - 响应 200 + JSON：
///   ```json
///   {"version":"1.2.0","buildNumber":3,"forceUpdate":false,
///    "releaseNotes":"...","downloadUrl":"https://..."}
///   ```
/// - 超时：5 秒（网络异常时静默降级，不中断用户）
///
/// ## 注入方式
/// API URL 通过 `--dart-define=UPDATE_API_URL=https://...` 注入，
/// 默认为空字符串（开发环境不发请求）。
class UpdateService {
  UpdateService._();

  /// 编译时注入的版本检测 API URL
  static const String _versionApi = String.fromEnvironment(
    'UPDATE_API_URL',
    defaultValue: '',
  );

  /// 版本请求超时时间
  static const Duration _timeout = Duration(seconds: 5);

  // ── 公开接口 ──────────────────────────────────────────────────────────────

  /// 检测是否有可用更新
  ///
  /// - 返回 [UpdateInfo]：存在更新（版本号大于本地）
  /// - 返回 `null`：无更新、API 未配置或请求失败（静默降级）
  static Future<UpdateInfo?> checkForUpdate() async {
    if (_versionApi.isEmpty) {
      return null;
    }

    try {
      final response = await http.get(Uri.parse(_versionApi)).timeout(_timeout);

      if (response.statusCode != 200) {
        CyberLogger.captureWarning(
          StateError('版本检测接口返回异常'),
          tag: 'update',
          extra: {
            'context': '版本检测 HTTP 响应',
            'statusCode': response.statusCode.toString(),
          },
        );
        return null;
      }

      final Map<String, dynamic> json =
          jsonDecode(response.body) as Map<String, dynamic>;
      final remote = UpdateInfo.fromJson(json);
      final local = await _getLocalVersion();

      if (_isNewerVersion(remote, local)) {
        CyberLogger.captureMessage(
          '发现新版本: remote=${remote.version}, local=${local.version}',
          tag: 'update',
        );
        return remote;
      }

      CyberLogger.captureMessage('当前已是最新版本: ${local.version}', tag: 'update');
      return null;
    } on Exception catch (e, stack) {
      // 网络异常、JSON 解析异常均静默降级，不影响用户体验
      CyberLogger.captureWarning(
        e,
        stack: stack,
        tag: 'update',
        extra: {'context': '版本检测异常，已静默降级'},
      );
      return null;
    }
  }

  // ── 内部工具 ──────────────────────────────────────────────────────────────

  /// 获取本地安装版本信息（仅读取，无副作用）
  static Future<UpdateInfo> _getLocalVersion() async {
    final info = await PackageInfo.fromPlatform();
    final buildNum = int.tryParse(info.buildNumber) ?? 0;
    return UpdateInfo(
      version: info.version,
      buildNumber: buildNum,
      forceUpdate: false,
    );
  }

  /// 判断 [remote] 版本是否比 [local] 更新
  ///
  /// 优先比较 buildNumber（整数，精确）；
  /// buildNumber 均为 0 时退级为语义版本字符串比较。
  static bool isNewerVersion(UpdateInfo remote, UpdateInfo local) =>
      _isNewerVersion(remote, local);

  static bool _isNewerVersion(UpdateInfo remote, UpdateInfo local) {
    // 以 buildNumber 优先对比
    if (remote.buildNumber > 0 || local.buildNumber > 0) {
      return remote.buildNumber > local.buildNumber;
    }
    // 退级：语义版本字符串对比（三段 int 比较）
    return _compareSemanticVersion(remote.version, local.version) > 0;
  }

  /// 语义版本比较，返回：正数 = a 更新，0 = 相同，负数 = b 更新
  static int compareSemanticVersion(String a, String b) =>
      _compareSemanticVersion(a, b);

  static int _compareSemanticVersion(String a, String b) {
    final aParts = _parseSemVer(a);
    final bParts = _parseSemVer(b);
    for (int i = 0; i < 3; i++) {
      final diff = aParts[i] - bParts[i];
      if (diff != 0) return diff;
    }
    return 0;
  }

  /// 将语义版本字符串拆分为三段整数列表（不足三段补 0）
  static List<int> _parseSemVer(String version) {
    final parts = version.split('.');
    return List.generate(3, (i) {
      if (i >= parts.length) return 0;
      return int.tryParse(parts[i]) ?? 0;
    });
  }
}
