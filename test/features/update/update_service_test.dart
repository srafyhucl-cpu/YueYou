import 'package:flutter_test/flutter_test.dart';
import 'package:yueyou/features/update/domain/update_info.dart';
import 'package:yueyou/features/update/services/update_service.dart';

void main() {
  // ── UpdateInfo.fromJson ───────────────────────────────────────────────────

  group('UpdateInfo.fromJson', () {
    test('完整 JSON 正确解析', () {
      final json = {
        'version': '1.2.0',
        'buildNumber': 5,
        'forceUpdate': true,
        'releaseNotes': '修复 TTS 偶发崩溃',
        'downloadUrl': 'https://example.com/download',
      };
      final info = UpdateInfo.fromJson(json);
      expect(info.version, '1.2.0');
      expect(info.buildNumber, 5);
      expect(info.forceUpdate, isTrue);
      expect(info.releaseNotes, '修复 TTS 偶发崩溃');
      expect(info.downloadUrl, 'https://example.com/download');
    });

    test('缺省字段使用安全默认值，不抛异常', () {
      final info = UpdateInfo.fromJson({});
      expect(info.version, '0.0.0');
      expect(info.buildNumber, 0);
      expect(info.forceUpdate, isFalse);
      expect(info.releaseNotes, '');
      expect(info.downloadUrl, '');
    });

    test('forceUpdate 缺省为 false', () {
      final info = UpdateInfo.fromJson({'version': '1.0.0', 'buildNumber': 1});
      expect(info.forceUpdate, isFalse);
    });

    test('buildNumber 为浮点数时向下取整', () {
      final info = UpdateInfo.fromJson({'version': '1.0.0', 'buildNumber': 3.9});
      expect(info.buildNumber, 3);
    });

    test('字段类型错误时返回默认值（宽松解析）', () {
      final info = UpdateInfo.fromJson({
        'version': null,
        'buildNumber': null,
        'forceUpdate': null,
      });
      expect(info.version, '0.0.0');
      expect(info.buildNumber, 0);
      expect(info.forceUpdate, isFalse);
    });
  });

  // ── UpdateInfo 值相等 ─────────────────────────────────────────────────────

  group('UpdateInfo 相等性', () {
    test('version/buildNumber/forceUpdate 相同时相等', () {
      const a = UpdateInfo(version: '1.0.0', buildNumber: 1, forceUpdate: false);
      const b = UpdateInfo(version: '1.0.0', buildNumber: 1, forceUpdate: false);
      expect(a, equals(b));
    });

    test('buildNumber 不同时不相等', () {
      const a = UpdateInfo(version: '1.0.0', buildNumber: 1, forceUpdate: false);
      const b = UpdateInfo(version: '1.0.0', buildNumber: 2, forceUpdate: false);
      expect(a, isNot(equals(b)));
    });
  });

  // ── UpdateService.compareSemanticVersion ─────────────────────────────────

  group('UpdateService.compareSemanticVersion', () {
    test('主版本号大的更新', () {
      expect(UpdateService.compareSemanticVersion('2.0.0', '1.9.9'), greaterThan(0));
    });

    test('次版本号大的更新', () {
      expect(UpdateService.compareSemanticVersion('1.2.0', '1.1.9'), greaterThan(0));
    });

    test('修订号大的更新', () {
      expect(UpdateService.compareSemanticVersion('1.0.2', '1.0.1'), greaterThan(0));
    });

    test('完全相同返回 0', () {
      expect(UpdateService.compareSemanticVersion('1.0.0', '1.0.0'), equals(0));
    });

    test('主版本号小的更旧', () {
      expect(UpdateService.compareSemanticVersion('1.0.0', '2.0.0'), lessThan(0));
    });

    test('两位版本号（补 0）正常对比', () {
      expect(UpdateService.compareSemanticVersion('1.1', '1.0.9'), greaterThan(0));
    });

    test('单位版本号（补 0）正常对比', () {
      expect(UpdateService.compareSemanticVersion('2', '1.9.9'), greaterThan(0));
    });

    test('空字符串与 0.0.0 相等', () {
      expect(UpdateService.compareSemanticVersion('', '0.0.0'), equals(0));
    });
  });

  // ── UpdateService.isNewerVersion ─────────────────────────────────────────

  group('UpdateService.isNewerVersion', () {
    test('buildNumber 较大时返回 true', () {
      const remote = UpdateInfo(version: '1.1.0', buildNumber: 5, forceUpdate: false);
      const local = UpdateInfo(version: '1.0.0', buildNumber: 3, forceUpdate: false);
      expect(UpdateService.isNewerVersion(remote, local), isTrue);
    });

    test('buildNumber 相同时返回 false', () {
      const remote = UpdateInfo(version: '1.1.0', buildNumber: 3, forceUpdate: false);
      const local = UpdateInfo(version: '1.0.0', buildNumber: 3, forceUpdate: false);
      expect(UpdateService.isNewerVersion(remote, local), isFalse);
    });

    test('buildNumber 较小时返回 false', () {
      const remote = UpdateInfo(version: '1.0.0', buildNumber: 2, forceUpdate: false);
      const local = UpdateInfo(version: '1.1.0', buildNumber: 5, forceUpdate: false);
      expect(UpdateService.isNewerVersion(remote, local), isFalse);
    });

    test('buildNumber 均为 0 时退级语义版本对比', () {
      const remote = UpdateInfo(version: '1.2.0', buildNumber: 0, forceUpdate: false);
      const local = UpdateInfo(version: '1.1.0', buildNumber: 0, forceUpdate: false);
      expect(UpdateService.isNewerVersion(remote, local), isTrue);
    });

    test('buildNumber 均为 0 且语义版本相同时返回 false', () {
      const remote = UpdateInfo(version: '1.0.0', buildNumber: 0, forceUpdate: false);
      const local = UpdateInfo(version: '1.0.0', buildNumber: 0, forceUpdate: false);
      expect(UpdateService.isNewerVersion(remote, local), isFalse);
    });

    test('buildNumber 均为 0 且远端语义版本较小时返回 false', () {
      const remote = UpdateInfo(version: '0.9.0', buildNumber: 0, forceUpdate: false);
      const local = UpdateInfo(version: '1.0.0', buildNumber: 0, forceUpdate: false);
      expect(UpdateService.isNewerVersion(remote, local), isFalse);
    });

    test('forceUpdate=true 也遵循版本对比规则', () {
      const remote = UpdateInfo(version: '2.0.0', buildNumber: 10, forceUpdate: true);
      const local = UpdateInfo(version: '1.0.0', buildNumber: 3, forceUpdate: false);
      expect(UpdateService.isNewerVersion(remote, local), isTrue);
    });
  });

  // ── UpdateService.checkForUpdate（API URL 为空时静默跳过）─────────────────

  group('UpdateService.checkForUpdate', () {
    test('UPDATE_API_URL 未配置时返回 null（静默跳过）', () async {
      // 测试环境无 --dart-define=UPDATE_API_URL，接口不发请求
      final result = await UpdateService.checkForUpdate();
      expect(result, isNull);
    });
  });
}
