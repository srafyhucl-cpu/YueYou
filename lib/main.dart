import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'core/constants/book_constants.dart';
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
import 'features/audio/services/tts_engine_service.dart';
import 'features/audio/providers/tts_audio_notifier.dart';

final GlobalKey<NavigatorState> globalNavigatorKey =
    GlobalKey<NavigatorState>();

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
  await CyberLogger.initSentry(
    () async => runApp(
      const riverpod.ProviderScope(
        child: YueYouApp(),
      ),
    ),
  );
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

  Future<void> _checkPrivacyAndBootstrap() async {
    if (!mounted) return;
    if (!StorageService.hasAgreedPrivacy()) {
      // 等待 MaterialApp 内部 Navigator 挂载完成（最多 5 次，间隔 50ms）
      // 避免首帧时 globalNavigatorKey 尚未绑定导致弹窗被静默跳过
      BuildContext? navContext;
      for (int i = 0; i < 5; i++) {
        navContext = globalNavigatorKey.currentContext;
        if (navContext != null) break;
        await Future<void>.delayed(const Duration(milliseconds: 50));
        if (!mounted) return;
      }
      if (navContext == null) {
        // 极端情况：Navigator 始终未挂载，记录日志后退出，绝不进入未授权状态
        CyberLogger.captureWarning(
          Exception('隐私弹窗 navContext 重试 5 次仍为 null'),
          tag: 'privacy',
          extra: {'context': '_checkPrivacyAndBootstrap'},
        );
        SystemNavigator.pop();
        return;
      }
      // navContext 来自 globalNavigatorKey，由 Navigator 自身管理生命周期，
      // 不依赖 _BootstrapperState.mounted；上方循环已做 mounted 守卫。
      // ignore: use_build_context_synchronously
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
