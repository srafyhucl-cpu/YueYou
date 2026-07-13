/// 听读首页的七种语义状态。
enum ReadingHomeStatus {
  /// 没有可继续的书籍或正文。
  empty,

  /// 有当前书籍，但音频尚未启动。
  ready,

  /// 音频正在准备缓冲。
  buffering,

  /// 音频正在播放。
  playing,

  /// 音频已暂停，保留当前句段。
  paused,

  /// 音频出现可恢复错误，保留当前阅读上下文。
  recoverableError,

  /// 当前正文游标已到达末尾且音频处于空闲状态。
  completed,
}

/// 听读首页只读状态快照。
///
/// 该模型只承载展示所需的脱敏投影，不保存正文、不操作播放器，也不依赖
/// Flutter、Riverpod 或本地存储。
final class ReadingHomeViewState {
  final ReadingHomeStatus status;
  final String? bookId;
  final String bookTitle;
  final String chapterTitle;
  final String? currentSentence;
  final double readingProgress;
  final double bufferingProgress;
  final String? errorMessage;
  final String? fallbackMessage;
  final double playbackRate;
  final int? session;
  final bool canRecover;

  const ReadingHomeViewState({
    required this.status,
    this.bookId,
    this.bookTitle = '阅游',
    this.chapterTitle = '暂无章节',
    this.currentSentence,
    this.readingProgress = 0.0,
    this.bufferingProgress = 0.0,
    this.errorMessage,
    this.fallbackMessage,
    this.playbackRate = 1.0,
    this.session,
    this.canRecover = true,
  });

  /// 无当前书状态的最小构造器。
  const ReadingHomeViewState.empty() : this(status: ReadingHomeStatus.empty);

  /// 当前状态是否已经拥有可展示的书籍上下文。
  bool get hasBook => bookId != null && bookId!.isNotEmpty;

  /// 当前状态对应的唯一主动作文案。
  String get primaryActionLabel => switch (status) {
        ReadingHomeStatus.empty => '导入本地书',
        ReadingHomeStatus.ready => '继续听读',
        ReadingHomeStatus.buffering => '取消缓冲',
        ReadingHomeStatus.playing => '暂停听读',
        ReadingHomeStatus.paused => '继续听读',
        ReadingHomeStatus.recoverableError => '重试播放',
        ReadingHomeStatus.completed => '返回书架',
      };
}
