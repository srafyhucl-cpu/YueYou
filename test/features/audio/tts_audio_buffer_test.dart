import 'package:flutter_test/flutter_test.dart';
import 'package:yueyou/features/audio/domain/tts_audio_buffer.dart';

/// T-3 / P0-6 回归用例：
/// 验证 [TtsAudioBuffer.add] 严格 FIFO，不再按 lineIndex 排序。
///
/// 该测试守护核心 TTS 顺序契约：无论 lineIndex 如何乱序加入，
/// takeNext() 的顺序必须等于 add() 的顺序，否则会出现 TTS 章末回卷重读章首等严重 Bug。
void main() {
  group('TtsAudioBuffer FIFO 语义（P0-6 回归）', () {
    late TtsAudioBuffer buffer;

    setUp(() {
      buffer = TtsAudioBuffer(maxSize: 6);
    });

    BufferedAudio mk(int line, {int session = 1, String? path}) => BufferedAudio(
          filePath: path ?? '/tmp/audio_$line.mp3',
          lineIndex: line,
          text: '第 $line 行的测试文本',
          title: '测试章节',
          session: session,
        );

    test('add 顺序与 takeNext 顺序严格一致（升序输入）', () {
      buffer.add(mk(10));
      buffer.add(mk(11));
      buffer.add(mk(12));

      expect(buffer.takeNext()?.lineIndex, 10);
      expect(buffer.takeNext()?.lineIndex, 11);
      expect(buffer.takeNext()?.lineIndex, 12);
      expect(buffer.takeNext(), isNull);
    });

    test('add 顺序与 takeNext 顺序严格一致（乱序输入，禁止内部排序）', () {
      // 模拟章末 wrap-around：先加入末尾大 lineIndex，再加入回卷后的 0
      buffer.add(mk(108));
      buffer.add(mk(109));
      buffer.add(mk(0)); // 不应被排序到队首

      expect(buffer.takeNext()?.lineIndex, 108);
      expect(buffer.takeNext()?.lineIndex, 109);
      expect(buffer.takeNext()?.lineIndex, 0);
    });

    test('prepend 项绝对优先于后续 add 项', () {
      buffer.add(mk(50));
      buffer.add(mk(51));
      // 模拟 pause→resume 把当前句插入队首
      buffer.prepend(mk(99, path: '/tmp/resume.mp3'));

      // resume 后预取又 add 进新句
      buffer.add(mk(52));

      final first = buffer.takeNext();
      expect(first?.lineIndex, 99,
          reason: 'prepend 后的项必须最先被 takeNext 取出，绝不能被 add 插队');
      expect(first?.filePath, '/tmp/resume.mp3');

      expect(buffer.takeNext()?.lineIndex, 50);
      expect(buffer.takeNext()?.lineIndex, 51);
      expect(buffer.takeNext()?.lineIndex, 52);
    });

    test('健康度状态映射符合阈值约定', () {
      // 6 容量：empty / critical(<33%) / warning(33-60%) / healthy(>=60%)
      expect(buffer.status, TtsBufferStatus.empty);

      buffer.add(mk(1));
      expect(buffer.status, TtsBufferStatus.critical); // 1/6 ≈ 16.7%

      buffer.add(mk(2));
      expect(buffer.status, TtsBufferStatus.warning); // 2/6 ≈ 33.3%

      buffer.add(mk(3));
      buffer.add(mk(4));
      expect(buffer.status, TtsBufferStatus.healthy); // 4/6 ≈ 66.7%
    });

    test('clear 后队列归零，状态回到 empty', () {
      buffer.add(mk(1));
      buffer.add(mk(2));
      expect(buffer.count, 2);

      buffer.clear();
      expect(buffer.count, 0);
      expect(buffer.isEmpty, true);
      expect(buffer.status, TtsBufferStatus.empty);
    });

    test('allFilePaths 反映当前队列内全部文件路径', () {
      buffer.add(mk(1, path: '/a.mp3'));
      buffer.add(mk(2, path: '/b.mp3'));

      expect(buffer.allFilePaths, ['/a.mp3', '/b.mp3']);
    });
  });
}
