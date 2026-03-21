// 这是阅游的单元测试占位文件。
// 随着业务逻辑（2048 算法等）的加入，我们将在此编写更严谨的测试。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:yueyou/features/game_2048/presentation/widgets/square_board.dart';
import 'package:yueyou/features/game_2048/providers/game_provider.dart';
import 'package:yueyou/core/config/tts_config.dart';

void main() {
  testWidgets('2048 棋盘加载测试', (WidgetTester tester) async {
    // 构建简化的测试环境
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => GameProvider(),
        child: const MaterialApp(
          home: Scaffold(
            body: SquareBoard(),
          ),
        ),
      ),
    );

    // 等待一帧以完成初始化
    await tester.pump();

    // 验证棋盘是否成功加载
    expect(find.byType(SquareBoard), findsOneWidget);
  });

  test('TTS 配置测试', () {
    // 测试 TTS 配置是否正确加载
    expect(TtsConfig.development.serverUrl, isNotEmpty);
    expect(TtsConfig.production.serverUrl, isNotEmpty);
    expect(TtsConfig.current.maxRetries, greaterThan(0));
  });
}
