import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> readContractSample(String name) {
  final file = File('docs/contracts/$name');
  final decoded = jsonDecode(file.readAsStringSync());
  expect(decoded, isA<Map<String, dynamic>>());
  return decoded as Map<String, dynamic>;
}

void main() {
  group('共享 API 契约样例', () {
    test('TTS 成功响应包含短效签名下载 URL', () {
      final sample = readContractSample('tts_success.json');

      expect(sample['status'], 'success');
      expect(sample['url'], isA<String>());
      expect(sample['url'] as String, contains('Expires='));
      expect(sample['url'] as String, contains('Signature='));
    });

    test('TTS 错误响应包含可展示 message', () {
      final sample = readContractSample('tts_error.json');

      expect(sample['status'], 'error');
      expect(sample['message'], isA<String>());
      expect(sample['message'] as String, isNotEmpty);
    });

    test('章节响应遵循分离下载 URL 契约', () {
      final sample = readContractSample('book_chapter_success.json');

      expect(sample['status'], 'success');
      expect(sample['url'], isA<String>());
      expect(sample['url'] as String, endsWith('/books/xiyouji/001.txt'));
    });

    test('目录响应包含章节标题和行号', () {
      final sample = readContractSample('book_catalog_success.json');
      final chapters = sample['chapters'];

      expect(sample['status'], 'success');
      expect(chapters, isA<List<dynamic>>());
      expect(chapters as List<dynamic>, isNotEmpty);
      final first = chapters.first as Map<String, dynamic>;
      expect(first['title'], isA<String>());
      expect(first['lineIndex'], isA<int>());
    });
  });
}
