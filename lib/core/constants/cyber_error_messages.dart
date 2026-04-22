class CyberErrorMessages {
  // ==========================================
  // 📡 网络与云端通讯错误 (屏蔽底层实现细节)
  // ==========================================
  static const String ttsNodeUnresponsive = '语音服务暂不可用，请检查网络后重试';
  static const String ttsConnectTimeout = '服务连接超时，请检查网络设置';
  static const String ttsRequestTimeout = '请求处理超时，请稍后重试';
  static const String ttsAudioLoadTimeout = '语音加载缓慢，为您切换至本地语音';

  static String ttsServerErrorCode(int code) => '服务器繁忙，请稍后重试 (错误码: $code)';

  // ==========================================
  // 🛡️ 降级与兜底提醒 (用户友好的状态变更)
  // ==========================================
  static const String ttsFallbackDisconnected = '云端连接因网络波动断开，已自动切换为本地语音';
  static const String ttsFallbackTimeout = '云端资源加载失败，正在使用本地语音播放';

  // ==========================================
  // 🧩 协议与解析异常 (隐藏服务架构与堆栈)
  // ==========================================
  static const String ttsInvalidFormat = '语音数据异常，请确保应用为最新版或稍后重试';
  static const String ttsNotJsonObject = '语音服务暂不支持该解析，请稍后重试';
  
  static String ttsMissingUrl(String body) => '获取语音地址失败，请重新尝试';
  static String ttsMissingUrlTest(String body) => '语音服务通道发生异常，请联系开发者获取支持';

  // ==========================================
  // 🤖 业务逻辑与系统状态提示
  // ==========================================
  static const String ttsRequireBookFirst = '请先导入一部书籍，再开启语音朗读';
  static const String ttsNoContentRequiresBook = '当前没有内容可以朗读，请先选择一部书籍';
  static const String ttsIdleTimeout = '您已经休息很久啦，为了省电，语音已自动暂停';
  static const String ttsAudioParamFailed = '语音参数调节失败，请重启功能重试';

  // ==========================================
  // 💾 本地数据与文件导入
  // ==========================================
  static const String importFormatFailed = '不支持该书籍的格式，请确认是否为文本文件';
  static const String importReadPathFailed = '无法读取文件路径，请检查您的存储权限';
  static const String testFailedUnresponsive = '连通性测试未通过：网络连接异常，服务不可用';
  
  static String importFileTooLarge(int maxMb) => 
      '为了保证流畅阅读，暂不支持体积超过 ${maxMb}MB 的书籍，建议分卷导入';
}
