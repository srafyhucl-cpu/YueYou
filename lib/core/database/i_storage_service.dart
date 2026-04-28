/// 本地持久化服务的统一接口定义（依赖倒置原则）
///
/// 所有业务逻辑层应依赖本接口，而非直接引用 [StorageService] 静态类。
/// 这样可在测试中注入 Mock 实现，在生产环境中注入 [LocalStorageService]，
/// 实现业务逻辑与具体存储实现的完全解耦。
///
/// ## 设计约束
/// - 本接口位于 `core/database/`，仅允许被 `features/*/providers/` 消费。
/// - 严禁在 `presentation/` 层直接调用任何存储接口。
/// - 所有写操作均为 async（`Future<void>`），读操作可同步或异步。
abstract interface class IStorageService {
  // ── 初始化 ────────────────────────────────────────────────────────────────

  /// 初始化底层存储引擎（应在 [runApp] 前调用一次）
  Future<void> init();

  // ── 游戏状态 ──────────────────────────────────────────────────────────────

  /// 保存完整的 2048 游戏快照
  ///
  /// - [board]：4×4 棋盘（`null` 表示空格，非 `null` 为 `{id, value}`）
  /// - [score]：当前全盘总分（全盘求和法，非累加法）
  /// - [combo]：当前连击数
  /// - [bestScore]：历史最佳得分
  /// - [maxCombo]：历史最大连击
  /// - [novelIndex]：当前关联的小说索引
  /// - [currentNovelId]：当前关联的小说 ID（可为 null）
  Future<void> saveGameState({
    required List<List<Map<String, dynamic>?>> board,
    required int score,
    required int combo,
    required int bestScore,
    required int maxCombo,
    required int novelIndex,
    String? currentNovelId,
  });

  /// 读取游戏快照，返回 `null` 表示无存档或存档损坏
  Map<String, dynamic>? loadGameState();

  /// 读取历史最佳得分（无存档时返回 0）
  int loadBestScore();

  /// 读取历史最大连击数（无存档时返回 0）
  int loadMaxCombo();

  // ── 书架元数据 ────────────────────────────────────────────────────────────

  /// 保存书架元数据列表（全量覆盖写入）
  ///
  /// 每个元素为书籍元数据 Map，至少包含 `id`、`title`、`total` 字段。
  Future<void> saveBookshelf(List<Map<String, dynamic>> shelf);

  /// 读取书架元数据列表（损坏或空时返回空列表）
  List<Map<String, dynamic>> loadBookshelf();

  // ── 阅读进度 ──────────────────────────────────────────────────────────────

  /// 更新指定书籍的阅读进度
  ///
  /// - [bookId]：书籍唯一标识
  /// - [cursor]：当前行号（0-based）
  /// - [total]：总行数（≤ 0 时忽略，防止除零）
  Future<void> updateReadingRecord(String bookId, int cursor, int total);

  /// 读取指定书籍的阅读进度
  ///
  /// 返回 `{cursor, total, percent}`，无记录时返回默认零进度。
  Map<String, dynamic> getReadingRecord(String bookId);

  /// 删除指定书籍的阅读进度记录
  Future<void> deleteReadingRecord(String bookId);

  // ── 当前小说状态 ──────────────────────────────────────────────────────────

  /// 设置当前激活的小说 ID（传入 `null` 时清除）
  Future<void> setCurrentNovelId(String? id);

  /// 读取当前激活的小说 ID（未设置时返回 `null`）
  String? getCurrentNovelId();

  /// 读取当前激活的小说在书架中的索引（未设置时返回 0）
  int getCurrentNovelIndex();

  /// 设置当前激活的小说在书架中的索引
  Future<void> setCurrentNovelIndex(int index);

  // ── 书籍正文内容 ──────────────────────────────────────────────────────────

  /// 将书籍正文按行存储为 JSON 文件（大文件，存入 Documents 目录）
  ///
  /// - [bookId]：书籍唯一标识（作为文件名）
  /// - [lines]：全文按行分割后的字符串列表
  /// - [chapters]：章节目录，每项至少含 `title`、`lineIndex` 字段
  Future<void> saveBookContent(
    String bookId, {
    required List<String> lines,
    required List<Map<String, dynamic>> chapters,
  });

  /// 读取书籍正文内容
  ///
  /// 返回 `{lines: List<String>, chapters: List<Map>}`，
  /// 文件不存在或 JSON 损坏时返回 `null`。
  Future<Map<String, dynamic>?> loadBookContent(String bookId);

  /// 删除指定书籍的正文文件（文件不存在时静默忽略）
  Future<void> deleteBookContent(String bookId);

  // ── 全局设置 ──────────────────────────────────────────────────────────────

  /// 读取音效开关（默认 `true`）
  bool getSettingSound();

  /// 设置音效开关并持久化
  Future<void> setSettingSound(bool v);

  /// 读取 TTS 朗读开关（默认 `true`）
  bool getSettingStoryTts();

  /// 设置 TTS 朗读开关并持久化
  Future<void> setSettingStoryTts(bool v);

  /// 读取 TTS 音色 ID（默认 `'zh-CN-XiaoxiaoNeural'`）
  String getSettingVoice();

  /// 设置 TTS 音色 ID 并持久化
  Future<void> setSettingVoice(String v);

  /// 读取空闲超时（分钟，默认 1）
  int getSettingIdleTimeout();

  /// 设置空闲超时并持久化
  Future<void> setSettingIdleTimeout(int v);

  /// 读取 TTS 播放倍速（默认 `1.0`）
  double getSettingTtsRate();

  /// 设置 TTS 播放倍速并持久化
  Future<void> setSettingTtsRate(double v);

  /// 读取环境音量（默认 `0.5`，范围 `0.0`–`1.0`）
  double getSettingAmbientVol();

  /// 设置环境音量并持久化
  Future<void> setSettingAmbientVol(double v);

  /// 读取环境背景音乐开关（默认 `true`）
  bool getSettingAmbientEnabled();

  /// 设置环境背景音乐开关并持久化
  Future<void> setSettingAmbientEnabled(bool v);

  // ── 隐私协议 ──────────────────────────────────────────────────────────────

  /// 读取用户是否已同意隐私协议（默认 `false`）
  bool hasAgreedPrivacy();

  /// 设置隐私协议同意状态并持久化
  Future<void> setHasAgreedPrivacy(bool v);
}
