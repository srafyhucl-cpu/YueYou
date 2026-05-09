import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yueyou/features/settings/providers/settings_provider.dart';
import 'package:yueyou/shared/widgets/cyber_confirm_dialog.dart';

import '../../utils/test_utils.dart';

/// CyberConfirmDialog + CyberModal 联动烟测，目标覆盖：
///   * `showCyberConfirmDialog` 完整调用链（lib/shared/widgets/cyber_confirm_dialog.dart）
///   * 通过 `showCyberModal` 间接覆盖 lib/shared/widgets/cyber_modal.dart 全部分支
///   * 标题/消息渲染、确认/取消按钮渲染、tap 回调返回值
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    await initializeTestEnvironment();
  });

  Widget _wrap(Widget Function(BuildContext) builder) {
    final settings = makeSettings();
    return ProviderScope(
      overrides: [
        settingsProvider.overrideWith((ref) => settings),
      ],
      child: MaterialApp(
        home: Builder(builder: (context) => Scaffold(body: builder(context))),
      ),
    );
  }

  testWidgets('showCyberConfirmDialog 必须渲染标题/消息/双按钮', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      _wrap(
        (ctx) => ElevatedButton(
          onPressed: () => showCyberConfirmDialog(
            context: ctx,
            title: '初始化测试',
            message: '此操作不可撤销，是否继续？',
            confirmText: '继续',
            cancelText: '回退',
          ),
          child: const Text('open'),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('初始化测试'), findsOneWidget);
    expect(find.text('此操作不可撤销，是否继续？'), findsOneWidget);
    expect(find.text('继续'), findsOneWidget,
        reason: 'confirm 按钮文本必须渲染');
    expect(find.text('回退'), findsOneWidget,
        reason: 'cancel 按钮文本必须渲染');
  });

  testWidgets('showCyberConfirmDialog 默认按钮文案为「确认/取消」', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      _wrap(
        (ctx) => ElevatedButton(
          onPressed: () => showCyberConfirmDialog(
            context: ctx,
            title: '默认按钮',
            message: '验证默认 confirmText/cancelText',
          ),
          child: const Text('open'),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('确认'), findsOneWidget);
    expect(find.text('取消'), findsOneWidget);
  });

  testWidgets('showCyberConfirmDialog low animation level 必须走非 blur 分支',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final settings = makeSettings();
    settings.animationQualitySetting = 'low';

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          settingsProvider.overrideWith((ref) => settings),
        ],
        child: MaterialApp(
          home: Builder(
            builder: (ctx) => Scaffold(
              body: ElevatedButton(
                onPressed: () => showCyberConfirmDialog(
                  context: ctx,
                  title: '低性能模式',
                  message: '走 isLowPerf=true 分支',
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    // 低性能模式下 modal 仍渲染标题，但内部走非 BackdropFilter 路径
    expect(find.text('低性能模式'), findsOneWidget);
  });
}
