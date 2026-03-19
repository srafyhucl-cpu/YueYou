// 这是阅游的单元测试占位文件。
// 随着业务逻辑（2048 算法等）的加入，我们将在此编写更严谨的测试。

import 'package:flutter_test/flutter_test.dart';
import 'package:yueyou/main.dart';
import 'package:yueyou/features/dashboard/presentation/dashboard_screen.dart';

void main() {
  testWidgets('阅游基础加载烟雾测试', (WidgetTester tester) async {
    // 构建 App
    await tester.pumpWidget(const YueYouApp());

    // 验证主控制台 DashboardScreen 是否成功加载
    expect(find.byType(DashboardScreen), findsOneWidget);
  });
}
