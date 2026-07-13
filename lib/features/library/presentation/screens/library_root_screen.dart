import 'package:flutter/material.dart';
import 'package:yueyou/features/library/presentation/screens/library_screen.dart';

/// 书架根页面外壳。
///
/// 根导航只依赖此页面入口，书架列表、导入、删除和进度仍全部复用既有
/// [LibraryScreen]，不创建第二套书架仓储或正文状态。
class LibraryRootScreen extends StatelessWidget {
  const LibraryRootScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const LibraryScreen(showCloseButton: false);
  }
}
