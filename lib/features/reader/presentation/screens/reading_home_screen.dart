import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yueyou/core/theme/cyber_colors.dart';
import 'package:yueyou/core/theme/cyber_dimensions.dart';
import 'package:yueyou/core/theme/cyber_text_styles.dart';
import 'package:yueyou/features/app_shell/providers/app_shell_provider.dart';
import 'package:yueyou/features/audio/providers/tts_audio_notifier.dart';
import 'package:yueyou/features/reader/domain/reading_home_view_state.dart';
import 'package:yueyou/features/reader/providers/reading_home_view_provider.dart';
import 'package:yueyou/features/reader/providers/reader_provider.dart';

/// 阅读优先首屏。
///
/// 页面只消费 [ReadingHomeViewState] 并把用户操作转发给现有 Provider，不在
/// build 中加载书籍、创建音频会话或写入任何持久化数据。
class ReadingHomeScreen extends ConsumerWidget {
  const ReadingHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(readingHomeViewProvider);
    return Scaffold(
      backgroundColor: CyberColors.background,
      appBar: AppBar(
        title: const Text('听读', style: CyberTextStyles.screenTitle),
        backgroundColor: CyberColors.background,
        foregroundColor: CyberColors.neonCyan,
      ),
      body: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(CyberDimensions.spacingL),
          child: _buildStateView(context, ref, state),
        ),
      ),
    );
  }

  Widget _buildStateView(
    BuildContext context,
    WidgetRef ref,
    ReadingHomeViewState state,
  ) {
    return switch (state.status) {
      ReadingHomeStatus.empty => _buildEmptyView(context, ref),
      ReadingHomeStatus.ready => _buildBookView(
          context,
          ref,
          state,
          title: '准备继续',
          actionIcon: Icons.play_arrow_rounded,
        ),
      ReadingHomeStatus.buffering => _buildBufferingView(context, ref, state),
      ReadingHomeStatus.playing => _buildBookView(
          context,
          ref,
          state,
          title: '正在听读',
          actionIcon: Icons.pause_rounded,
        ),
      ReadingHomeStatus.paused => _buildBookView(
          context,
          ref,
          state,
          title: '已暂停',
          actionIcon: Icons.play_arrow_rounded,
        ),
      ReadingHomeStatus.recoverableError =>
        _buildErrorView(context, ref, state),
      ReadingHomeStatus.completed => _buildCompletedView(context, ref, state),
    };
  }

  Widget _buildEmptyView(BuildContext context, WidgetRef ref) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.headphones_outlined,
            size: CyberDimensions.iconL * 2,
            color: CyberColors.neonCyan,
          ),
          const SizedBox(height: CyberDimensions.spacingL),
          const Text('从一本书开始', style: CyberTextStyles.screenTitle),
          const SizedBox(height: CyberDimensions.spacingS),
          const Text(
            '正文、进度和听读记录默认只保存在本机。',
            textAlign: TextAlign.center,
            style: CyberTextStyles.bodySmall,
          ),
          const SizedBox(height: CyberDimensions.spacingL),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () => _openLibrary(ref),
              icon: const Icon(Icons.folder_open_outlined),
              label: const Text('导入本地书'),
              style: FilledButton.styleFrom(
                backgroundColor: CyberColors.neonCyan,
                foregroundColor: CyberColors.background,
                padding: const EdgeInsets.symmetric(
                  vertical: CyberDimensions.spacingMS,
                ),
              ),
            ),
          ),
          const SizedBox(height: CyberDimensions.spacingS),
          TextButton.icon(
            onPressed: () => _openLibrary(ref),
            icon: const Icon(Icons.menu_book_outlined),
            label: const Text('查看书架'),
          ),
        ],
      ),
    );
  }

  Widget _buildBookView(
    BuildContext context,
    WidgetRef ref,
    ReadingHomeViewState state, {
    required String title,
    required IconData actionIcon,
  }) {
    return ListView(
      children: [
        Text(title, style: CyberTextStyles.sectionLabel),
        const SizedBox(height: CyberDimensions.spacingS),
        Text(
          state.bookTitle,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: CyberTextStyles.screenTitle.copyWith(
            color: CyberColors.whiteHigh,
          ),
        ),
        const SizedBox(height: CyberDimensions.spacingXS),
        Text(state.chapterTitle, style: CyberTextStyles.tileSubtitle),
        const SizedBox(height: CyberDimensions.spacingL),
        LinearProgressIndicator(
          value: state.readingProgress.clamp(0.0, 1.0).toDouble(),
          minHeight: CyberDimensions.borderThick,
          backgroundColor: CyberColors.whiteSubtle,
          valueColor: const AlwaysStoppedAnimation(CyberColors.neonCyan),
        ),
        const SizedBox(height: CyberDimensions.spacingS),
        Text(
          '${(state.readingProgress * 100).toStringAsFixed(1)}% 已读',
          style: CyberTextStyles.caption,
        ),
        const SizedBox(height: CyberDimensions.spacingXL),
        _buildSentencePanel(state),
        const SizedBox(height: CyberDimensions.spacingXL),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: () => _togglePlayback(ref),
            icon: Icon(actionIcon),
            label: Text(state.primaryActionLabel),
            style: FilledButton.styleFrom(
              backgroundColor: CyberColors.neonCyan,
              foregroundColor: CyberColors.background,
              padding: const EdgeInsets.symmetric(
                vertical: CyberDimensions.spacingMS,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildBufferingView(
    BuildContext context,
    WidgetRef ref,
    ReadingHomeViewState state,
  ) {
    return ListView(
      children: [
        const Text('正在准备下一句', style: CyberTextStyles.sectionLabel),
        const SizedBox(height: CyberDimensions.spacingS),
        Text(state.bookTitle, style: CyberTextStyles.screenTitle),
        const SizedBox(height: CyberDimensions.spacingXS),
        Text(state.chapterTitle, style: CyberTextStyles.tileSubtitle),
        const SizedBox(height: CyberDimensions.spacingL),
        LinearProgressIndicator(
          value: state.bufferingProgress.clamp(0.0, 1.0).toDouble(),
          minHeight: CyberDimensions.borderThick,
          backgroundColor: CyberColors.whiteSubtle,
          valueColor: const AlwaysStoppedAnimation(CyberColors.neonPink),
        ),
        const SizedBox(height: CyberDimensions.spacingL),
        _buildSentencePanel(state),
        const SizedBox(height: CyberDimensions.spacingXL),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () => ref.read(ttsAudioProvider.notifier).pause(),
            icon: const Icon(Icons.stop_circle_outlined),
            label: Text(state.primaryActionLabel),
          ),
        ),
      ],
    );
  }

  Widget _buildErrorView(
    BuildContext context,
    WidgetRef ref,
    ReadingHomeViewState state,
  ) {
    return ListView(
      children: [
        const Icon(
          Icons.cloud_off_outlined,
          size: CyberDimensions.iconL * 2,
          color: CyberColors.neonPink,
        ),
        const SizedBox(height: CyberDimensions.spacingL),
        const Text('朗读需要恢复', style: CyberTextStyles.screenTitle),
        const SizedBox(height: CyberDimensions.spacingS),
        Text(
          state.errorMessage ?? '音频服务暂时不可用，请重试。',
          style: CyberTextStyles.bodySmall,
        ),
        const SizedBox(height: CyberDimensions.spacingL),
        _buildSentencePanel(state),
        const SizedBox(height: CyberDimensions.spacingXL),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: state.canRecover
                ? () => ref.read(ttsAudioProvider.notifier).recover()
                : null,
            icon: const Icon(Icons.refresh),
            label: Text(state.primaryActionLabel),
            style: FilledButton.styleFrom(
              backgroundColor: CyberColors.neonPink,
              foregroundColor: CyberColors.background,
              padding: const EdgeInsets.symmetric(
                vertical: CyberDimensions.spacingMS,
              ),
            ),
          ),
        ),
        Align(
          alignment: Alignment.center,
          child: TextButton.icon(
            onPressed: () => _openLibrary(ref),
            icon: const Icon(Icons.menu_book_outlined),
            label: const Text('返回书架'),
          ),
        ),
      ],
    );
  }

  Widget _buildCompletedView(
    BuildContext context,
    WidgetRef ref,
    ReadingHomeViewState state,
  ) {
    return ListView(
      children: [
        const Icon(
          Icons.auto_awesome,
          size: CyberDimensions.iconL * 2,
          color: CyberColors.neonGreen,
        ),
        const SizedBox(height: CyberDimensions.spacingL),
        const Text('这一页已听完', style: CyberTextStyles.screenTitle),
        const SizedBox(height: CyberDimensions.spacingS),
        Text(state.bookTitle, style: CyberTextStyles.tileTitle),
        const SizedBox(height: CyberDimensions.spacingXL),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: () => _openLibrary(ref),
            icon: const Icon(Icons.menu_book_outlined),
            label: Text(state.primaryActionLabel),
            style: FilledButton.styleFrom(
              backgroundColor: CyberColors.neonGreen,
              foregroundColor: CyberColors.background,
              padding: const EdgeInsets.symmetric(
                vertical: CyberDimensions.spacingMS,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSentencePanel(ReadingHomeViewState state) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(CyberDimensions.spacingL),
      decoration: BoxDecoration(
        color: CyberColors.panelBackground,
        border: Border.all(
          color: CyberColors.neonCyan.withValues(alpha: 0.35),
          width: CyberDimensions.borderNormal,
        ),
        borderRadius: BorderRadius.circular(CyberDimensions.radiusM),
      ),
      child: Text(
        state.currentSentence ?? '当前句段将在开始听读后显示。',
        maxLines: 5,
        overflow: TextOverflow.ellipsis,
        style: CyberTextStyles.bodySmall.copyWith(
          color: CyberColors.whiteHigh,
          height: 1.6,
        ),
      ),
    );
  }

  void _togglePlayback(WidgetRef ref) {
    ref.read(readerProvider).toggleTTS();
  }

  void _openLibrary(WidgetRef ref) {
    ref.read(appShellTabProvider.notifier).state = AppShellTab.library;
  }
}
