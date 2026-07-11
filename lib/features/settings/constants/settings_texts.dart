/// 设置模块文案常量。
class SettingsTexts {
  const SettingsTexts._();

  /// 设置页标题。
  static const String screenTitle = '神经系统配置';

  /// 语音播报分组标题。
  static const String ttsSectionTitle = '语音播报 (TTS)';

  /// 自动朗读开关标题。
  static const String autoReadTitle = '自动朗读';

  /// 自动朗读开关说明。
  static const String autoReadSubtitle = '接入神经链路，自动播报小说文本';

  /// 核心音色字段标题。
  static const String voiceLabel = '核心音色';

  /// 语音包提示。
  static const String voiceHint = '💡 提示：若音色生硬，请在系统设置中下载高品质语音包。';

  /// 意境氛围分组标题。
  static const String ambientSectionTitle = '意境氛围';

  /// 背景氛围音开关标题。
  static const String ambientSoundTitle = '背景氛围音';

  /// 背景氛围音开关说明。
  static const String ambientSoundSubtitle = '注入沉浸式白噪声，屏蔽外界干扰';

  /// 意境风格字段标题。
  static const String ambientStyleLabel = '意境风格';

  /// 武侠风格选项。
  static const String ambientStyleWuxia = '江湖风云 (深沉)';

  /// 温馨风格选项。
  static const String ambientStyleWarm = '围炉夜话 (温馨)';

  /// 输出增益字段标题。
  static const String ambientVolumeLabel = '输出增益';

  /// 省电管理分组标题。
  static const String powerSectionTitle = '省电管理';

  /// 静默暂停字段标题。
  static const String idleTimeoutLabel = '静默暂停 (无操作自动停止)';

  /// 永不暂停选项。
  static const String idleNever = '永不';

  /// 1 分钟选项。
  static const String idleOneMinute = '1m';

  /// 5 分钟选项。
  static const String idleFiveMinutes = '5m';

  /// 10 分钟选项。
  static const String idleTenMinutes = '10m';

  /// 20 分钟选项。
  static const String idleTwentyMinutes = '20m';

  /// 30 分钟选项。
  static const String idleThirtyMinutes = '30m';

  /// 1 小时选项。
  static const String idleOneHour = '1h';

  /// 系统音效分组标题。
  static const String systemSoundSectionTitle = '系统音效';

  /// 方块合并音效开关标题。
  static const String mergeSoundTitle = '方块合并音效';

  /// 方块合并音效开关说明。
  static const String mergeSoundSubtitle = '2048 核心交互音频反馈';

  /// 隐私与合规分组标题。
  static const String privacyComplianceTitle = '隐私与合规';

  /// 隐私政策入口标题。
  static const String privacyPolicyTitle = '隐私政策';

  /// 隐私政策入口说明。
  static const String privacyPolicySubtitle = '查看数据存储、TTS 云端合成与权限使用说明';

  /// 隐私授权撤回入口标题。
  static const String privacyRevokeTitle = '撤回隐私授权';

  /// 隐私授权撤回入口说明。
  static const String privacyRevokeSubtitle = '清理第三方会话，并在下次启动重新确认';

  /// 晓晓音色显示名。
  static const String voiceXiaoxiao = '晓晓 (温柔)';

  /// 云溪音色显示名。
  static const String voiceYunxi = '云溪 (阳光)';

  /// 云健音色显示名。
  static const String voiceYunjian = '云健 (稳重)';

  /// 晓伊音色显示名。
  static const String voiceXiaoyi = '晓伊 (知性)';

  /// 晓梦音色显示名。
  static const String voiceXiaomeng = '晓梦 (活泼)';

  /// TTS 自检进行中文案。
  static const String ttsTestingLabel = '正在进行神经链路诊断...';

  /// TTS 自检按钮文案。
  static const String ttsTestButtonLabel = '执行系统自检 (TTS Test)';

  /// TTS 自检成功标题。
  static const String ttsTestSuccessTitle = '链路诊断报告：通畅';

  /// TTS 自检失败标题。
  static const String ttsTestFailureTitle = '链路诊断报告：故障';

  /// 确认按钮文案。
  static const String confirmButtonLabel = '了解';

  /// TTS 自检异常上下文。
  static const String ttsTestExceptionContext = 'TTS 自检触发异常';
}
