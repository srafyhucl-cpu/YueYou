import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 阅游一级导航页签。
enum AppShellTab {
  reading,
  library,
  companion,
}

/// 当前一级导航索引。
final appShellTabProvider =
    StateProvider<AppShellTab>((ref) => AppShellTab.reading);
