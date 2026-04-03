/// 赛博朋克设计系统 - 尺寸规范
/// 统一管理圆角、边框、模糊、间距等数值，确保视觉一致性
class CyberDimensions {
  // ==================== 圆角系统 ====================
  // 5 级圆角，从大到小递减

  /// 超大圆角 - 用于大型容器（棋盘外框）
  static const double radiusXL = 32.0;

  /// 大圆角 - 用于中型容器（控制台、工具栏、弹窗）
  static const double radiusL = 24.0;

  /// 中圆角 - 用于卡片、格子
  static const double radiusM = 16.0;

  /// 小圆角 - 用于按钮、小卡片
  static const double radiusS = 12.0;

  /// 超小圆角 - 用于细节（进度条、波形条）
  static const double radiusXS = 2.0;

  // ==================== 边框系统 ====================
  // 3 级边框宽度

  /// 粗边框 - 用于强调（选中状态、主要边框）
  static const double borderThick = 1.5;

  /// 常规边框 - 用于普通容器
  static const double borderNormal = 1.0;

  /// 细边框 - 用于细微装饰（背景网格）
  static const double borderThin = 0.5;

  // ==================== 毛玻璃模糊系统 ====================
  // 3 级模糊强度

  /// 强模糊 - 用于主要容器（棋盘、卡片）
  static const double blurStrong = 20.0;

  /// 中模糊 - 用于工具栏、控制台
  static const double blurMedium = 15.0;

  /// 轻模糊 - 用于遮罩、头部
  static const double blurLight = 10.0;

  // ==================== 间距系统 ====================
  // 标准间距，8px 倍数

  static const double spacingXXS = 2.0;
  static const double spacingXS = 4.0;
  static const double spacingS = 8.0;
  static const double spacingMS = 12.0;
  static const double spacingM = 16.0;
  static const double spacingML = 20.0;
  static const double spacingL = 24.0;
  static const double spacingXL = 32.0;

  // ==================== 头部 / 工具栏 ====================

  /// 标准页面头部高度
  static const double headerHeight = 56.0;

  /// 标准电传屏高度
  static const double teleprompterHeight = 46.0;

  /// 标准电传屏遮罩宽度
  static const double teleprompterMaskWidth = 40.0;

  /// 标准仪表盘吉祥物宽度
  static const double dashboardMascotWidth = 68.0;

  /// 标准仪表盘吉祥物高度
  static const double dashboardMascotHeight = 84.0;

  /// 标准仪表盘缓冲区高度
  static const double dashboardBoardBuffer = 76.0;

  /// 标准仪表盘状态卡片最小高度
  static const double dashboardStatusCardMinHeight = 85.0;

  // ==================== 图标尺寸 ====================

  /// 超小图标（箭头、指示器）
  static const double iconXS = 16.0;

  /// 小图标（音量、状态）
  static const double iconS = 18.0;

  /// 中图标（操作按钮、加载器）
  static const double iconM = 20.0;

  /// 大图标（对话框标题图标）
  static const double iconL = 28.0;
}
