import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../features/audio/services/tts_engine_service.dart';

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

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Ensure we start with fresh snapshot when dependencies change
    _previousError = context.read<TtsEngineService>().lastError;
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
              '[TtsErrorListener] New error detected: $err, scheduling SnackBar');
          // Show SnackBar after frame to avoid setState during build
          WidgetsBinding.instance.addPostFrameCallback((_) {
            debugPrint(
                '[TtsErrorListener] Post frame callback executing, mounted=$mounted');
            if (!mounted) {
              debugPrint('[TtsErrorListener] Not mounted, skipping SnackBar');
              return;
            }
            try {
              final scaffold = ScaffoldMessenger.of(context);
              debugPrint(
                  '[TtsErrorListener] Got ScaffoldMessenger, showing SnackBar');
              scaffold
                ..removeCurrentSnackBar()
                ..showSnackBar(SnackBar(content: Text(err)));
              debugPrint('[TtsErrorListener] SnackBar shown successfully');
            } catch (e) {
              debugPrint('[TtsErrorListener] ERROR showing SnackBar: $e');
            }
            tts.clearLastError();
          });
        } else {
          debugPrint(
              '[TtsErrorListener] No new error (err=$err, _previousError=$_previousError)');
        }
        return widget.child;
      },
      child: widget.child,
    );
  }
}
