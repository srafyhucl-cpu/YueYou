/// 应用主体信息配置。
///
/// 开发者/运营主体和联系方式必须在正式构建时通过 `--dart-define` 注入。
/// 默认值仅作为未配置时的占位提醒，禁止直接用于上架包。
class AppInfoConfig {
  const AppInfoConfig._();

  /// 运营主体名称。
  static const String developerName = String.fromEnvironment(
    'APP_DEVELOPER_NAME',
    defaultValue: '【待填写：开发者或运营主体名称】',
  );

  /// 隐私与用户反馈联系邮箱。
  static const String contactEmail = String.fromEnvironment(
    'APP_CONTACT_EMAIL',
    defaultValue: '【待填写：联系邮箱】',
  );
}
