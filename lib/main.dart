import 'dart:ui';
import 'package:flutter/material.dart';

import 'core/database/storage_service.dart';
import 'core/theme/cyber_colors.dart';
import 'core/utils/cyber_logger.dart';
import 'features/settings/presentation/widgets/privacy_agreement_modal.dart';
import 'features/audio/services/ambient_service.dart';
import 'features/audio/services/sfx_service.dart';
import 'features/dashboard/presentation/dashboard_screen.dart';

import 'features/library/domain/book_model.dart';
import 'features/reader/providers/reader_provider.dart';
import 'features/settings/providers/settings_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' as riverpod;
import 'shared/widgets/tts_error_listener.dart';

final GlobalKey<NavigatorState> globalNavigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 全局错误捕获锚点（先注册，确保 Sentry 初始化前的错误也能记录）
  FlutterError.onError = CyberLogger.recordFlutterError;
  PlatformDispatcher.instance.onError = CyberLogger.recordPlatformError;

  // 启动前初始化持久化层与音效引擎
  await StorageService.init();
  try {
    await SfxService.init();
  } catch (e, st) {
    CyberLogger.recordFlutterError(
      FlutterErrorDetails(exception: e, stack: st, library: 'SfxService'),
    );
  }

  // 初始化环境背景音服务
  try {
    await AmbientService.init();
  } catch (e, st) {
    CyberLogger.recordFlutterError(
      FlutterErrorDetails(exception: e, stack: st, library: 'AmbientService'),
    );
  }

  // 通过 CyberLogger 初始化 Sentry 并启动 App
  // DSN 通过 --dart-define=SENTRY_DSN=https://... 注入，空时静默跳过
  await CyberLogger.initSentry(() async => runApp(
        const riverpod.ProviderScope(
          child: YueYouApp(),
        ),
      ));
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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance
      ..addObserver(this)
      ..addPostFrameCallback((_) => _checkPrivacyAndBootstrap());
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
  }

  /// App 生命周期：切后台暂停，切前台恢复
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
        AmbientService.pause();
      case AppLifecycleState.resumed:
        AmbientService.resume();
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
        AmbientService.dispose();
    }
  }

  Future<void> _checkPrivacyAndBootstrap() async {
    if (!mounted) return;
    if (!StorageService.hasAgreedPrivacy()) {
      final navContext = globalNavigatorKey.currentContext;
      if (navContext == null) return;
      final agreed = await showPrivacyAgreementModal(navContext);
      if (!mounted) return;
      if (agreed) {
        await StorageService.setHasAgreedPrivacy(true);
      } else {
        return;
      }
    }
    await _bootstrap();
  }

  Future<void> _bootstrap() async {
    if (_booted) return;
    _booted = true;

    final reader = ref.read(readerProvider);
    final currentNovelId = StorageService.getCurrentNovelId();
    if (currentNovelId == null) return;

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
      builder: (context, child) => TtsErrorListener(child: child!),
      home: const DashboardScreen(),
    );
  }
}
