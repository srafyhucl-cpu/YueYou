import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yueyou/features/audio/domain/tts_audio_state.dart';
import 'package:yueyou/features/audio/providers/tts_audio_notifier.dart';
import 'package:yueyou/features/audio/services/tts_engine_service.dart';
import 'package:yueyou/features/reader/providers/reader_provider.dart';
import 'package:yueyou/core/theme/cyber_colors.dart';
import 'package:yueyou/core/theme/cyber_dimensions.dart';
import 'package:yueyou/core/theme/cyber_shadows.dart';
import 'package:yueyou/core/theme/cyber_text_styles.dart';
import 'package:yueyou/core/utils/cyber_performance_detector.dart';
import 'package:yueyou/core/utils/safe_string.dart';

/// 🔥 赛博 KTV 提词器 - 物理进度驱动版
/// 架构：监听 TtsEngineService 的实时音频进度流，实现 100% 同步的扫光扫字。
class TeleprompterView extends ConsumerStatefulWidget {
  const TeleprompterView({super.key});

  @override
  ConsumerState<TeleprompterView> createState() => _TeleprompterViewState();
}

class _TeleprompterViewState extends ConsumerState<TeleprompterView> {
  String _prevText = '';
  double _totalTextWidth = 0;
  final ScrollController _scrollCtrl = ScrollController();
  Timer? _errorTimer;
  bool _showError = false;

  static final TextStyle _readStyle =
      CyberTextStyles.teleprompterInlineRead.copyWith(
    shadows: [
      Shadow(
        color: CyberColors.hackerBlue.withValues(alpha: 0.5),
        blurRadius: 8,
      ),
    ],
  );

  static const TextStyle _unreadStyle = CyberTextStyles.teleprompterInlineUnread;

  @override
  void dispose() {
    _errorTimer?.cancel();
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _handleErrorState(String? errorMessage) {
    if (errorMessage != null && !_showError) {
      setState(() => _showError = true);
      _errorTimer?.cancel();
      _errorTimer = Timer(const Duration(seconds: 3), () {
        if (mounted) {
          setState(() => _showError = false);
        }
      });
    } else if (errorMessage == null) {
      _showError = false;
      _errorTimer?.cancel();
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
    final engine = ref.watch(ttsEngineProvider);

    _handleErrorState(reader.ttsErrorMessage);

    if (reader.isParsing) {
      return _buildPlaceholder('正在连接神经数据链路...');
    }
    if (reader.sentences.isEmpty) {
      return _buildPlaceholder('等待数据流接入 [ _ ]');
    }

    // 从 ttsState 获取当前正在播放/暂停的文本内容
    final String text = switch (ttsState) {
      TtsAudioPlaying(:final item) => item.textPreview,
      TtsAudioPaused(:final item) => item?.textPreview ?? '',
      _ => '',
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
        final isLowPerf =
            CyberPerformanceDetector.detectLevel() == CyberAnimationLevel.low;

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
                    child: _buildInner(text, isPlaying, halfWidth, engine),
                  )
                : BackdropFilter(
                    filter: ImageFilter.blur(
                      sigmaX: CyberDimensions.blurMedium,
                      sigmaY: CyberDimensions.blurMedium,
                    ),
                    child: Container(
                      color: CyberColors.glassDark,
                      child: _buildInner(text, isPlaying, halfWidth, engine),
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
  ) {
    // 如果没有文本（Idle/Buffering），显示占位或空容器
    if (text.isEmpty) {
      return const SizedBox.shrink();
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

            // 同步滚动
            _syncScroll(progress);

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
                        text: safeSubstring(text, 0, charIndex),
                        style: _readStyle,
                      ),
                      // 未读：暗色
                      TextSpan(
                        text: safeSubstring(text, charIndex, text.length),
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
                    blurRadius: 8,
                    spreadRadius: 1,
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

        // ── 错误提示浮层 ──────────────────────────────
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
                    style: CyberTextStyles.caption.copyWith(
                      color: CyberColors.neonPink,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
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
