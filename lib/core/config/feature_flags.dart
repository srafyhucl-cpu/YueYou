/// 阅游产品阶段性能力开关。
///
/// 所有新能力默认关闭，按工作包通过 `--dart-define` 独立启用，确保回滚时
/// 不读取新状态、不加载新资源，也不请求新服务。
abstract final class FeatureFlags {
  /// 是否启用以听读为首屏的三根导航壳。
  static const bool readingFirstShell = bool.fromEnvironment(
    'READING_FIRST_SHELL_ENABLED',
    defaultValue: false,
  );

  /// 是否启用 Xiaoyo 2.0 角色资源。
  static const bool xiaoyoV2 = bool.fromEnvironment(
    'XIAOYO_V2_ENABLED',
    defaultValue: false,
  );

  /// 是否启用 Xiaoyo 关系与价值系统。
  static const bool xiaoyoValueSystem = bool.fromEnvironment(
    'XIAOYO_VALUE_SYSTEM_ENABLED',
    defaultValue: false,
  );

  /// 是否启用商业预览能力。
  static const bool commercePreview = bool.fromEnvironment(
    'COMMERCE_PREVIEW_ENABLED',
    defaultValue: false,
  );

  /// 是否启用按需 3D 能力。
  static const bool xiaoyo3d = bool.fromEnvironment(
    'XIAOYO_3D_ENABLED',
    defaultValue: false,
  );
}
