/// 2048 游戏方块模型 (TileModel)
/// 溯源：对应旧版 GameEngine.js 中的 tile 对象定义 { id, value }
class TileModel {
  final int id;
  final int value;

  const TileModel({
    required this.id,
    required this.value,
  });

  /// 复制并修改值（用于合并）
  /// 溯源：对应旧版 GameEngine.js L66 (M.value = M.value * 2)
  TileModel copyWith({int? value}) {
    return TileModel(
      id: id,
      value: value ?? this.value,
    );
  }
}
