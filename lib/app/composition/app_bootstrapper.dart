import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:yueyou/core/constants/book_constants.dart';
import 'package:yueyou/core/database/storage_service.dart';
import 'package:yueyou/core/theme/cyber_animation_scope.dart';
import 'package:yueyou/core/theme/cyber_colors.dart';
import 'package:yueyou/features/audio/providers/tts_audio_notifier.dart';
import 'package:yueyou/features/audio/services/ambient_service.dart';
import 'package:yueyou/features/audio/services/tts_engine_service.dart';
import 'package:yueyou/features/dashboard/presentation/dashboard_screen.dart';
import 'package:yueyou/features/library/domain/book_model.dart';
import 'package:yueyou/features/reader/providers/reader_provider.dart';
import 'package:yueyou/features/settings/providers/settings_provider.dart';
import 'tts_error_listener.dart';

/// 应用组合根，负责连接跨功能模块的生命周期和启动装配。
class AppBootstrapper extends ConsumerStatefulWidget {
  final GlobalKey<NavigatorState> navigatorKey;

  const AppBootstrapper({super.key, required this.navigatorKey});

  @override
  ConsumerState<AppBootstrapper> createState() => _AppBootstrapperState();
}

class _AppBootstrapperState extends ConsumerState<AppBootstrapper>
    with WidgetsBindingObserver {
  bool _booted = false;

  /// 记录上一次 SettingsProvider 的环境音状态，用于增量同步。
  bool? _lastAmbientEnabled;
  double? _lastAmbientVol;
  String? _lastAmbientStyle;

  @override
  void initState() {
    super.initState();
    ref.listenManual<SettingsProvider>(
      settingsProvider,
      (_, next) => _syncAmbient(next),
    );
    WidgetsBinding.instance
      ..addObserver(this)
      ..addPostFrameCallback((_) => _bootstrap());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncAmbient(ref.read(settingsProvider));
  }

  /// 把设置状态同步到环境音基础设施，保持设置 Provider 与服务解耦。
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

  /// 应用生命周期连接到环境音与 TTS 的后台策略。
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

  /// 恢复当前书籍；默认书由 readerProvider 的懒加载路径独占处理。
  Future<void> _bootstrap() async {
    if (_booted) return;
    _booted = true;

    final reader = ref.read(readerProvider);
    final currentNovelId = StorageService.getCurrentNovelId();
    if (currentNovelId == null ||
        currentNovelId == BookConstants.defaultBookKey) {
      return;
    }

    final content = await StorageService.loadBookContent(currentNovelId);
    if (!mounted || content == null) return;

    final rawLines = content['lines'] as List<dynamic>? ?? [];
    final rawChapters = content['chapters'] as List<dynamic>? ?? [];
    final chapters = rawChapters
        .map((e) => ChapterModel.fromJson(e as Map<String, dynamic>))
        .toList();
    final lines = rawLines.map((e) => e.toString()).toList();
    final initialIndex = StorageService.getCurrentNovelIndex();

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
      navigatorKey: widget.navigatorKey,
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
        child: CyberAnimationScope(
          animationLevel: ref.watch(settingsProvider).currentAnimationLevel,
          child: TtsErrorListener(child: child!),
        ),
      ),
      home: const DashboardScreen(),
    );
  }
}
