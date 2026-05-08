import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yueyou/features/audio/domain/tts_audio_state.dart';
import 'package:yueyou/features/audio/providers/tts_audio_notifier.dart';
import 'package:yueyou/features/audio/services/tts_engine_service.dart';
import 'package:yueyou/features/reader/domain/chapter_load_state.dart';
import 'package:yueyou/features/reader/providers/reader_provider.dart';
import 'package:yueyou/core/theme/cyber_colors.dart';
import 'package:yueyou/core/theme/cyber_dimensions.dart';
import 'package:yueyou/core/theme/cyber_shadows.dart';
import 'package:yueyou/core/theme/cyber_text_styles.dart';
import 'package:yueyou/core/utils/cyber_performance_detector.dart';
import 'package:yueyou/core/utils/safe_string.dart';
import 'package:yueyou/features/settings/providers/settings_provider.dart';

/// 🔥 赛博 KTV 提词器 - 物理进度驱动版
/// 架构：监听 TtsEngineService 的实时音频进度流，实现 100% 同步的扫光扫字。
class TeleprompterView extends ConsumerStatefulWidget {
  const TeleprompterView({super.key});

  @override
  ConsumerState<TeleprompterView> createState() => _TeleprompterViewState();
}

class _TeleprompterViewState extends ConsumerState<TeleprompterView>
    with SingleTickerProviderStateMixin {
  String _prevText = '';
  double _totalTextWidth = 0;
  final ScrollController _scrollCtrl = ScrollController();
  Timer? _errorTimer;
  StreamSubscription<double>? _progressSub; // 独立进度订阅
  bool _showError = false;
  late final AnimationController _skeletonCtrl;

  static final TextStyle _readStyle =
      CyberTextStyles.teleprompterInlineRead.copyWith(
    shadows: [
      Shadow(
        color: CyberColors.hackerBlue.withValues(alpha: 0.5),
        blurRadius: CyberDimensions.glowBlurRadius,
      ),
    ],
  );

  static const TextStyle _unreadStyle =
      CyberTextStyles.teleprompterInlineUnread;

  @override
  void initState() {
    super.initState();
    _initProgressSubscription();
    _skeletonCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    );
  }

  void _initProgressSubscription() {
    _progressSub?.cancel();
    // 监听全局进度流，直接驱动滚动而不触发 rebuild
    _progressSub =
        ref.read(ttsEngineProvider).progressStream.listen((progress) {
      final ttsState = ref.read(ttsAudioProvider);
      if (ttsState is TtsAudioPlaying) {
        _syncScroll(progress);
      }
    });
  }

  @override
  void dispose() {
    _progressSub?.cancel();
    _errorTimer?.cancel();
    _scrollCtrl.dispose();
    _skeletonCtrl.dispose();
    super.dispose();
  }

  /// 处理 TTS 错误条幅的显隐状态。
  ///
  /// P0-1：本方法由 [build] 同步调用，必须避免在 build 流程中执行 `setState`
  /// 触发 `setState() called during build` 框架断言。
  /// 因此所有状态变更都包裹在 `addPostFrameCallback` 内，等待当前帧绘制结束后再切换。
  void _handleErrorState(String? errorMessage) {
    if (errorMessage != null && !_showError) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _showError) return;
        setState(() => _showError = true);
        _errorTimer?.cancel();
        _errorTimer = Timer(const Duration(seconds: 3), () {
          if (!mounted) return;
          setState(() => _showError = false);
        });
      });
    } else if (errorMessage == null && _showError) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_showError) return;
        setState(() => _showError = false);
        _errorTimer?.cancel();
      });
    }
  }

  void _syncScroll(double progress) {
    if (!mounted || !_scrollCtrl.hasClients || _totalTextWidth <= 0) return;
    final target = (progress * _totalTextWidth)
        .clamp(0.0, _scrollCtrl.position.maxScrollExtent);
    if (_scrollCtrl.offset != target) {
      _scrollCtrl.jumpTo(target);
    }
  }

  void _onSentenceChanged(String text) {
    _prevText = text;
    final tp = TextPainter(
      text: TextSpan(text: text, style: _readStyle),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: double.infinity);
    _totalTextWidth = tp.width;

    // 立即重置滚动位置
    if (_scrollCtrl.hasClients) {
      _scrollCtrl.jumpTo(0.0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final reader = ref.watch(readerProvider);
    final ttsState = ref.watch(ttsAudioProvider);
    final engine = ref.read(ttsEngineProvider);

    _handleErrorState(reader.ttsErrorMessage);

    // 骨架屏动画仅在缓冲状态运行，其余状态停止以节省 GPU
    if (ttsState is TtsAudioBuffering) {
      if (!_skeletonCtrl.isAnimating) _skeletonCtrl.repeat();
    } else {
      if (_skeletonCtrl.isAnimating) _skeletonCtrl.stop();
    }

    if (reader.isParsing) {
      return _buildPlaceholder('正在连接神经数据链路...');
    }

    // ── 分章懒加载状态处理 ────────────────────────────────────────
    if (reader.isDefaultBookMode) {
      if (reader.chapterLoadState == ChapterLoadState.loading &&
          reader.sentences.isEmpty) {
        return _buildPlaceholder('正在同步云端卷宗...');
      }
      if (reader.chapterLoadState == ChapterLoadState.error &&
          reader.sentences.isEmpty) {
        return _buildChapterError(reader.currentChapterIndex ?? 0);
      }
    }

    // 从 ttsState 获取当前正在播放/暂停的文本内容
    // Idle/Buffering/Error 时回退到 reader.currentSentence 展示已加载文本
    final String text = switch (ttsState) {
      TtsAudioPlaying(:final item) => item.textPreview,
      TtsAudioPaused(:final item) => item?.textPreview ?? '',
      _ => reader.currentSentence ?? '',
    };

    if (text.isNotEmpty && text != _prevText) {
      // 在构建后重置，避免 build 期间调用 jumpTo
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _onSentenceChanged(text);
      });
    }

    final bool isPlaying = ttsState is TtsAudioPlaying;

    return LayoutBuilder(
      builder: (context, constraints) {
        final halfWidth = constraints.maxWidth / 2;
        final isLowPerf = ref.watch(settingsProvider).currentAnimationLevel ==
            CyberAnimationLevel.low;

        return Container(
          height: CyberDimensions.teleprompterHeight,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(CyberDimensions.radiusL),
            border: Border.all(
              color: CyberColors.neonCyan.withValues(alpha: 0.3),
              width: CyberDimensions.borderNormal,
            ),
            boxShadow: CyberShadows.floating,
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(
              CyberDimensions.radiusL - CyberDimensions.borderNormal,
            ),
            child: isLowPerf
                ? Container(
                    color: CyberColors.glassDark.withValues(alpha: 0.95),
                    child: _buildInner(
                      text,
                      isPlaying,
                      halfWidth,
                      engine,
                      ttsState,
                      isChapterError: reader.isDefaultBookMode &&
                          reader.chapterLoadState == ChapterLoadState.error,
                      chapterIndex: reader.currentChapterIndex ?? 0,
                    ),
                  )
                : BackdropFilter(
                    filter: ImageFilter.blur(
                      sigmaX: CyberDimensions.blurMedium,
                      sigmaY: CyberDimensions.blurMedium,
                    ),
                    child: Container(
                      color: CyberColors.glassDark,
                      child: _buildInner(
                        text,
                        isPlaying,
                        halfWidth,
                        engine,
                        ttsState,
                        isChapterError: reader.isDefaultBookMode &&
                            reader.chapterLoadState == ChapterLoadState.error,
                        chapterIndex: reader.currentChapterIndex ?? 0,
                      ),
                    ),
                  ),
          ),
        );
      },
    );
  }

  Widget _buildInner(
    String text,
    bool isPlaying,
    double halfWidth,
    TtsEngineService engine,
    TtsAudioState ttsState, {
    bool isChapterError = false,
    int chapterIndex = 0,
  }) {
    if (text.isEmpty) {
      // Idle：未启动播放器
      if (ttsState is TtsAudioIdle) {
        return _buildPlaceholder('数据流未开启');
      }
      // Buffering / Paused 等：已启动，正在加载
      return _buildSkeletonRows();
    }

    return Stack(
      clipBehavior: Clip.hardEdge,
      children: [
        StreamBuilder<double>(
          stream: engine.progressStream,
          initialData: 0.0,
          builder: (context, snapshot) {
            final double progress = isPlaying ? (snapshot.data ?? 0.0) : 0.0;
            final charIndex =
                (progress * text.length).floor().clamp(0, text.length);

            // 💡 优化：不再在此处调用 _syncScroll，由 _progressSub 独立驱动
            return SingleChildScrollView(
              controller: _scrollCtrl,
              scrollDirection: Axis.horizontal,
              physics: const NeverScrollableScrollPhysics(),
              padding: EdgeInsets.symmetric(horizontal: halfWidth),
              child: Center(
                child: RichText(
                  text: TextSpan(
                    children: [
                      // 已读：亮青色 + 发光
                      TextSpan(
                        text: text.safeSubstring(0, charIndex),
                        style: _readStyle,
                      ),
                      // 未读：暗色
                      TextSpan(
                        text: text.safeSubstring(charIndex, text.length),
                        style: _unreadStyle.copyWith(
                          color: CyberColors.whiteMuted.withValues(
                            alpha: isPlaying ? 0.4 : 0.65,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),

        // ── 中心读取位置指示线（仅播放时显示）────────
        if (isPlaying)
          Positioned(
            left: halfWidth - 1,
            top: CyberDimensions.spacingS,
            bottom: CyberDimensions.spacingS,
            child: Container(
              width: CyberDimensions.radiusXS,
              decoration: BoxDecoration(
                borderRadius:
                    BorderRadius.circular(CyberDimensions.radiusXS / 2),
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    CyberColors.neonCyan.withValues(alpha: 0.0),
                    CyberColors.neonCyan,
                    CyberColors.neonCyan,
                    CyberColors.neonCyan.withValues(alpha: 0.0),
                  ],
                  stops: const [0.0, 0.25, 0.75, 1.0],
                ),
                boxShadow: [
                  BoxShadow(
                    color: CyberColors.neonCyan.withValues(alpha: 0.7),
                    blurRadius: CyberDimensions.glowBlurRadius,
                    spreadRadius: CyberDimensions.glowSpreadRadius,
                  ),
                ],
              ),
            ),
          ),

        // ── 两端渐隐遮罩 ────────────
        Positioned.fill(
          child: IgnorePointer(
            child: Row(
              children: [
                Container(
                  width: CyberDimensions.teleprompterMaskWidth,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      colors: [
                        CyberColors.glassDark,
                        CyberColors.glassDark.withValues(alpha: 0),
                      ],
                    ),
                  ),
                ),
                const Spacer(),
                Container(
                  width: CyberDimensions.teleprompterMaskWidth,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.centerRight,
                      end: Alignment.centerLeft,
                      colors: [
                        CyberColors.glassDark,
                        CyberColors.glassDark.withValues(alpha: 0),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),

        // ── 分章加载失败浮层（内容非空时也能重试）──────────
        if (isChapterError)
          Positioned.fill(
            child: GestureDetector(
              onTap: () => ref.read(readerProvider).loadChapter(chapterIndex),
              child: Container(
                color: CyberColors.background.withValues(alpha: 0.88),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '云端卷宗同步失败',
                        style: CyberTextStyles.teleprompterErrorTitle.copyWith(
                          color: CyberColors.neonPink,
                        ),
                      ),
                      const SizedBox(height: CyberDimensions.spacingXS),
                      Text(
                        '[ 点击重试 ]',
                        style: CyberTextStyles.teleprompterErrorHint.copyWith(
                          color: CyberColors.neonCyan,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

        // ── TTS 错误提示浮层 ──────────────────────────────
        if (_showError && ref.read(readerProvider).ttsErrorMessage != null)
          Positioned.fill(
            key: const ValueKey('teleprompter_error_tip'),
            child: GestureDetector(
              onTap: () {
                _errorTimer?.cancel();
                setState(() => _showError = false);
                ref.read(readerProvider).clearTtsError();
              },
              child: Container(
                color: CyberColors.background.withValues(alpha: 0.9),
                child: Center(
                  child: Text(
                    '数据链路中断: ${ref.read(readerProvider).ttsErrorMessage}',
                    textAlign: TextAlign.center,
                    style: CyberTextStyles.teleprompterErrorTitle.copyWith(
                      color: CyberColors.neonPink,
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  /// 章节加载失败空态视图（全屏占位 + 点击重试）
  Widget _buildChapterError(int chapterIndex) {
    return SizedBox(
      height: CyberDimensions.teleprompterHeight,
      child: GestureDetector(
        onTap: () => ref.read(readerProvider).loadChapter(chapterIndex),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '云端卷宗同步失败',
                style: CyberTextStyles.teleprompterErrorTitle.copyWith(
                  color: CyberColors.neonPink,
                ),
              ),
              const SizedBox(height: CyberDimensions.spacingXS),
              Text(
                '[ 点击重试 ]',
                style: CyberTextStyles.teleprompterErrorHint.copyWith(
                  color: CyberColors.neonCyan.withValues(alpha: 0.7),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSkeletonRows() {
    return SizedBox(
      height: CyberDimensions.teleprompterHeight,
      child: Center(
        child: AnimatedBuilder(
          animation: _skeletonCtrl,
          builder: (_, __) => LayoutBuilder(
            builder: (ctx, constraints) {
              final totalWidth = constraints.maxWidth;
              const shimmerWidth = CyberDimensions.shimmerWidth;
              final offset = _skeletonCtrl.value * (totalWidth + shimmerWidth) -
                  shimmerWidth;
              const innerHeight = CyberDimensions.teleprompterHeight -
                  CyberDimensions.spacingS * 2;
              return ClipRect(
                child: SizedBox(
                  width: totalWidth,
                  height: innerHeight,
                  child: Stack(
                    children: [
                      // 底色横条
                      Container(
                        width: totalWidth,
                        height: innerHeight,
                        decoration: BoxDecoration(
                          borderRadius:
                              BorderRadius.circular(CyberDimensions.radiusXS),
                          color: CyberColors.neonCyan.withValues(alpha: 0.06),
                        ),
                      ),
                      // 扫光
                      Positioned(
                        top: 0,
                        bottom: 0,
                        left: offset,
                        child: Container(
                          width: shimmerWidth,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                CyberColors.neonCyan.withValues(alpha: 0.0),
                                CyberColors.neonCyan.withValues(alpha: 0.35),
                                CyberColors.neonCyan.withValues(alpha: 0.0),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildPlaceholder(String msg) {
    return SizedBox(
      height: CyberDimensions.teleprompterHeight,
      child: Center(
        child: Text(
          msg,
          style: CyberTextStyles.teleprompterPlaceholder.copyWith(
            color: CyberColors.whiteMuted.withValues(alpha: 0.5),
          ),
        ),
      ),
    );
  }
}
