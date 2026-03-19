import 'package:flutter/material.dart';
import 'package:yueyou/core/theme/cyber_text_styles.dart';
import 'package:yueyou/shared/widgets/cyber_cursor.dart';

/// 提词器核心展示组件
/// 重构目标：支持流式滚动，防止长文本在有限布局内溢出
class TeleprompterView extends StatelessWidget {
  static const String _hardcodedText =
      "城市在灰色的雨幕中颤抖。代码在天际线的流光中交织，那是一场名为‘协议’的永恒审判。杰克握紧了手中发烫的接口盒，神经链路里的电流正在疯狂反噬。他知道，在这个霓虹灯永远不熄灭的深渊里，每一次登入都是对灵魂的抵押。如果你能听见电子脉冲的跳动，那说明你已经成为了矩阵的一部分。别回头，那里只有被格式化的阴影和永不停止的循环。";

  final int progressIndex;

  const TeleprompterView({
    super.key,
    this.progressIndex = 40,
  });

  @override
  Widget build(BuildContext context) {
    if (progressIndex > _hardcodedText.length) return const SizedBox.shrink();
    
    final String readPart = _hardcodedText.substring(0, progressIndex);
    final String unreadPart = _hardcodedText.substring(progressIndex);

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16.0),
        child: RichText(
          textAlign: TextAlign.justify,
          text: TextSpan(
            children: [
              TextSpan(
                text: readPart,
                style: CyberTextStyles.teleprompterActive,
              ),
              const WidgetSpan(
                alignment: PlaceholderAlignment.middle,
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 4.0),
                  child: CyberCursor(),
                ),
              ),
              TextSpan(
                text: unreadPart,
                style: CyberTextStyles.teleprompterDim,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
