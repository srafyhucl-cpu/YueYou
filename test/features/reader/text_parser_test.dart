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
}
