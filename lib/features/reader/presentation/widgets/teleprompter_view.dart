import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
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
  double _totalTextWidth = 0;
  final ScrollController _scrollCtrl = ScrollController();
  ReaderProvider? _reader;
  String? _errorMessage;
  bool _errorVisible = false;
  Timer? _errorHideTimer;
  Timer? _errorCleanupTimer;

  static const Duration _errorDisplayDuration = Duration(seconds: 3);
  static const Duration _errorFadeDuration = Duration(milliseconds: 300);

  static final TextStyle _readStyle = TextStyle(
    color: CyberTextStyles.teleprompterInlineRead.color,
    fontSize: CyberTextStyles.teleprompterInlineRead.fontSize,
    fontWeight: CyberTextStyles.teleprompterInlineRead.fontWeight,
    letterSpacing: CyberTextStyles.teleprompterInlineRead.letterSpacing,
    height: CyberTextStyles.teleprompterInlineRead.height,
    shadows: [
      Shadow(
        color: CyberColors.hackerBlue.withOpacity(0.5),
        blurRadius: 8,
      ),
    ],
  );

  static final TextStyle _unreadStyle = TextStyle(
    color: CyberTextStyles.teleprompterInlineUnread.color,
    fontSize: CyberTextStyles.teleprompterInlineUnread.fontSize,
    fontWeight: CyberTextStyles.teleprompterInlineUnread.fontWeight,
    letterSpacing: CyberTextStyles.teleprompterInlineUnread.letterSpacing,
    height: CyberTextStyles.teleprompterInlineUnread.height,
  );

  @override
  void initState() {
    super.initState();
    _ktvController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    );
    _ktvController.addListener(_syncScroll);
  }

  void _onErrorChanged(String? message) {
    if (_errorMessage == message && _errorVisible) {
      return;
    }

    _errorHideTimer?.cancel();
    _errorCleanupTimer?.cancel();

    if (message == null || message.isEmpty) {
      _hideErrorTip();
      return;
    }

    setState(() {
      _errorMessage = message;
      _errorVisible = true;
    });

    _errorHideTimer = Timer(_errorDisplayDuration, _hideErrorTip);
  }

  void _hideErrorTip() {
    if (!mounted) return;
    if (!_errorVisible && _errorMessage == null) return;

    setState(() {
      _errorVisible = false;
    });

    _errorCleanupTimer = Timer(_errorFadeDuration, () {
      if (!mounted || _errorVisible) return;
      setState(() {
        _errorMessage = null;
      });
    });
  }

  void _onErrorTipTap() {
    _hideErrorTip();
    _reader?.clearTtsError();
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

    _onErrorChanged(reader.ttsErrorMessage);

    if (reader.isParsing || reader.sentences.isEmpty) {
      if (_prevIsPlaying) {
        _ktvController.stop();
        _prevIsPlaying = false;
      }
      return;
    }

    final String text = reader.currentSentence ?? '';
    final bool isPlaying = reader.ttsEngine.isSpeaking;

    // 🔥 关键修复：即使不播放，如果文字变了（如手动切句），也要重置提词器进度并预计算
    if (text != _prevText && text.isNotEmpty) {
      _onSentenceChanged(text, reader.ttsEngine.playbackRate, start: isPlaying);
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
    _errorHideTimer?.cancel();
    _errorCleanupTimer?.cancel();
    _ktvController.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _onSentenceChanged(String text, double playbackRate,
      {bool start = true}) {
    _prevText = text;
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
        final bool isPlaying = reader.ttsEngine.isSpeaking;

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

                      if (_errorMessage != null)
                        Positioned(
                          top: CyberDimensions.spacingXS,
                          left: CyberDimensions.spacingS,
                          right: CyberDimensions.spacingS,
                          child: AnimatedOpacity(
                            duration: _errorFadeDuration,
                            opacity: _errorVisible ? 1.0 : 0.0,
                            child: GestureDetector(
                              key: const ValueKey('teleprompter_error_tip'),
                              onTap: _onErrorTipTap,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: CyberDimensions.spacingS,
                                  vertical: CyberDimensions.spacingXS,
                                ),
                                decoration: BoxDecoration(
                                  color: CyberColors.panelBackground,
                                  borderRadius: BorderRadius.circular(
                                      CyberDimensions.radiusS),
                                  border: Border.all(
                                    color:
                                        CyberColors.neonPink.withOpacity(0.7),
                                    width: CyberDimensions.borderNormal,
                                  ),
                                ),
                                child: Text(
                                  _errorMessage!,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: CyberTextStyles.teleprompterError,
                                ),
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
