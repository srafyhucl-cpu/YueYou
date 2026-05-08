import 'package:flutter_test/flutter_test.dart';
import 'package:yueyou/core/constants/book_constants.dart';
import 'package:yueyou/features/audio/presentation/widgets/cyber_player_console.dart';
import 'package:yueyou/features/library/domain/book_model.dart';

/// T-5 / P1-3 回归用例：
/// `resolveNovelTitle` 必须正确处理默认书 key 与普通书 id 的双轨标识。
///
/// 旧实现 _getNovelTitle 中：
///   bookshelf.shelf.firstWhere((b) => b.id.toString() == bookId, ...)
/// 默认书 currentBookId='xiyouji' 但 BookModel.id=999 → 永远不匹配 →
/// 标题 fallback 为'阅游'，用户体验断裂。
void main() {
  group('resolveNovelTitle - P1-3 回归', () {
    test('null bookId 兜底返回"阅游"', () {
      expect(resolveNovelTitle(null, const []), '阅游');
    });

    test('默认书 key 直接命中 BookConstants.defaultBookTitle', () {
      // 注意：故意传入空 shelf，模拟书架尚未加载完成时的极端场景，
      // 仍然必须返回 "西游记"。
      expect(
        resolveNovelTitle(BookConstants.defaultBookKey, const []),
        BookConstants.defaultBookTitle,
      );
    });

    test('默认书 key 即使书架包含同 id 的其它书也优先返回内置标题', () {
      // 即便有人把 id=999 的书改名注入书架，也以默认书常量为准。
      const evilShelf = [
        BookModel(id: BookConstants.defaultBookId, title: '伪装书.txt', total: 1),
      ];
      expect(
        resolveNovelTitle(BookConstants.defaultBookKey, evilShelf),
        BookConstants.defaultBookTitle,
      );
    });

    test('普通书按 id.toString() 匹配，去除 .txt 后缀显示', () {
      const shelf = [
        BookModel(id: 7, title: '斗破苍穹.txt', total: 1500),
        BookModel(id: 12, title: '诡秘之主.txt', total: 1300),
      ];
      expect(resolveNovelTitle('7', shelf), '斗破苍穹');
      expect(resolveNovelTitle('12', shelf), '诡秘之主');
    });

    test('未匹配到任何书时回退到"阅游"，绝不抛异常', () {
      const shelf = [
        BookModel(id: 1, title: 'A.txt', total: 100),
      ];
      expect(resolveNovelTitle('999', shelf), '阅游');
    });
  });
}
