// ignore_for_file: avoid_print
import 'dart:io';

void main() async {
  // 原文件名 -> 概括性中文名
  final files = {
    'handoff_status.md': '重构交接状态与计划',
    'optimization_tasks.md': '系统深度优化任务书_阶段一',
    'optimization_tasks2.md': '系统深度优化任务书_阶段二',
    'optimization_tasks3.md': 'TTS发声引擎重构任务书',
    'v1_release_tasks.md': 'V1商业化发版合规任务书',
  };

  int successCount = 0;
  final dir = Directory('DevelopmentPlan');

  if (!await dir.exists()) {
    print('❌ 找不到 DevelopmentPlan 文件夹，请确认之前是否成功执行。');
    return;
  }

  for (final entry in files.entries) {
    final originalFile = entry.key;
    final cnName = entry.value;

    // 模糊匹配：找到当前 DevelopmentPlan 里面包含了中文名称（并且是以 .md 结尾）的文件
    var targetFile = File('');
    bool found = false;

    final list = dir.listSync();
    for (var f in list) {
      if (f.path.contains(cnName) && f.path.endsWith('.md')) {
        targetFile = File(f.path);
        found = true;
        break;
      }
    }

    if (!found) continue;

    try {
      // 核心：调用底层的 git 进程来读取该文件历史版本里的最后一次提交时间 (格式：YYYYMMDD)
      final result = await Process.run('git', [
        'log',
        '-1',
        '--format=%cd',
        '--date=format:%Y%m%d',
        '--',
        originalFile
      ]);

      String gitDate = result.stdout.toString().trim();
      
      // 对于没有查到记录的情况，提供脱敏报错
      if (gitDate.isEmpty) {
        print('⚠️ 警告: $originalFile 以前可能并未提交进入 Git 历史线，提取不到版本时间。');
        continue; 
      }

      final newName = '${cnName}_$gitDate.md';
      final newPath = 'DevelopmentPlan/$newName';

      // 剔除路径分隔符差异，进行对比
      if (targetFile.absolute.path != File(newPath).absolute.path) {
        await targetFile.rename(newPath);
        print('✅ 修正成功: 依据 Git 黑匣记录 -> $newPath');
        successCount++;
      }
    } catch (e) {
      print('❌ 操作执行失败: $e');
    }
  }

  print('\n🎯 Git 历史线重缝完毕！依靠真实的 Git Commit 溯源修正了 $successCount 份文档。');
}
