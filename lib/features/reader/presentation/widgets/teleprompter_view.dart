import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:yueyou/features/reader/providers/reader_provider.dart';
import 'package:yueyou/core/theme/cyber_colors.dart';
import 'package:yueyou/core/theme/cyber_dimensions.dart';
import 'package:yueyou/core/theme/cyber_shadows.dart';

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

  static const double _fontSize = 18;
  static const double _containerHeight = 46;

  static final TextStyle _readStyle = TextStyle(
    color: CyberColors.neonCyan,
    fontSize: _fontSize,
    fontWeight: FontWeight.w800,
    letterSpacing: 0.5,
    height: 1.0,
    shadows: [
      Shadow(
        color: CyberColors.hackerBlue.withOpacity(0.5),
        blurRadius: 8,
      ),
    ],
  );

  static const TextStyle _unreadStyle = TextStyle(
    color: CyberColors.whiteMuted,
    fontSize: _fontSize,
    fontWeight: FontWeight.w500,
    letterSpacing: 0.5,
    height: 1.0,
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
    _ktvController.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _onSentenceChanged(String text, double playbackRate) {
    if (text == _prevText) return;
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
    _ktvController.forward(from: 0.0);
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

        if (isPlaying && text.isNotEmpty) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            if (text != _prevText) {
              _onSentenceChanged(text, reader.ttsEngine.playbackRate);
            } else if (!_ktvController.isAnimating) {
              _ktvController.forward();
            }
            _prevIsPlaying = true;
          });
        } else if (!isPlaying && _prevIsPlaying) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            _ktvController.stop();
            _prevIsPlaying = false;
          });
        }

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
                  height: _containerHeight,
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
                          final pos = isPlaying ? _ktvController.value : 0.0;
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
                                      text: text.substring(0, charIndex),
                                      style: _readStyle,
                                    ),
                                    // 未读：暗色
                                    TextSpan(
                                      text: text.substring(charIndex),
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
                          top: 8,
                          bottom: 8,
                          child: Container(
                            width: 2,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(1),
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
                        left: 2,
                        top: 2,
                        bottom: 2,
                        width: 40,
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: const BorderRadius.only(
                              topLeft:
                                  Radius.circular(CyberDimensions.radiusL - 2),
                              bottomLeft:
                                  Radius.circular(CyberDimensions.radiusL - 2),
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
                        right: 2,
                        top: 2,
                        bottom: 2,
                        width: 40,
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: const BorderRadius.only(
                              topRight:
                                  Radius.circular(CyberDimensions.radiusL - 2),
                              bottomRight:
                                  Radius.circular(CyberDimensions.radiusL - 2),
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
      height: _containerHeight,
      child: Center(
        child: Text(
          msg,
          style: TextStyle(
            color: CyberColors.whiteMuted.withOpacity(0.5),
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
