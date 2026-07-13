import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yueyou/core/theme/cyber_colors.dart';
import 'package:yueyou/features/app_shell/presentation/widgets/companion_shell_page.dart';
import 'package:yueyou/features/app_shell/presentation/widgets/mini_player_bar.dart';
import 'package:yueyou/features/app_shell/providers/app_shell_provider.dart';
import 'package:yueyou/features/library/presentation/screens/library_screen.dart';
import 'package:yueyou/features/reader/presentation/screens/reading_home_screen.dart';

/// 听读优先的一级导航壳。
///
/// 通过 [IndexedStack] 保留三个根页面的状态；切换页签只更新索引，不触发
/// 播放、暂停、停止、刷新会话或章节加载。
class YueYouShell extends ConsumerWidget {
  /// 可注入页面集合，供壳层 Widget 测试使用；生产默认使用正式页面。
  final List<Widget>? pages;

  /// 是否渲染跨页播放插槽，测试壳层时可关闭以隔离音频平台依赖。
  final bool showMiniPlayer;

  const YueYouShell({
    super.key,
    this.pages,
    this.showMiniPlayer = true,
  }) : assert(pages == null || pages.length == 3);

  List<Widget> _defaultPages() {
    return const [
      ReadingHomeScreen(),
      LibraryScreen(showCloseButton: false),
      CompanionShellPage(),
    ];
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedTab = ref.watch(appShellTabProvider);
    final shellPages = pages ?? _defaultPages();

    return Scaffold(
      backgroundColor: CyberColors.background,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Expanded(
              child: IndexedStack(
                index: selectedTab.index,
                children: shellPages,
              ),
            ),
            if (showMiniPlayer) const MiniPlayerBar(),
          ],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: selectedTab.index,
        onDestinationSelected: (index) {
          ref.read(appShellTabProvider.notifier).state =
              AppShellTab.values[index];
        },
        backgroundColor: CyberColors.panelBackground,
        indicatorColor: CyberColors.neonCyan.withValues(alpha: 0.16),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.headphones_outlined),
            selectedIcon: Icon(Icons.headphones),
            label: '听读',
          ),
          NavigationDestination(
            icon: Icon(Icons.menu_book_outlined),
            selectedIcon: Icon(Icons.menu_book),
            label: '书架',
          ),
          NavigationDestination(
            icon: Icon(Icons.auto_awesome_outlined),
            selectedIcon: Icon(Icons.auto_awesome),
            label: '陪伴',
          ),
        ],
      ),
    );
  }
}
