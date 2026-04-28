import 'package:flutter_test/flutter_test.dart';
import 'package:yueyou/features/game_2048/domain/tile_model.dart';

void main() {
  group('TileModel - copyWith', () {
    test('copyWith 仅修改 value，id 保持不变', () {
      const t = TileModel(id: 7, value: 2);
      final copied = t.copyWith(value: 4);

      expect(copied.id, 7);
      expect(copied.value, 4);
    });

    test('copyWith 不传 value 时保持原值', () {
      const t = TileModel(id: 7, value: 2);
      final copied = t.copyWith();

      expect(copied.id, 7);
      expect(copied.value, 2);
    });

    test('copyWith 返回新对象（不是同一引用）', () {
      const t = TileModel(id: 1, value: 2);
      final copied = t.copyWith(value: 2);
      // 虽然值相同，但应是不同实例
      expect(identical(t, copied), isFalse);
    });

    test('连续合并：值依次翻倍', () {
      const t = TileModel(id: 1, value: 2);
      final t2 = t.copyWith(value: t.value * 2); // 4
      final t4 = t2.copyWith(value: t2.value * 2); // 8
      final t8 = t4.copyWith(value: t4.value * 2); // 16

      expect(t2.value, 4);
      expect(t4.value, 8);
      expect(t8.value, 16);
      // id 始终不变
      expect(t8.id, 1);
    });
  });

  group('TileModel - 构造', () {
    test('id 为 0 时合法', () {
      const t = TileModel(id: 0, value: 2);
      expect(t.id, 0);
      expect(t.value, 2);
    });

    test('极大 id 与极大 value 均可构造', () {
      const t = TileModel(id: 999999, value: 2048);
      expect(t.id, 999999);
      expect(t.value, 2048);
    });

    test('value 为 4（10% 概率新方块值）可正常构造', () {
      const t = TileModel(id: 5, value: 4);
      expect(t.value, 4);
    });
  });
}
