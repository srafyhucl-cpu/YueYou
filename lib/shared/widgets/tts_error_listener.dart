import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme/cyber_colors.dart';
import '../../core/theme/cyber_dimensions.dart';
import '../../features/audio/services/tts_engine_service.dart';
import 'cyber_toast.dart';

/// Wrap any screen or the whole app with this widget to automatically
/// display a SnackBar whenever `TtsEngineService.lastError` becomes non-null.
class TtsErrorListener extends StatefulWidget {
  final Widget child;
  const TtsErrorListener({super.key, required this.child});

  @override
  State<TtsErrorListener> createState() => _TtsErrorListenerState();
}

class _TtsErrorListenerState extends State<TtsErrorListener> {
  String? _previousError;
  String? _previousFallback;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Ensure we start with fresh snapshot when dependencies change
    _previousError = context.read<TtsEngineService>().lastError;
    _previousFallback = context.read<TtsEngineService>().fallbackNotification;
  }

  @override
  Widget build(BuildContext context) {
    debugPrint('[TtsErrorListener] building, will listen to TtsEngineService');
    return Consumer<TtsEngineService>(
      builder: (context, tts, child) {
        final err = tts.lastError;
        debugPrint(
            '[TtsErrorListener] Consumer builder called, lastError=$err, _previousError=$_previousError');
        if (err != null && err != _previousError) {
          _previousError = err;
          debugPrint(
              '[TtsErrorListener] New error detected: $err, scheduling CyberToast');
          WidgetsBinding.instance.addPostFrameCallback((_) {
            debugPrint(
                '[TtsErrorListener] Post frame callback executing, mounted=$mounted');
            if (!mounted) {
              debugPrint('[TtsErrorListener] Not mounted, skipping CyberToast');
              return;
            }
            try {
              debugPrint(
                  '[TtsErrorListener] Showing CyberToast for error: $err');
              CyberToast.show(context, err, type: ToastType.error);
              debugPrint('[TtsErrorListener] CyberToast shown successfully');
            } catch (e) {
              debugPrint('[TtsErrorListener] ERROR showing CyberToast: $e');
            }
            tts.clearLastError();
          });
        } else {
          debugPrint(
              '[TtsErrorListener] No new error (err=$err, _previousError=$_previousError)');
        }

        final fallback = tts.fallbackNotification;
        if (fallback != null && fallback != _previousFallback) {
          _previousFallback = fallback;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            try {
              CyberToast.show(context, fallback, type: ToastType.info);
            } catch (e) {
              debugPrint(
                  '[TtsErrorListener] ERROR showing fallback CyberToast: $e');
            }
            tts.clearFallbackNotification();
          });
        }

        return widget.child;
      },
      child: widget.child,
    );
  }
}
