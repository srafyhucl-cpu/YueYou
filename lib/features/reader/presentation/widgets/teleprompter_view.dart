import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../core/theme/cyber_text_styles.dart';
import '../../../../shared/widgets/cyber_cursor.dart';
import '../../providers/reader_provider.dart';

/// 提词器核心展示层
/// 视觉：使用 AnimatedSwitcher + Fade + Slide 实现赛博残影动效
class TeleprompterView extends StatelessWidget {
  const TeleprompterView({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<ReaderProvider>(
      builder: (context, provider, child) {
        // 1. 神经数据解析中状态
        if (provider.isParsing) {
          return const Center(
            child: Text(
              "🧩 正在连接神经数据链路...",
              style: TextStyle(color: Colors.white30, fontSize: 13, fontWeight: FontWeight.bold),
            ),
          );
        }

        // 2. 空数据/等待接入状态
        if (provider.sentences.isEmpty) {
          return Center(
            child: Opacity(
              opacity: 0.5,
              child: Text(
                "等待数据流接入 [ _ ]",
                style: CyberTextStyles.teleprompterDim.copyWith(fontSize: 16),
              ),
            ),
          );
        }

        final String? text = provider.currentSentence;

        // 3. 阅读主展示区域 - 支持手势步进，增加动画交互
        return GestureDetector(
          onTap: () => provider.nextSentence(), // 点击此处逻辑与老项目的点击切换 1:1 还原
          child: Container(
            width: double.infinity,
            alignment: Alignment.centerLeft,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              transitionBuilder: (Widget child, Animation<double> animation) {
                // 工业级视觉：FadeTransition + 微小垂直平移 (SlideTransition)
                return FadeTransition(
                  opacity: animation,
                  child: SlideTransition(
                    position: Tween<Offset>(
                      begin: const Offset(0.0, 0.2), // 从下方微小滑入
                      end: Offset.zero,
                    ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
                    child: child,
                  ),
                );
              },
              child: RichText(
                // 必须绑定 ValueKey<int>(provider.currentIndex) 才能触发 Widget 过场动画
                key: ValueKey<int>(provider.currentIndex),
                textAlign: TextAlign.left,
                text: TextSpan(
                  children: [
                    const WidgetSpan(
                      alignment: PlaceholderAlignment.middle,
                      child: Padding(
                        padding: EdgeInsets.only(right: 8, bottom: 4),
                        child: CyberCursor(width: 8, height: 22),
                      ),
                    ),
                    TextSpan(
                      text: text ?? "",
                      style: CyberTextStyles.teleprompterActive,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
