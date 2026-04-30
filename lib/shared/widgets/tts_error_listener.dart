import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../features/audio/services/tts_engine_service.dart';
import 'cyber_toast.dart';

/// TTS 错误全局监听器组件
///
/// 将任意页面或整个 App 根节点包裹在此组件下，
/// 每当 [TtsEngineService.lastError] 变为非 null 时，
/// 自动弹出 [CyberToast] 错误提示，无需各页面手动监听。
class TtsErrorListener extends ConsumerStatefulWidget {
  final Widget child;
  const TtsErrorListener({super.key, required this.child});

  @override
  ConsumerState<TtsErrorListener> createState() => _TtsErrorListenerState();
}

class _TtsErrorListenerState extends ConsumerState<TtsErrorListener> {
  int _previousErrorTime = 0;
  String? _previousFallback;
  int _lastFallbackTimestamp = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 依赖变化时刷新快照，避免初始化重复触发旧错误
    _previousErrorTime = ref.read(ttsEngineProvider).errorTimestamp;
    _previousFallback = ref.read(ttsEngineProvider).fallbackNotification;
  }

  @override
  Widget build(BuildContext context) {
    debugPrint('[TtsErrorListener] 正在构建，监听 TtsEngineService 状态');
    final tts = ref.watch(ttsEngineProvider);
    final err = tts.lastError;
        final currentTimestamp = DateTime.now().millisecondsSinceEpoch;
        
        if (err != null && tts.errorTimestamp != _previousErrorTime) {
          _previousErrorTime = tts.errorTimestamp;
          debugPrint(
              '[TtsErrorListener] 检测到新错误: $err，将展示 CyberToast',);
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            try {
              CyberToast.show(err, type: ToastType.error);
            } catch (e) {
              debugPrint('[TtsErrorListener] 展示 CyberToast 失败: $e');
            }
          });
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
                CyberToast.show(fallback, type: ToastType.info);
              } catch (e) {
                debugPrint(
                    '[TtsErrorListener] 展示降级通知 CyberToast 失败: $e',);
              }
            });
          }
        }

        return widget.child;
  }
}
