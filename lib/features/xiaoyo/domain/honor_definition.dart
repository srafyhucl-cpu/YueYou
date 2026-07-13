/// 可展示的永久荣誉定义，解锁规则由 [XiaoyoGrowthEngine] 统一解释。
final class XiaoyoHonorDefinition {
  final String id;
  final String title;
  final String description;

  const XiaoyoHonorDefinition({
    required this.id,
    required this.title,
    required this.description,
  });
}

/// 首版永久荣誉 ID，规则由 [XiaoyoGrowthEngine] 统一解释。
abstract final class XiaoyoHonorIds {
  static const firstBook = 'book.first';
  static const fifthBook = 'book.fifth';
  static const tenthBook = 'book.tenth';
  static const tenHours = 'listen.ten_hours';
  static const fiftyHours = 'listen.fifty_hours';
  static const oneHundredHours = 'listen.one_hundred_hours';
  static const companion = 'stage.companion';
  static const guardian = 'stage.guardian';
  static const resonance = 'stage.resonance';
  static const readingSeason = 'activity.reading_season_21d';
}

/// 首版永久荣誉目录，保持本地静态可审计，不依赖远程配置。
abstract final class XiaoyoHonorDefinitions {
  static const all = <XiaoyoHonorDefinition>[
    XiaoyoHonorDefinition(
      id: XiaoyoHonorIds.firstBook,
      title: '初次完本',
      description: '完成第一本书。',
    ),
    XiaoyoHonorDefinition(
      id: XiaoyoHonorIds.fifthBook,
      title: '五册同行',
      description: '完成五本书。',
    ),
    XiaoyoHonorDefinition(
      id: XiaoyoHonorIds.tenthBook,
      title: '十册守页',
      description: '完成十本书。',
    ),
    XiaoyoHonorDefinition(
      id: XiaoyoHonorIds.tenHours,
      title: '十小时共读',
      description: '累计有效听读十小时。',
    ),
    XiaoyoHonorDefinition(
      id: XiaoyoHonorIds.fiftyHours,
      title: '五十小时共读',
      description: '累计有效听读五十小时。',
    ),
    XiaoyoHonorDefinition(
      id: XiaoyoHonorIds.oneHundredHours,
      title: '百小时守页',
      description: '累计有效听读一百小时。',
    ),
    XiaoyoHonorDefinition(
      id: XiaoyoHonorIds.companion,
      title: '同行者',
      description: '达到同行者成长阶段。',
    ),
    XiaoyoHonorDefinition(
      id: XiaoyoHonorIds.guardian,
      title: '守页者',
      description: '达到守页者成长阶段。',
    ),
    XiaoyoHonorDefinition(
      id: XiaoyoHonorIds.resonance,
      title: '书声共振',
      description: '达到书声共振成长阶段。',
    ),
    XiaoyoHonorDefinition(
      id: XiaoyoHonorIds.readingSeason,
      title: '共读季守页',
      description: '完成 21 天书境共读季。',
    ),
  ];

  static XiaoyoHonorDefinition? find(String id) {
    for (final definition in all) {
      if (definition.id == id) return definition;
    }
    return null;
  }
}
