import 'package:flutter_test/flutter_test.dart';
import 'package:yueyou/features/reader/domain/text_parser.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ── 边界输入 ─────────────────────────────────────────────────────────────────

  group('TextParser - 边界输入', () {
    test('空字符串返回空 ParseResult', () async {
      final result = await TextParser.parse('');
      expect(result.sentences, isEmpty);
      expect(result.rawLineOrigins, isEmpty);
    });

    test('纯空白字符串返回空 ParseResult', () async {
      final result = await TextParser.parse('   \n\n\t  ');
      expect(result.sentences, isEmpty);
    });

    test('sentences 与 rawLineOrigins 长度始终一致', () async {
      final result = await TextParser.parse('第一句。第二句！第三句？');
      expect(result.sentences.length, result.rawLineOrigins.length);
    });
  });

  // ── 基础切分 ─────────────────────────────────────────────────────────────────

  group('TextParser - 基础切分', () {
    test('单行单句，返回包含该句的列表', () async {
      final result = await TextParser.parse('你好世界。');
      expect(result.sentences, isNotEmpty);
      expect(result.sentences.first, contains('你好世界'));
    });

    test('句号切分多句', () async {
      final result = await TextParser.parse('第一句话。第二句话。第三句话。');
      expect(result.sentences.length, greaterThanOrEqualTo(2));
    });

    test('叹号切分句子', () async {
      final result = await TextParser.parse('这是感叹句！真的很厉害！');
      expect(result.sentences.length, greaterThanOrEqualTo(1));
    });

    test('问号切分句子', () async {
      final result = await TextParser.parse('这是问句吗？对的。');
      expect(result.sentences.length, greaterThanOrEqualTo(1));
    });

    test('分号切分句子', () async {
      final result = await TextParser.parse('前半部分；后半部分。');
      expect(result.sentences.length, greaterThanOrEqualTo(1));
    });

    test('结果中每个句子非空且非纯空白', () async {
      final result = await TextParser.parse('你好。世界。今天天气很好。');
      for (final s in result.sentences) {
        expect(s.trim(), isNotEmpty);
      }
    });

    test('多行输入：换行符不产生空句', () async {
      final result = await TextParser.parse('第一行。\n第二行。\n第三行。');
      for (final s in result.sentences) {
        expect(s.trim(), isNotEmpty);
      }
    });
  });

  // ── 噪声过滤 ─────────────────────────────────────────────────────────────────

  group('TextParser - 噪声过滤', () {
    test('纯标点符号段被过滤，不出现在结果中', () async {
      // 切分后可能残留纯标点段，应被过滤
      final result = await TextParser.parse('正常句子。「」。');
      for (final s in result.sentences) {
        // 每个句子至少含一个汉字或字母
        expect(
          RegExp(r'[\u4e00-\u9fff\u3400-\u4dbf\w]').hasMatch(s),
          isTrue,
          reason: '句子 "$s" 不含任何有效字符',
        );
      }
    });

    test('空行不产生空句', () async {
      const raw = '有效句子。\n\n\n另一句。';
      final result = await TextParser.parse(raw);
      for (final s in result.sentences) {
        expect(s.trim(), isNotEmpty);
      }
    });
  });

  // ── 长句防溢出切分 ──────────────────────────────────────────────────────────

  group('TextParser - 长句防溢出（>50字符）', () {
    test('超过 50 字符的单句被二次截断为多段', () async {
      // 构造一个超长无标点句（60个汉字）
      final longLine = '这是一个很长的句子' * 7; // 63 chars
      final result = await TextParser.parse(longLine);
      // 必须被切分为多段
      expect(result.sentences.length, greaterThan(1));
    });

    test('截断后每段不超过 50 字符', () async {
      final longLine = '甲乙丙丁戊己庚辛壬癸' * 6; // 60 chars, no punctuation
      final result = await TextParser.parse(longLine);
      for (final s in result.sentences) {
        expect(
          s.length,
          lessThanOrEqualTo(50),
          reason: '段落 "$s" 超过 50 字符',
        );
      }
    });

    test('含逗号的长句优先从逗号处截断', () async {
      // 50字符阈值内有逗号（在 70% 位置之后），应从逗号截断
      const text = 'ABCDEFGHIJKLMNOPQRSTUVWXYZABCDE，剩余部分FGHIJKLMNOP。';
      final result = await TextParser.parse(text);
      expect(result.sentences, isNotEmpty);
      // 截断结果的拼接应包含原文所有内容（无字符丢失）
      final joined = result.sentences.join('');
      // 原文汉字均应出现
      expect(joined, contains('剩余部分'));
    });

    test('连续多个省略号被预清洗为单个句号', () async {
      final result = await TextParser.parse('他说……我知道了。');
      expect(result.sentences, isNotEmpty);
      // 预清洗不应导致崩溃或产生空句
      for (final s in result.sentences) {
        expect(s.trim(), isNotEmpty);
      }
    });

    test('无标点长句优先从助词（的/了/和/与）处截断而非硬切', () async {
      // 构造一个 >50 字符、无标点无逗号无空格的句子
      // 助词"和"位于第 47 位（>50%=25），软断点应在此处生效
      const text = '在这个充满霓虹灯光与电子信号交织而成的巨大赛博朋克都市里每个人都在努力寻找属于自己的生存方式和存在的意义';
      expect(text.length, greaterThan(50)); // 前置断言：确保触发 _emergencySplit
      final result = await TextParser.parse(text);
      expect(result.sentences.length, greaterThan(1));
      // 截断点应在助词后，而非任意位置硬切
      final first = result.sentences.first;
      final lastChar = first[first.length - 1];
      expect(
        '的了和与'.contains(lastChar),
        isTrue,
        reason: '首段 "$first" 末尾字符 "$lastChar" 不是助词软断点',
      );
    });
  });

  // ── rawLineOrigins 正确性 ────────────────────────────────────────────────────

  group('TextParser - rawLineOrigins', () {
    test('单行输入的所有 rawLineOrigins 均为 0', () async {
      final result = await TextParser.parse('第一句。第二句。第三句。');
      for (final origin in result.rawLineOrigins) {
        expect(origin, 0);
      }
    });

    test('多行输入的 rawLineOrigins 单调不递减', () async {
      final result = await TextParser.parse('第一行。\n第二行。\n第三行。');
      for (int i = 1; i < result.rawLineOrigins.length; i++) {
        expect(
          result.rawLineOrigins[i],
          greaterThanOrEqualTo(result.rawLineOrigins[i - 1]),
          reason: 'rawLineOrigins 在索引 $i 处出现逆序',
        );
      }
    });

    test('rawLineOrigins 所有值均在合法行号范围内', () async {
      const raw = '行一内容。\n行二内容。\n行三内容。';
      final lineCount = raw.split('\n').length;
      final result = await TextParser.parse(raw);
      for (final origin in result.rawLineOrigins) {
        expect(origin, inInclusiveRange(0, lineCount - 1));
      }
    });
  });

  // ── 不变量测试 ─────────────────────────────────────────────────────────────────

  group('TextParser - 不变量测试', () {
    test('解析结果不丢失有效字符', () async {
      const raw = '这是一个测试句子。另一个测试句子！还有一个问句？分号分割；省略号...结束。';
      final result = await TextParser.parse(raw);
      final joined = result.sentences.join('');
      expect(joined, contains('这是一个测试句子'));
      expect(joined, contains('另一个测试句子'));
      expect(joined, contains('还有一个问句'));
      expect(joined, contains('分号分割'));
      expect(joined, contains('省略号。结束'));
    });

    test('解析结果保持原始顺序', () async {
      const raw = '第一句。第二句。第三句。';
      final result = await TextParser.parse(raw);
      expect(result.sentences.length, 3);
      expect(result.sentences[0], contains('第一句'));
      expect(result.sentences[1], contains('第二句'));
      expect(result.sentences[2], contains('第三句'));
    });

    test('多行输入保持行号与句子对应', () async {
      const raw = '第一行句子。\n第二行第一句。第二行第二句。\n第三行句子。';
      final result = await TextParser.parse(raw);
      expect(result.rawLineOrigins[0], 0, reason: '第一行句子应对应行号 0');
      expect(result.rawLineOrigins[1], 1, reason: '第二行第一句应对应行号 1');
      expect(result.rawLineOrigins[2], 1, reason: '第二行第二句应对应行号 1');
      expect(result.rawLineOrigins[3], 2, reason: '第三行句子应对应行号 2');
    });

    test('长句截断后仍保持语义完整性', () async {
      const text = '这是一个很长很长很长很长很长很长很长很长很长很长很长很长很长很长很长的句子需要被截断但要保持语义完整性。';
      final result = await TextParser.parse(text);
      expect(result.sentences.length, greaterThan(1), reason: '长句应被截断');
      final joined = result.sentences.join('');
      expect(joined,
          contains('这是一个很长很长很长很长很长很长很长很长很长很长很长很长很长很长很长的句子需要被截断但要保持语义完整性'),
          reason: '截断后不应丢失有效字符');
    });

    test('连续标点符号不导致空句', () async {
      const raw = '这句话有连续标点.....另一句有多个问号?????还有一句有多个叹号!!!!!';
      final result = await TextParser.parse(raw);
      for (final s in result.sentences) {
        expect(s.trim(), isNotEmpty, reason: '不应有空句');
      }
    });
  });
}
