import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yueyou/core/theme/cyber_colors.dart';
import 'package:yueyou/core/theme/cyber_dimensions.dart';
import 'package:yueyou/core/theme/cyber_text_styles.dart';
import 'package:yueyou/features/xiaoyo/domain/xiaoyo_profile.dart';
import 'package:yueyou/features/xiaoyo/providers/xiaoyo_profile_notifier.dart';
import 'package:yueyou/features/xiaoyo/services/xiaoyo_profile_transfer_service.dart';
import 'package:yueyou/shared/widgets/cyber_confirm_dialog.dart';
import 'package:yueyou/shared/widgets/cyber_toast.dart';

/// Xiaoyo 本地成长数据的导出与恢复操作。
class XiaoyoProfileTransferActions extends ConsumerStatefulWidget {
  /// 创建导出与恢复操作区。
  const XiaoyoProfileTransferActions({
    super.key,
    required this.profile,
  });

  final XiaoyoProfile profile;

  @override
  ConsumerState<XiaoyoProfileTransferActions> createState() =>
      _XiaoyoProfileTransferActionsState();
}

class _XiaoyoProfileTransferActionsState
    extends ConsumerState<XiaoyoProfileTransferActions> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const Text('数据恢复', style: CyberTextStyles.sectionLabel),
        const SizedBox(height: CyberDimensions.spacingS),
        Row(
          children: <Widget>[
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _busy ? null : _export,
                icon: const Icon(Icons.upload_file_outlined),
                label: const Text('导出成长数据'),
                style: _buttonStyle(),
              ),
            ),
            const SizedBox(width: CyberDimensions.spacingS),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _busy ? null : _import,
                icon: const Icon(Icons.file_open_outlined),
                label: const Text('恢复成长数据'),
                style: _buttonStyle(),
              ),
            ),
          ],
        ),
      ],
    );
  }

  ButtonStyle _buttonStyle() => OutlinedButton.styleFrom(
        foregroundColor: CyberColors.neonCyan,
        side: const BorderSide(color: CyberColors.neonCyan),
        padding: const EdgeInsets.symmetric(
          horizontal: CyberDimensions.spacingS,
          vertical: CyberDimensions.spacingMS,
        ),
      );

  Future<void> _export() async {
    await _runTransfer(() async {
      final result = await ref
          .read(xiaoyoProfileTransferServiceProvider)
          .exportProfile(widget.profile);
      if (!mounted) return;
      final message = switch (result.status) {
        XiaoyoTransferStatus.completed => '成长数据已导出',
        XiaoyoTransferStatus.cancelled => '已取消导出',
        XiaoyoTransferStatus.failed => result.message ?? '导出失败',
      };
      CyberToast.show(
        message,
        type: result.status == XiaoyoTransferStatus.failed
            ? ToastType.error
            : ToastType.success,
      );
    });
  }

  Future<void> _import() async {
    await _runTransfer(() async {
      final result =
          await ref.read(xiaoyoProfileTransferServiceProvider).importProfile();
      if (!mounted || result.status != XiaoyoTransferStatus.completed) {
        if (mounted && result.status == XiaoyoTransferStatus.failed) {
          CyberToast.show(
            result.message ?? '恢复失败',
            type: ToastType.error,
          );
        }
        return;
      }
      final profile = result.profile;
      if (profile == null) return;
      final confirmed = await showCyberConfirmDialog(
        context: context,
        title: '恢复成长数据',
        message: '当前本地成长会被导入文件替换，现有文件仍保留在本机备份中。',
        confirmText: '恢复',
        cancelText: '取消',
      );
      if (!confirmed || !mounted) return;
      final restored = await ref
          .read(xiaoyoProfileProvider.notifier)
          .replaceProfile(profile);
      if (!mounted) return;
      CyberToast.show(
        restored ? '成长数据已恢复' : '成长数据恢复失败',
        type: restored ? ToastType.success : ToastType.error,
      );
    });
  }

  Future<void> _runTransfer(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}
