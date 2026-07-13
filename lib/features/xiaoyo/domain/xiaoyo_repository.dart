import 'package:yueyou/features/xiaoyo/domain/xiaoyo_profile.dart';

/// 本地 Xiaoyo Profile 的持久化边界。
abstract interface class XiaoyoRepository {
  Future<XiaoyoProfile> load();

  Future<void> save(XiaoyoProfile profile);

  Future<XiaoyoExportBundle> exportBundle();

  Future<XiaoyoProfile> importBundle(XiaoyoExportBundle bundle);
}

/// 用户可导出的成长摘要，不包含正文、路径或音频数据。
final class XiaoyoExportBundle {
  final XiaoyoProfile profile;

  const XiaoyoExportBundle(this.profile);
}
