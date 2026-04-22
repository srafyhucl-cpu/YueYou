import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
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
  int _lastErrorTimestamp = 0;
  String? _previousFallback;
  int _lastFallbackTimestamp = 0;

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
        final currentTimestamp = DateTime.now().millisecondsSinceEpoch;
        
        debugPrint(
            '[TtsErrorListener] Consumer builder called, lastError=$err, _previousError=$_previousError');
        if (err == null) {
          _previousError = null;
        } else {
          final isSameError = err == _previousError;
          final isThrottled = isSameError && (currentTimestamp - _lastErrorTimestamp < 1000);
          
          if (!isThrottled) {
            _previousError = err;
            _lastErrorTimestamp = currentTimestamp;
            debugPrint(
                '[TtsErrorListener] New error detected: $err, scheduling CyberToast');
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              try {
                CyberToast.show(context, err, type: ToastType.error);
              } catch (e) {
                debugPrint('[TtsErrorListener] ERROR showing CyberToast: $e');
              }
            });
          }
        }

        final fallback = tts.fallbackNotification;
        if (fallback == null) {
          _previousFallback = null;
        } else {
          final isSameFallback = fallback == _previousFallback;
          final isThrottled = isSameFallback && (currentTimestamp - _lastFallbackTimestamp < 1000);
          
          if (!isThrottled) {
            _previousFallback = fallback;
            _lastFallbackTimestamp = currentTimestamp;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              try {
                CyberToast.show(context, fallback, type: ToastType.info);
              } catch (e) {
                debugPrint(
                    '[TtsErrorListener] ERROR showing fallback CyberToast: $e');
              }
            });
          }
        }

        return widget.child;
      },
      child: widget.child,
    );
  }
}
