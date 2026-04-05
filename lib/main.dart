import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'core/database/storage_service.dart';
import 'core/theme/cyber_colors.dart';
import 'core/utils/cyber_logger.dart';
import 'features/settings/presentation/widgets/privacy_agreement_modal.dart';
import 'features/audio/services/sfx_service.dart';
import 'features/dashboard/presentation/dashboard_screen.dart';
import 'features/game_2048/providers/game_provider.dart';
import 'features/audio/services/tts_engine_service.dart';
import 'features/library/providers/bookshelf_provider.dart';
import 'features/library/domain/book_model.dart';
import 'features/reader/providers/reader_provider.dart';
import 'features/settings/providers/settings_provider.dart';
import 'widgets/tts_error_listener.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 全局错误捕获锚点（Task 4）
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
  runApp(const YueYouApp());
}

class _AppBootstrapData {
  final SettingsProvider settings;
  final BookshelfProvider bookshelf;

  const _AppBootstrapData({
    required this.settings,
    required this.bookshelf,
  });
}

class YueYouApp extends StatefulWidget {
  const YueYouApp({super.key});

  @override
  State<YueYouApp> createState() => _YueYouAppState();
}

class _YueYouAppState extends State<YueYouApp> {
  late final Future<_AppBootstrapData> _bootstrapFuture;

  @override
  void initState() {
    super.initState();
    _bootstrapFuture = _loadBootstrapData();
  }

  Future<_AppBootstrapData> _loadBootstrapData() async {
    final settings = SettingsProvider();
    final bookshelf = BookshelfProvider();

    await Future.wait<void>([
      Future<void>(() => settings.loadFromStorage()),
      Future<void>(() => bookshelf.loadFromStorage()),
    ]);

    return _AppBootstrapData(settings: settings, bookshelf: bookshelf);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_AppBootstrapData>(
      future: _bootstrapFuture,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const MaterialApp(
            debugShowCheckedModeBanner: false,
            home: Scaffold(
              backgroundColor: CyberColors.background,
              body: Center(
                child: CircularProgressIndicator(),
              ),
            ),
          );
        }

        final bootstrap = snapshot.data!;
        return MultiProvider(
          providers: [
            ChangeNotifierProvider<SettingsProvider>.value(
              value: bootstrap.settings,
            ),
            ChangeNotifierProvider<BookshelfProvider>.value(
              value: bootstrap.bookshelf,
            ),
            ChangeNotifierProxyProvider<SettingsProvider, TtsEngineService>(
              create: (ctx) {
                final settings = ctx.read<SettingsProvider>();
                return TtsEngineService(settings);
              },
              update: (ctx, settings, prev) =>
                  prev ?? TtsEngineService(settings),
            ),
            ChangeNotifierProxyProvider2<SettingsProvider, TtsEngineService,
                GameProvider>(
              create: (ctx) {
                final gp = GameProvider();
                gp.soundEnabled = ctx.read<SettingsProvider>().sound;
                gp.onUserMove =
                    () => ctx.read<TtsEngineService>().notifyUserActivity();
                return gp;
              },
              update: (ctx, settings, tts, prev) {
                prev?.soundEnabled = settings.sound;
                prev?.onUserMove = () => tts.notifyUserActivity();
                return prev ?? GameProvider();
              },
            ),
            ChangeNotifierProxyProvider<TtsEngineService, ReaderProvider>(
              create: (ctx) => ReaderProvider(ctx.read<TtsEngineService>()),
              update: (ctx, tts, previous) => previous ?? ReaderProvider(tts),
            ),
          ],
          child: const _Bootstrapper(),
        );
      },
    );
  }
}

class _Bootstrapper extends StatefulWidget {
  const _Bootstrapper();

  @override
  State<_Bootstrapper> createState() => _BootstrapperState();
}

class _BootstrapperState extends State<_Bootstrapper> {
  bool _booted = false;
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _checkPrivacyAndBootstrap());
  }

  Future<void> _checkPrivacyAndBootstrap() async {
    if (!mounted) return;
    if (!StorageService.hasAgreedPrivacy()) {
      final navContext = _navigatorKey.currentContext;
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

    final reader = context.read<ReaderProvider>();
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
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: _navigatorKey,
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
