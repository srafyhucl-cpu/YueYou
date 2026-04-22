// ignore_for_file: avoid_print
import 'dart:io';

void main() async {
  final dir = Directory('DevelopmentPlan');
  if (!await dir.exists()) {
    print('❌ 找不到 DevelopmentPlan 文件夹');
    return;
  }

  // 获取所有 md 文件
  final list = dir.listSync().whereType<File>().toList();
  int successCount = 0;

  for (final file in list) {
    if (!file.path.endsWith('.md')) continue;

    final basename = file.uri.pathSegments.last; // 例如 "重构交接状态与计划_20260330.md"
    
    // 用正则提取名称部分与日期的后缀
    final regExp = RegExp(r'^(.*)_(\d{8})\.md$');
    final match = regExp.firstMatch(basename);
    
    if (match != null) {
      final namePart = match.group(1)!;
      final datePart = match.group(2)!;
      
      // 直接把日期甩到最前面，天然迎合操作系统的字符级字典序排序
      final newName = '${datePart}_$namePart.md';
      final newPath = 'DevelopmentPlan/$newName';
      
      try {
        await file.rename(newPath);
        print('✅ 排序重构: $basename -> $newName');
        successCount++;
      } catch (e) {
        print('❌ 无法重命名 $basename: $e');
      }
    } else {
      final alreadySortedRegExp = RegExp(r'^(\d{8})_.*\.md$');
      if (alreadySortedRegExp.hasMatch(basename)) {
         print('⏭️ 跳过: $basename 已经处于排序状态。');
      }
    }
  }

  print('\n🎯 文件时间戳前置完毕，成功重排了 $successCount 份文档！');
}
