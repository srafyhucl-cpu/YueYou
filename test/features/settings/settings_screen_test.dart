import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yueyou/features/settings/constants/settings_texts.dart';
import 'package:yueyou/features/settings/presentation/screens/settings_screen.dart';
import 'package:yueyou/features/settings/presentation/widgets/privacy_agreement_modal.dart';
import 'package:yueyou/features/settings/providers/settings_provider.dart';

import '../../utils/test_utils.dart';

/// SettingsScreen widget 烟测。
///
/// 一次性渲染整个设置页，覆盖：
///   * Header 区域（line 42-91）
///   * _buildBody ListView 渲染所有 section（line 93-282）
///   * 各 _SectionTitle / _ToggleTile / _RadioTile 等子 widget
///   * 静默暂停 / 系统音效 / 隐私合规等所有分组
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    await initializeTestEnvironment();
  });

  Widget _wrap() {
    final settings = makeSettings();

    return ProviderScope(
      overrides: [settingsProvider.overrideWith((ref) => settings)],
      child: const MaterialApp(home: SettingsScreen()),
    );
  }

  testWidgets('SettingsScreen 必须渲染 Header 标题与所有 section 标题', (tester) async {
    // 大屏避免 ListView 滚动遮挡底部 section
    tester.view.physicalSize = const Size(1080, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(_wrap());
    await tester.pump();

    // Header 标题
    expect(
      find.text(SettingsTexts.screenTitle),
      findsOneWidget,
      reason: 'Header 必须渲染「神经系统配置」',
    );
    // 各 section title
    expect(
      find.text(SettingsTexts.ttsSectionTitle),
      findsOneWidget,
      reason: '语音播报分组必须渲染',
    );
    expect(
      find.text(SettingsTexts.ambientSectionTitle),
      findsOneWidget,
      reason: '意境氛围分组必须渲染',
    );
    expect(
      find.text(SettingsTexts.powerSectionTitle),
      findsOneWidget,
      reason: '省电管理分组必须渲染',
    );
    expect(
      find.text(SettingsTexts.systemSoundSectionTitle),
      findsOneWidget,
      reason: '系统音效分组必须渲染',
    );
    expect(
      find.text(SettingsTexts.privacyComplianceTitle),
      findsOneWidget,
      reason: '隐私与合规分组必须渲染',
    );
    expect(
      find.text(SettingsTexts.privacyRevokeTitle),
      findsOneWidget,
      reason: '撤回隐私授权入口必须渲染',
    );
  });

  testWidgets('SettingsScreen 必须渲染各类设置项 widget（Toggle / Label / 静默暂停选项）', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(_wrap());
    await tester.pump();

    // Toggle 项 → Switch widget
    expect(
      find.byType(Switch),
      findsWidgets,
      reason: '至少一个开关项必须渲染（自动朗读 / 背景音 / 方块音效）',
    );
    // 自动朗读 ToggleTile 标题
    expect(find.text(SettingsTexts.autoReadTitle), findsOneWidget);
    // 静默暂停标签
    expect(find.text(SettingsTexts.idleTimeoutLabel), findsOneWidget);
  });

  testWidgets('SettingsScreen 默认尺寸必须不崩溃（小屏 ListView 滚动）', (tester) async {
    // 固定逻辑小屏尺寸，避免不同平台默认 devicePixelRatio 造成视口漂移。
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(_wrap());
    await tester.pump();

    // Header 必须可见
    expect(find.text(SettingsTexts.screenTitle), findsOneWidget);
    // Scaffold 已构建
    expect(find.byType(Scaffold), findsOneWidget);
  });

  // ── PrivacyAgreementModal 完整渲染 ────────────────────────────────────
  //
  // 覆盖 lib/features/settings/presentation/widgets/privacy_agreement_modal.dart：
  //   * showPrivacyAgreementModal entry（line 13-20）
  //   * _PrivacyAgreementContent build（line 22-170）
  //   * 5 个 _PolicySection 渲染（line 73-110, 174-217）
  //   * _AgreeButton / _DeclineButton 渲染（line 219-284）
  //
  // 注意：tap 「同意」会 pop modal 让 Builder context 失效；tap 「不同意」会调
  // SystemNavigator.pop 触发平台 channel；两种交互均不验证回调，只验证渲染。
  testWidgets('showPrivacyAgreementModal 必须渲染完整内容（标题/5 个 PolicySection/双按钮）', (
    tester,
  ) async {
    // 大屏避免 modal 内容溢出（_PrivacyAgreementContent 含 5 个 PolicySection +
    // 协议正文滚动框 + 提示 + 双按钮，默认 800x600 会触发 RenderFlex overflow）
    tester.view.physicalSize = const Size(1080, 3000);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final settings = makeSettings();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [settingsProvider.overrideWith((ref) => settings)],
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: ElevatedButton(
                onPressed: () => showPrivacyAgreementModal(context),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    // 启动 modal + 推进 ScaleTransition / FadeTransition 完成
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    // 标题
    expect(find.text('阅游 · 隐私政策'), findsOneWidget);
    // 5 个 _PolicySection title
    expect(find.text('数据存储'), findsOneWidget);
    expect(find.text('云端 TTS 合成'), findsOneWidget);
    expect(find.text('存储权限'), findsOneWidget);
    expect(find.text('隐私承诺'), findsOneWidget);
    expect(find.text('开发者信息'), findsOneWidget);
    // 双按钮
    expect(find.text('同意'), findsOneWidget);
    expect(find.text('不同意并退出'), findsOneWidget);
  });
}
