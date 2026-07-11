import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'core/config/app_info_config.dart';
import 'core/constants/book_constants.dart';
import 'core/database/storage_service.dart';
import 'core/theme/cyber_colors.dart';
import 'core/theme/cyber_dimensions.dart';
import 'core/theme/cyber_text_styles.dart';
import 'core/utils/cyber_logger.dart';
import 'features/audio/services/ambient_service.dart';
import 'features/audio/services/sfx_service.dart';
import 'features/dashboard/presentation/dashboard_screen.dart';
import 'features/library/domain/book_model.dart';
import 'features/reader/providers/reader_provider.dart';
import 'features/settings/providers/settings_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' as riverpod;
import 'shared/widgets/tts_error_listener.dart';
import 'features/audio/services/tts_engine_service.dart';
import 'features/audio/providers/tts_audio_notifier.dart';

final GlobalKey<NavigatorState> globalNavigatorKey =
    GlobalKey<NavigatorState>();

typedef YueYouAppRunner = Future<void> Function();
typedef YueYouSentryInitializer = Future<void> Function(
  YueYouAppRunner appRunner,
);
typedef YueYouWidgetRunner = void Function(Widget widget);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 全局错误捕获锚点（先注册，确保 Sentry 初始化前的错误也能记录）
  FlutterError.onError = CyberLogger.recordFlutterError;
  PlatformDispatcher.instance.onError = CyberLogger.recordPlatformError;

  await StorageService.init();

  await YueYouStartup().launch();
}

@visibleForTesting
class YueYouStartup {
  final bool Function() hasAgreedPrivacy;
  final Future<void> Function(bool value) setHasAgreedPrivacy;
  final Future<void> Function() initializeFullInfrastructure;
  final YueYouSentryInitializer initializeSentry;
  final YueYouWidgetRunner runWidget;
  final Future<void> Function() exitApp;

  YueYouStartup({
    bool Function()? hasAgreedPrivacy,
    Future<void> Function(bool value)? setHasAgreedPrivacy,
    Future<void> Function()? initializeFullInfrastructure,
    YueYouSentryInitializer? initializeSentry,
    YueYouWidgetRunner? runWidget,
    Future<void> Function()? exitApp,
  })  : hasAgreedPrivacy = hasAgreedPrivacy ?? StorageService.hasAgreedPrivacy,
        setHasAgreedPrivacy =
            setHasAgreedPrivacy ?? StorageService.setHasAgreedPrivacy,
        initializeFullInfrastructure =
            initializeFullInfrastructure ?? _initializeFullInfrastructure,
        initializeSentry = initializeSentry ??
            ((appRunner) => CyberLogger.initSentry(() async {
                  await appRunner();
                })),
        runWidget = runWidget ?? runApp,
        exitApp = exitApp ?? SystemNavigator.pop;

  Future<void> launch() async {
    if (hasAgreedPrivacy()) {
      await _launchFullApp();
      return;
    }

    runWidget(ConsentApp(onAgreed: _acceptConsent, onDeclined: exitApp));
  }

  Future<void> _acceptConsent() async {
    await setHasAgreedPrivacy(true);
    await _launchFullApp();
  }

  Future<void> _launchFullApp() async {
    await initializeFullInfrastructure();
    await initializeSentry(
      () async => runWidget(const riverpod.ProviderScope(child: YueYouApp())),
    );
  }
}

Future<void> _initializeFullInfrastructure() async {
  try {
    await SfxService.init();
  } catch (e, st) {
    CyberLogger.recordFlutterError(
      FlutterErrorDetails(exception: e, stack: st, library: 'SfxService'),
    );
  }

  try {
    await AmbientService.init();
  } catch (e, st) {
    CyberLogger.recordFlutterError(
      FlutterErrorDetails(exception: e, stack: st, library: 'AmbientService'),
    );
  }
}

class ConsentApp extends StatelessWidget {
  final Future<void> Function() onAgreed;
  final Future<void> Function() onDeclined;

