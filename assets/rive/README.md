# Rive 动画资源目录

## 当前使用的 Rive 文件

### xiaoyo.riv
- **来源**: [Lil Guy - Rive Community](https://rive.app/marketplace/18912-35694-lil-guy/)
- **用途**: 阅游 2048 游戏吉祥物 XIAOYO
- **状态机**: 需要确认是否包含以下输入
  - `lookX` (Number): 眼球水平偏移 [-1, 1]
  - `lookY` (Number): 眼球垂直偏移 [-1, 1]
  - `onMerge` (Trigger): 合并方块时触发欢呼
  - `isGameOver` (Boolean): 游戏结束状态

## 下载步骤
1. 访问 https://rive.app/marketplace/18912-35694-lil-guy/
2. 点击 "Download" 下载 `.riv` 文件
3. 重命名为 `xiaoyo.riv`
4. 放到本目录下

## 注意事项
- 如果原始文件的状态机输入名称不匹配，需要在 Rive Editor 中调整
- 或者修改 `board_mascot_rive.dart` 中的输入名称映射
