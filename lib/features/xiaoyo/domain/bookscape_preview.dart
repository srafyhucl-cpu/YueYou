/// 书境预览的本地展示层级，不代表实际购买权益。
enum XiaoyoBookscapeTier { free, paidPreview }

/// 一个静态书境预览定义，不包含订单、价格、权益或远程配置。
final class XiaoyoBookscapeDefinition {
  final XiaoyoBookscapeTier tier;
  final String title;
  final String sceneTitle;
  final String description;
  final List<String> visualDifferences;
  final bool previewOnly;

  const XiaoyoBookscapeDefinition({
    required this.tier,
    required this.title,
    required this.sceneTitle,
    required this.description,
    required this.visualDifferences,
    required this.previewOnly,
  });
}

/// 首个书境对比预览目录，默认不挂载到正式用户路径。
abstract final class XiaoyoBookscapePreviews {
  static const free = XiaoyoBookscapeDefinition(
    tier: XiaoyoBookscapeTier.free,
    title: '基础书境',
    sceneTitle: '纸页台座',
    description: '保留完整的听读、成长、印记和荣誉基础体验。',
    visualDifferences: [
      '基础材质与静态陪伴',
      '章节完成与完本反馈',
      '本地活动和永久荣誉',
    ],
    previewOnly: false,
  );

  static const paidPreview = XiaoyoBookscapeDefinition(
    tier: XiaoyoBookscapeTier.paidPreview,
    title: '主题书境预览',
    sceneTitle: '岭南雨驿',
    description: '只展示主题材质、空间和转场差异，尚未开放购买。',
    visualDifferences: [
      '主题材质与空间氛围',
      '章节和完本专属转场',
      '不改变成长、荣誉或听读效率',
    ],
    previewOnly: true,
  );

  static const all = <XiaoyoBookscapeDefinition>[free, paidPreview];

  static XiaoyoBookscapeDefinition forTier(XiaoyoBookscapeTier tier) =>
      switch (tier) {
        XiaoyoBookscapeTier.free => free,
        XiaoyoBookscapeTier.paidPreview => paidPreview,
      };
}