  const ConsentApp({
    super.key,
    required this.onAgreed,
    required this.onDeclined,
  });

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '阅游 YueYou',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        scaffoldBackgroundColor: CyberColors.background,
        colorScheme: const ColorScheme.dark(
          primary: CyberColors.neonGreen,
          secondary: CyberColors.neonPink,
        ),
        useMaterial3: true,
      ),
      home: _ConsentScreen(onAgreed: onAgreed, onDeclined: onDeclined),
    );
  }
}

class _ConsentScreen extends StatefulWidget {
  final Future<void> Function() onAgreed;
  final Future<void> Function() onDeclined;

  const _ConsentScreen({required this.onAgreed, required this.onDeclined});

  @override
  State<_ConsentScreen> createState() => _ConsentScreenState();
}

class _ConsentScreenState extends State<_ConsentScreen> {
  bool _busy = false;

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    await action();
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: CyberColors.background,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(CyberDimensions.spacingL),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.security_rounded,
                    color: CyberColors.neonCyan,
                    size: CyberDimensions.iconL,
                  ),
                  const SizedBox(height: CyberDimensions.spacingM),
                  Text(
                    '阅游 · 隐私政策',
                    style: CyberTextStyles.dialogTitle.copyWith(
                      color: CyberColors.neonCyan,
                    ),
                  ),
                  const SizedBox(height: CyberDimensions.spacingM),
                  Text(
                    '同意前仅读取本机授权状态，不初始化业务服务、第三方 SDK 或网络能力。',
                    textAlign: TextAlign.center,
                    style: CyberTextStyles.bodySmall.copyWith(
                      color: CyberColors.whiteMuted,
                    ),
                  ),
                  const SizedBox(height: CyberDimensions.spacingL),
                  _PolicyPanel(),
                  const SizedBox(height: CyberDimensions.spacingL),
                  TextButton(
                    onPressed: () => launchUrl(
                      Uri.parse(AppInfoConfig.privacyPolicyUrl),
                      mode: LaunchMode.externalApplication,
                    ),
                    child: Text(
                      '阅读完整版《阅游隐私政策》',
                      style: CyberTextStyles.caption.copyWith(
                        color: CyberColors.neonCyan,
                        decoration: TextDecoration.underline,
                        decorationColor: CyberColors.neonCyan,
                      ),
                    ),
                  ),
                  const SizedBox(height: CyberDimensions.spacingM),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed:
                              _busy ? null : () => _run(widget.onDeclined),
                          child: const Text('不同意并退出'),
                        ),
                      ),
                      const SizedBox(width: CyberDimensions.spacingM),
                      Expanded(
                        child: FilledButton(
                          onPressed: _busy ? null : () => _run(widget.onAgreed),
                          child: const Text('同意'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PolicyPanel extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(CyberDimensions.spacingM),
      decoration: BoxDecoration(
        color: CyberColors.whiteFaint,
        borderRadius: BorderRadius.circular(CyberDimensions.radiusS),
        border: Border.all(
          color: CyberColors.neonCyan.withValues(alpha: 0.2),
          width: CyberDimensions.borderThin,
        ),
      ),
      child: Text(
        '数据存储：阅读进度、游戏数据及设置仅存储于本地设备。\n\n'
        '云端 TTS：启用听书时，仅当前朗读文本段落会发送到云端 TTS 服务用于合成音频。\n\n'
        '存储权限：仅用于读取您主动选择导入的文件，不扫描其他目录。\n\n'
        '撤回授权：可在设置页撤回隐私授权，撤回后下次启动会重新进入本页面。',
        style: CyberTextStyles.captionComfortable.copyWith(
          color: CyberColors.whiteMedium,
        ),
      ),
    );
  }
}

class YueYouApp extends riverpod.ConsumerWidget {
  const YueYouApp({super.key});

  @override
  Widget build(BuildContext context, riverpod.WidgetRef ref) {
    return const _Bootstrapper();
  }
}

class _Bootstrapper extends riverpod.ConsumerStatefulWidget {
  const _Bootstrapper();

  @override
  riverpod.ConsumerState<_Bootstrapper> createState() => _BootstrapperState();
}

