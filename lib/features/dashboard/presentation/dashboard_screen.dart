import 'package:flutter/material.dart';
import 'package:yueyou/core/theme/cyber_colors.dart';
import 'package:yueyou/core/theme/cyber_text_styles.dart';
import 'package:yueyou/shared/widgets/safe_padding_wrap.dart';
import 'package:yueyou/features/game_2048/presentation/widgets/square_board.dart';

/// 阅游主界面仪表盘
/// 采用“上提词下游戏”的典型赛博朋克双线程布局
class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: CyberColors.background,
      body: Column(
        children: [
          // 上半部分：极简提词器
          SafePaddingWrap(
            child: Text(
              "“极简，并不意味着缺失。它是对核心体验的极致克制。正如这块棋盘，既是游戏，也是入定的敲门砖。”",
              style: CyberTextStyles.teleprompterActive,
              textAlign: TextAlign.justify,
            ),
          ),
          
          // 下半部分：2048 棋盘（居中且自适应）
          Expanded(
            child: Center(
              child: SquareBoard(),
            ),
          ),
        ],
      ),
    );
  }
}
