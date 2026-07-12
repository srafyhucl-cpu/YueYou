import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:yueyou/features/audio/services/tts_engine_service.dart';
import 'package:yueyou/features/settings/providers/settings_provider.dart';

/// TTS 引擎全局 Provider，统一托管服务生命周期和设置同步。
final ttsEngineProvider = ChangeNotifierProvider<TtsEngineService>((ref) {
  final settings = ref.read(settingsProvider);
  final service = TtsEngineService(settings, externalSettingsListener: false);

  ref.onDispose(service.dispose);
  ref.listen<SettingsProvider>(
    settingsProvider,
    (_, next) => service.syncSettingsFromProvider(next),
  );
  return service;
});
