import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:yueyou/features/audio/services/tts_engine_service.dart';
import 'package:yueyou/features/reader/providers/reader_provider.dart';
import 'package:yueyou/core/theme/cyber_colors.dart';
import 'package:yueyou/core/theme/cyber_dimensions.dart';
import 'package:yueyou/core/theme/cyber_shadows.dart';
import 'package:yueyou/core/theme/cyber_text_styles.dart';
import 'package:yueyou/core/utils/safe_string.dart';

/// 🔥 赛博 KTV 提词器 - 音乐播放器居中滚动风格
/// 架构：AnimationController 驱动逐字进度，TextPainter 计算已读宽度
/// 当前字始终居中，已读=亮青色，未读=暗色，两端渐隐遮罩
class TeleprompterView extends StatefulWidget {
  const TeleprompterView({super.key});

  @override
  State<TeleprompterView> createState() => _TeleprompterViewState();
}

class _TeleprompterViewState extends State<TeleprompterView>
    with SingleTickerProviderStateMixin {
  late AnimationController _ktvController;
  String _prevText = '';
  bool _prevIsPlaying = false;
  double _prevPlaybackRate = 1.0;
  double _totalTextWidth = 0;
  final ScrollController _scrollCtrl = ScrollController();
  ReaderProvider? _reader;

  static final TextStyle _readStyle = CyberTextStyles.teleprompterInlineRead.copyWith(
    shadows: [
      Shadow(
        color: CyberColors.hackerBlue.withOpacity(0.5),
        blurRadius: 8,
      ),
    ],
  );

  static const TextStyle _unreadStyle = CyberTextStyles.teleprompterInlineUnread;

  @override
  void initState() {
    super.initState();
    _ktvController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    );
    _ktvController.addListener(_syncScroll);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reader = context.read<ReaderProvider>();
    if (!identical(_reader, reader)) {
      _reader?.removeListener(_onReaderChanged);
      _reader = reader;
      _reader?.addListener(_onReaderChanged);
      _onReaderChanged();
    }
  }

  void _onReaderChanged() {
    final reader = _reader;
    if (!mounted || reader == null) return;

    if (reader.isParsing || reader.sentences.isEmpty) {
      if (_prevIsPlaying) {
        _ktvController.stop();
        _prevIsPlaying = false;
      }
      return;
    }

    final String text = reader.currentSentence ?? '';
    final bool isPlaying = reader.ttsEngine.state == TtsPlaybackState.playing;
    final double playbackRate = reader.ttsEngine.playbackRate;

    // 🔥 关键修复：即使不播放，如果文字变了（如手动切句），也要重置提词器进度并预计算
    if (text != _prevText && text.isNotEmpty) {
      _onSentenceChanged(text, playbackRate, start: isPlaying);
    } else if (text.isNotEmpty && playbackRate != _prevPlaybackRate) {
      _onPlaybackRateChanged(text, playbackRate, isPlaying: isPlaying);
    }

    if (isPlaying && text.isNotEmpty) {
      if (!_ktvController.isAnimating) {
        _ktvController.forward();
      }
      _prevIsPlaying = true;
    } else {
      // 停止动画但保留当前进度
      if (_prevIsPlaying) {
        _ktvController.stop();
        _prevIsPlaying = false;
      }
    }
  }

  void _syncScroll() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollCtrl.hasClients || _totalTextWidth <= 0) return;
      if (!_scrollCtrl.position.hasPixels) return;
      final target = (_ktvController.value * _totalTextWidth)
          .clamp(0.0, _scrollCtrl.position.maxScrollExtent);
      _scrollCtrl.jumpTo(target);
    });
  }

  @override
  void dispose() {
    _reader?.removeListener(_onReaderChanged);
    _ktvController.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _onSentenceChanged(String text, double playbackRate,
      {bool start = true}) {
    _prevText = text;
    _prevPlaybackRate = playbackRate;
    // 新句子：预计算文字总宽度（只做一次，后续用线性插值）
    final tp = TextPainter(
      text: TextSpan(text: text, style: _readStyle),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: double.infinity);
    _totalTextWidth = tp.width;

    final speed = playbackRate.clamp(0.5, 3.0);
    // 中文 TTS 约 3.5 字/秒（~286ms/字），比之前 5字/秒更贴近实际语速
    final ms = (text.length * (1000 / (speed * 3.5))).round().clamp(800, 10000);
    _ktvController.duration = Duration(milliseconds: ms);

    if (start) {
      _ktvController.forward(from: 0.0);
    } else {
      _ktvController.value = 0.0; // 暂停且切句时，重置进度到开头
    }
  }

  void _onPlaybackRateChanged(String text, double playbackRate,
      {required bool isPlaying}) {
    _prevPlaybackRate = playbackRate;
    final double currentProgress = _ktvController.value;
    final speed = playbackRate.clamp(0.5, 3.0);
    final ms = (text.length * (1000 / (speed * 3.5))).round().clamp(800, 10000);
    _ktvController.duration = Duration(milliseconds: ms);

    if (isPlaying) {
      _ktvController.forward(from: currentProgress);
    } else {
      _ktvController.value = currentProgress;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ReaderProvider>(
      builder: (context, reader, _) {
        if (reader.isParsing) {
          return _buildPlaceholder('正在连接神经数据链路...');
        }
        if (reader.sentences.isEmpty) {
          return _buildPlaceholder('等待数据流接入 [ _ ]');
        }

        final String text = reader.currentSentence ?? '';
        final bool isPlaying =
            reader.ttsEngine.state == TtsPlaybackState.playing;

        return LayoutBuilder(
          builder: (context, constraints) {
            final halfWidth = constraints.maxWidth / 2;

            return ClipRRect(
              borderRadius: BorderRadius.circular(CyberDimensions.radiusL),
              child: BackdropFilter(
                filter: ImageFilter.blur(
                  sigmaX: CyberDimensions.blurMedium,
                  sigmaY: CyberDimensions.blurMedium,
                ),
                child: Container(
                  height: CyberDimensions.teleprompterHeight,
                  decoration: BoxDecoration(
                    color: CyberColors.glassDark,
                    borderRadius:
                        BorderRadius.circular(CyberDimensions.radiusL),
                    border: Border.all(
                      color: CyberColors.neonCyan.withOpacity(0.3),
                      width: CyberDimensions.borderNormal,
                    ),
                    boxShadow: CyberShadows.floating,
                  ),
                  child: Stack(
                    clipBehavior: Clip.hardEdge,
                    children: [
                      AnimatedBuilder(
                        animation: _ktvController,
                        builder: (context, _) {
                          final pos = _ktvController.value;
                          final charIndex =
                              (pos * text.length).floor().clamp(0, text.length);

                          return SingleChildScrollView(
                            controller: _scrollCtrl,
                            scrollDirection: Axis.horizontal,
                            physics: const NeverScrollableScrollPhysics(),
                            padding:
                                EdgeInsets.symmetric(horizontal: halfWidth),
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
                                      text: safeSubstring(
                                          text, charIndex, text.length),
                                      style: _unreadStyle.copyWith(
                                        color: CyberColors.whiteMuted
                                            .withOpacity(
                                                isPlaying ? 0.4 : 0.65),
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
                              borderRadius: BorderRadius.circular(
                                  CyberDimensions.radiusXS / 2),
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  CyberColors.neonCyan.withOpacity(0.0),
                                  CyberColors.neonCyan,
                                  CyberColors.neonCyan,
                                  CyberColors.neonCyan.withOpacity(0.0),
                                ],
                                stops: const [0.0, 0.25, 0.75, 1.0],
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: CyberColors.neonCyan.withOpacity(0.7),
                                  blurRadius: 8,
                                  spreadRadius: 1,
                                ),
                              ],
                            ),
                          ),
                        ),

                      // ── 左端渐隐遮罩（防文字溢出可见，避开边框）────────────
                      Positioned(
                        left: CyberDimensions.spacingXXS,
                        top: CyberDimensions.spacingXXS,
                        bottom: CyberDimensions.spacingXXS,
                        width: CyberDimensions.teleprompterMaskWidth,
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: const BorderRadius.only(
                              topLeft: Radius.circular(CyberDimensions.radiusL -
                                  CyberDimensions.spacingXXS),
                              bottomLeft: Radius.circular(
                                  CyberDimensions.radiusL -
                                      CyberDimensions.spacingXXS),
                            ),
                            gradient: LinearGradient(
                              begin: Alignment.centerLeft,
                              end: Alignment.centerRight,
                              colors: [
                                CyberColors.glassDark,
                                CyberColors.glassDark.withOpacity(0),
                              ],
                            ),
                          ),
                        ),
                      ),

                      // ── 右端渐隐遮罩（避开边框）──────────────────────────────
                      Positioned(
                        right: CyberDimensions.spacingXXS,
                        top: CyberDimensions.spacingXXS,
                        bottom: CyberDimensions.spacingXXS,
                        width: CyberDimensions.teleprompterMaskWidth,
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: const BorderRadius.only(
                              topRight: Radius.circular(
                                  CyberDimensions.radiusL -
                                      CyberDimensions.spacingXXS),
                              bottomRight: Radius.circular(
                                  CyberDimensions.radiusL -
                                      CyberDimensions.spacingXXS),
                            ),
                            gradient: LinearGradient(
                              begin: Alignment.centerRight,
                              end: Alignment.centerLeft,
                              colors: [
                                CyberColors.glassDark,
                                CyberColors.glassDark.withOpacity(0),
                              ],
                            ),
                          ),
                        ),
                      ),

                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildPlaceholder(String msg) {
    return SizedBox(
      height: CyberDimensions.teleprompterHeight,
      child: Center(
        child: Text(
          msg,
          style: CyberTextStyles.teleprompterPlaceholder.copyWith(
            color: CyberColors.whiteMuted.withOpacity(0.5),
          ),
        ),
      ),
    );
  }
}
