/// 应用主体信息配置。
///
/// 开发者/运营主体和联系方式支持通过 `--dart-define` 覆盖。
/// 默认值为当前个人开发者公开信息。
class AppInfoConfig {
  const AppInfoConfig._();

  /// 运营主体名称。
  static const String developerName = String.fromEnvironment(
    'APP_DEVELOPER_NAME',
    defaultValue: '胡传龙',
  );

  /// 隐私与用户反馈联系邮箱。
  static const String contactEmail = String.fromEnvironment(
    'APP_CONTACT_EMAIL',
    defaultValue: 'hucloong@163.com',
  );

  /// 正式隐私政策页面。
  static const String privacyPolicyUrl = String.fromEnvironment(
    'PRIVACY_POLICY_URL',
    defaultValue: 'https://hclstudio.cn/privacy',
  );
}
