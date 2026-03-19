import 'package:flutter/material.dart';
import 'package:yueyou/core/theme/cyber_colors.dart';

/// 2048 棋盘正方形容器
/// 核心：强制 1:1 比例，霓虹外发光效果，并引入 RepaintBoundary 隔离高刷重绘
class SquareBoard extends StatelessWidget {
  const SquareBoard({super.key});

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: AspectRatio(
        aspectRatio: 1.0,
        child: Container(
          margin: const EdgeInsets.all(20.0), // 与边框保持距离
          decoration: BoxDecoration(
            color: const Color(0xFF1A1C25), // 极其暗的灰色，增加对比
            borderRadius: BorderRadius.circular(8.0),
            // 赛博霓虹外发光
            border: Border.all(
              color: CyberColors.neonGreen.withOpacity(0.8),
              width: 2.0,
            ),
            boxShadow: const [
              BoxShadow(
                color: CyberColors.glowShadow,
                blurRadius: 15.0,
                spreadRadius: 2.0,
              ),
            ],
          ),
          child: const Center(
            child: Text(
              "2048 ENGINE READY",
              style: TextStyle(
                color: CyberColors.neonGreen,
                fontSize: 14,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.5,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