class _BootstrapperState extends riverpod.ConsumerState<_Bootstrapper>
    with WidgetsBindingObserver {
  bool _booted = false;

  /// 记录上一次 SettingsProvider 的 ambient 状态，用于增量对比
  bool? _lastAmbientEnabled;
  double? _lastAmbientVol;
  String? _lastAmbientStyle;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance
      ..addObserver(this)
      ..addPostFrameCallback((_) => _bootstrap());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 每当 SettingsProvider 变化时同步 AmbientService
    final settings = ref.watch(settingsProvider);
    _syncAmbient(settings);
  }

  /// 同步 SettingsProvider 的 ambient 设置到 AmbientService
  void _syncAmbient(SettingsProvider settings) {
    if (settings.ambientEnabled != _lastAmbientEnabled) {
      _lastAmbientEnabled = settings.ambientEnabled;
      AmbientService.setEnabled(settings.ambientEnabled);
    }
    if (settings.ambientVol != _lastAmbientVol) {
      _lastAmbientVol = settings.ambientVol;
      AmbientService.setVolume(settings.ambientVol);
    }
    if (settings.ambientStyle != _lastAmbientStyle) {
      _lastAmbientStyle = settings.ambientStyle;
      AmbientService.setStyle(settings.ambientStyle);
    }
  }

  /// App 生命周期：切后台暂停，切前台恢复。
  ///
  /// P0-3：原实现把 `hidden` 与 `detached` 一并 `dispose()`，但 Android `hidden`
  /// 是瞬态状态（电源键熄屏、最近任务、画中画切换），dispose 后 `_initialized=false`
  /// 会让本次进程内 AmbientService 永久哑火。改为：
  /// - paused / inactive / hidden ：均仅 `pause()`，资源保留以便快速恢复；
  /// - detached ：仅在进程将被销毁时才 `dispose()`。
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
        AmbientService.pause();
        ref.read(ttsAudioProvider.notifier).setBackgroundTolerant(true);
      case AppLifecycleState.resumed:
        AmbientService.resume();
        ref.read(ttsAudioProvider.notifier).setBackgroundTolerant(false);
      case AppLifecycleState.detached:
        AmbientService.dispose();
    }
  }

  Future<void> _bootstrap() async {
    if (_booted) return;
    _booted = true;

    final reader = ref.read(readerProvider);
    final currentNovelId = StorageService.getCurrentNovelId();
    if (currentNovelId == null) return;
    // P1-8：默认书《西游记》走分章懒加载路径，由 readerProvider 创建时
    // 触发的 restoreDefaultBook() 独占恢复，_bootstrap 不再读其全书内容，
    // 避免与 microtask 形成竞态把空数据写入 _sentences。
    if (currentNovelId == BookConstants.defaultBookKey) return;

    final content = await StorageService.loadBookContent(currentNovelId);
    if (!mounted || content == null) return;

    final List<dynamic> rawLines = content['lines'] as List<dynamic>? ?? [];
    final List<dynamic> rawChapters =
        content['chapters'] as List<dynamic>? ?? [];
    final chapters = rawChapters
        .map((e) => ChapterModel.fromJson(e as Map<String, dynamic>))
        .toList();
    final lines = rawLines.map((e) => e.toString()).toList();
    final int initialIndex = StorageService.getCurrentNovelIndex();

    await reader.loadPreparedBook(
      lines,
      bookId: currentNovelId,
      chapters: chapters,
      initialIndex: initialIndex,
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: globalNavigatorKey,
      title: '阅游 YueYou',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        scaffoldBackgroundColor: CyberColors.background,
        colorScheme: const ColorScheme.dark(
          primary: CyberColors.neonGreen,
          secondary: CyberColors.neonPink,
        ),
        useMaterial3: true,
      ),
      builder: (context, child) => Listener(
        onPointerDown: (_) => ref.read(ttsEngineProvider).notifyUserActivity(),
        behavior: HitTestBehavior.translucent,
        child: TtsErrorListener(child: child!),
      ),
      home: const DashboardScreen(),
    );
  }
}
