import 'package:flutter_test/flutter_test.dart';
import 'package:yueyou/features/library/domain/book_model.dart';

void main() {
  group('BookModel', () {
    test('toJson / fromJson 往返一致（含默认值）', () {
      const model = BookModel(id: 1, title: '测试书.txt', total: 10, cursor: 3);
      final json = model.toJson();
      final from = BookModel.fromJson(json);

      expect(from.id, 1);
      expect(from.title, '测试书.txt');
      expect(from.total, 10);
      expect(from.cursor, 3);
    });

    test('fromJson 缺省字段时使用默认值', () {
      final from = BookModel.fromJson({
        'id': 2,
        'title': 'A.txt',
      });

      expect(from.total, 0);
      expect(from.cursor, 0);
      expect(from.chapters, isEmpty);
    });

    test('copyWith 仅覆盖指定字段', () {
      const base = BookModel(id: 1, title: 'A.txt', total: 9, cursor: 1);
      final copied = base.copyWith(cursor: 7, chapters: const [
        ChapterModel(title: '第一章', lineIndex: 0),
      ]);

      expect(copied.id, base.id);
      expect(copied.title, base.title);
      expect(copied.total, base.total);
      expect(copied.cursor, 7);
      expect(copied.chapters.length, 1);
    });

    test('displayTitle 去除 .txt 后缀（大小写不敏感）', () {
      const a = BookModel(id: 1, title: 'Hello.TXT', total: 1);
      expect(a.displayTitle, 'Hello');
    });

    test('coverChar 为 displayTitle 首字', () {
      const a = BookModel(id: 1, title: '你好.txt', total: 1);
      expect(a.coverChar, '你');
    });

    test('coverChar 在标题为空时返回 ?', () {
      const a = BookModel(id: 1, title: '', total: 1);
      expect(a.coverChar, '?');
    });
  });

  group('ChapterModel', () {
    test('toJson / fromJson 往返一致', () {
      const c = ChapterModel(title: '第一章', lineIndex: 7);
      final json = c.toJson();
      final from = ChapterModel.fromJson(json);

      expect(from.title, '第一章');
      expect(from.lineIndex, 7);
    });
  });
}
