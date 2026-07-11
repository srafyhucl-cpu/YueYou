import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yueyou/features/dashboard/presentation/dashboard_screen.dart';
import 'package:yueyou/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('首次启动未同意时只渲染 ConsentApp，不初始化完整业务栈', () async {
    var fullInitCount = 0;
    var sentryInitCount = 0;
    Widget? launched;

    final startup = YueYouStartup(
      hasAgreedPrivacy: () => false,
      setHasAgreedPrivacy: (_) async {},
      initializeFullInfrastructure: () async => fullInitCount++,
      initializeSentry: (runner) async {
        sentryInitCount++;
        await runner();
      },
      runWidget: (widget) => launched = widget,
      exitApp: () async {},
    );

    await startup.launch();

    expect(fullInitCount, 0);
    expect(sentryInitCount, 0);
    expect(launched, isA<ConsentApp>());
  });

  testWidgets('ConsentApp 同意前不创建 ProviderScope 或 Dashboard', (tester) async {
    await tester.pumpWidget(
      ConsentApp(onAgreed: () async {}, onDeclined: () async {}),
    );

    expect(find.byType(ProviderScope), findsNothing);
    expect(find.byType(DashboardScreen), findsNothing);
    expect(find.text('同意'), findsOneWidget);
    expect(find.text('不同意并退出'), findsOneWidget);
  });

  testWidgets('ConsentApp 点击同意后才持久化授权并启动完整业务栈', (tester) async {
    var agreed = false;
    var fullInitCount = 0;
    var sentryInitCount = 0;
    Widget? launched;

    final startup = YueYouStartup(
      hasAgreedPrivacy: () => false,
      setHasAgreedPrivacy: (value) async => agreed = value,
      initializeFullInfrastructure: () async => fullInitCount++,
      initializeSentry: (runner) async {
        sentryInitCount++;
        await runner();
      },
      runWidget: (widget) => launched = widget,
      exitApp: () async {},
    );

    await startup.launch();
    await tester.pumpWidget(launched!);
    await tester.tap(find.text('同意'));
    await tester.pump();

    expect(agreed, isTrue);
    expect(fullInitCount, 1);
    expect(sentryInitCount, 1);
    expect(launched, isA<ProviderScope>());
  });

  test('已同意启动时直接初始化完整业务栈', () async {
    var fullInitCount = 0;
    var sentryInitCount = 0;
    Widget? launched;

    final startup = YueYouStartup(
      hasAgreedPrivacy: () => true,
      setHasAgreedPrivacy: (_) async {},
      initializeFullInfrastructure: () async => fullInitCount++,
      initializeSentry: (runner) async {
        sentryInitCount++;
        await runner();
      },
      runWidget: (widget) => launched = widget,
      exitApp: () async {},
    );

    await startup.launch();

    expect(fullInitCount, 1);
    expect(sentryInitCount, 1);
    expect(launched, isA<ProviderScope>());
  });

  testWidgets('ConsentApp 点击拒绝时只执行退出回调', (tester) async {
    var declined = false;
    var agreed = false;

    await tester.pumpWidget(
      ConsentApp(
        onAgreed: () async => agreed = true,
        onDeclined: () async => declined = true,
      ),
    );

    await tester.tap(find.text('不同意并退出'));
    await tester.pump();

    expect(declined, isTrue);
    expect(agreed, isFalse);
  });
}
