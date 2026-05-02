/// TTS 缓冲队列健康状态。
///
/// - [healthy]：缓冲充足（已缓冲 ≥ 60% 上限），系统运行流畅。
/// - [warning]：缓冲偏低（已缓冲 33%–60%），触发加速预加载。
/// - [critical]：缓冲危险（已缓冲 < 33%），可能出现卡顿。
/// - [empty]：队列为空，无可用缓冲。
enum TtsBufferStatus { healthy, warning, critical, empty }

/// 已缓冲的音频项。
///
/// 绑定磁盘文件路径与原始文本行号，确保播放顺序与预加载顺序一致。
class BufferedAudio {
  final String filePath;
  final int lineIndex;
  final String text;
  final String title;
  final int session;

  const BufferedAudio({
    required this.filePath,
    required this.lineIndex,
    required this.text,
    required this.title,
    required this.session,
  });
}

/// TTS 预加载缓冲队列。
///
/// 纯领域逻辑，无任何 Flutter / IO 依赖。
/// 负责维护预加载队列的健康状态计算与 FIFO 出队。
class TtsAudioBuffer {
  final int maxSize;
  final List<BufferedAudio> _items = [];

  TtsAudioBuffer({required this.maxSize});

  /// 当前缓冲数量。
  int get count => _items.length;

  /// 队列是否已满（达到上限）。
  bool get isFull => _items.length >= maxSize;

  /// 队列是否为空。
  bool get isEmpty => _items.isEmpty;

  /// 缓冲健康比例（0.0 = 空，1.0 = 满）。
  double get healthRatio {
    if (maxSize <= 0) return 1.0;
    return (_items.length / maxSize).clamp(0.0, 1.0);
  }

  /// 缓冲健康状态。
  TtsBufferStatus get status {
    if (_items.isEmpty) return TtsBufferStatus.empty;
    final ratio = healthRatio;
    if (ratio >= 0.6) return TtsBufferStatus.healthy;
    if (ratio >= 0.33) return TtsBufferStatus.warning;
    return TtsBufferStatus.critical;
  }

  /// 是否需要补充预加载（低于 60% 即触发）。
  bool get needsRefill => !isFull && healthRatio < 0.6;

  /// 向队列添加一个缓冲项，并按 [lineIndex] 排序。
  void add(BufferedAudio item) {
    _items.add(item);
    _items.sort((a, b) => a.lineIndex.compareTo(b.lineIndex));
  }

  /// 取出队列头部的项（FIFO）。
  BufferedAudio? takeNext() {
    if (_items.isEmpty) return null;
    return _items.removeAt(0);
  }

  /// 预览队列头部项，不移除。
  BufferedAudio? get peek => _items.isNotEmpty ? _items.first : null;

  /// 清空队列。
  void clear() => _items.clear();

  /// 获取所有文件路径（用于清理临时文件）。
  List<String> get allFilePaths => _items.map((e) => e.filePath).toList();

  /// 检查特定行索引是否已在缓冲区中。
  bool containsLineIndex(int index) => _items.any((e) => e.lineIndex == index);
}
