import 'package:flutter_test/flutter_test.dart';
import 'package:yueyou/features/game_2048/domain/tile_model.dart';

void main() {
  group('TileModel', () {
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
  });
}
