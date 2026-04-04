import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:yueyou/core/theme/cyber_colors.dart';
import 'package:yueyou/core/theme/cyber_dimensions.dart';
import 'package:yueyou/core/theme/cyber_text_styles.dart';
import 'package:yueyou/shared/widgets/cyber_modal.dart';

/// 赛博朋克风格隐私协议弹窗
/// - barrierDismissible: false，强制用户作出选择
/// - 返回 true 表示同意，用户拒绝时直接退出应用
Future<bool> showPrivacyAgreementModal(BuildContext context) async {
  final result = await showCyberModal<bool>(
    context: context,
    barrierDismissible: false,
    child: const _PrivacyAgreementContent(),
  );
  return result ?? false;
}

class _PrivacyAgreementContent extends StatelessWidget {
  const _PrivacyAgreementContent();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(CyberDimensions.spacingL),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── 图标 + 标题 ─────────────────────────────────────────
          const Icon(
            Icons.security_rounded,
            color: CyberColors.neonCyan,
            size: CyberDimensions.iconL,
          ),
          const SizedBox(height: CyberDimensions.spacingS),
          Text(
            '神经接驳协议',
            style: CyberTextStyles.screenTitle.copyWith(
              color: CyberColors.neonCyan,
              fontSize: 20,
            ),
          ),
          const SizedBox(height: CyberDimensions.spacingXS),
          Text(
            'NEURAL LINK AGREEMENT  v1.0',
            style: CyberTextStyles.caption.copyWith(
              color: CyberColors.whiteMuted,
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(height: CyberDimensions.spacingM),

          // ── 协议正文（可滚动）────────────────────────────────────
          Container(
            constraints: const BoxConstraints(maxHeight: 280),
            decoration: BoxDecoration(
              color: CyberColors.whiteFaint,
              borderRadius: BorderRadius.circular(CyberDimensions.radiusS),
              border: Border.all(
                color: CyberColors.neonCyan.withOpacity(0.2),
                width: CyberDimensions.borderThin,
              ),
            ),
            child: const SingleChildScrollView(
              padding: EdgeInsets.all(CyberDimensions.spacingM),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _PolicySection(
                    icon: '📡',
                    title: '数据存储',
                    body: '所有阅读进度、游戏数据及用户设置仅存储于您的本地设备。'
                        '我们不会将您的个人数据上传至任何远端服务器。',
                  ),
                  SizedBox(height: CyberDimensions.spacingM),
                  _PolicySection(
                    icon: '🔊',
                    title: '云端 TTS 合成',
                    body: '当您启用听书功能时，当前朗读的文本段落将通过加密信道发送至'
                        '云端 TTS 服务以合成音频。除朗读文本外，不传输任何其他信息。',
                  ),
                  SizedBox(height: CyberDimensions.spacingM),
                  _PolicySection(
                    icon: '📂',
                    title: '存储权限',
                    body: '导入数据芯片（TXT 文件）时，本应用需要访问您设备的本地存储。'
                        '此权限仅用于读取您主动选择的文件，不会扫描其他目录。',
                  ),
                  SizedBox(height: CyberDimensions.spacingM),
                  _PolicySection(
                    icon: '🛡',
                    title: '隐私承诺',
                    body: '• 不采集设备标识符或位置信息\n'
                        '• 不追踪用户行为或使用习惯\n'
                        '• 不向任何第三方共享数据\n'
                        '• 符合《个人信息保护法》及 GDPR',
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: CyberDimensions.spacingM),

          // ── 提示 + 隐私政策外链 ─────────────────────────────────
          Wrap(
            alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                '同意后，您可在设置页面随时重新查看本协议· ',
                textAlign: TextAlign.center,
                style: CyberTextStyles.caption.copyWith(
                  color: CyberColors.whiteMuted,
                ),
              ),
              GestureDetector(
                onTap: () => launchUrl(
                  Uri.parse('https://docs.qq.com/doc/DVXpHSW9qRkFZVVlN'),
                  mode: LaunchMode.externalApplication,
                ),
                child: Text(
                  '阅读完整版《阅游隐私政策》',
                  style: CyberTextStyles.caption.copyWith(
                    color: CyberColors.neonCyan,
                    decoration: TextDecoration.underline,
                    decorationColor: CyberColors.neonCyan,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: CyberDimensions.spacingL),

          // ── 按钮行 ───────────────────────────────────────────────
          Row(
            children: [
              // 拒绝并退出（危险操作，用粉色/红色边框区分）
              Expanded(
                child: _DeclineButton(
                  onTap: () {
                    Navigator.of(context).pop(false);
                    SystemNavigator.pop();
                  },
                ),
              ),
              const SizedBox(width: CyberDimensions.spacingMS),
              // 同意接入（主按钮）
              Expanded(
                child: _AgreeButton(
                  onTap: () => Navigator.of(context).pop(true),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── 协议条款单节 ──────────────────────────────────────────────────────────────
class _PolicySection extends StatelessWidget {
  final String icon;
  final String title;
  final String body;

  const _PolicySection({
    required this.icon,
    required this.title,
    required this.body,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(icon, style: const TextStyle(fontSize: 14)),
            const SizedBox(width: CyberDimensions.spacingXS),
            Text(
              title,
              style: const TextStyle(
                color: CyberColors.neonCyan,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: CyberDimensions.spacingXS),
        Text(
          body,
          style: const TextStyle(
            color: CyberColors.whiteMedium,
            fontSize: 12,
            height: 1.55,
          ),
        ),
      ],
    );
  }
}

// ── 拒绝按钮（霓虹粉边框，危险语义）────────────────────────────────────────
class _DeclineButton extends StatelessWidget {
  final VoidCallback onTap;
  const _DeclineButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding:
            const EdgeInsets.symmetric(vertical: CyberDimensions.spacingMS),
        decoration: BoxDecoration(
          color: CyberColors.neonPink.withOpacity(0.08),
          borderRadius: BorderRadius.circular(CyberDimensions.radiusS),
          border: Border.all(
            color: CyberColors.neonPink.withOpacity(0.5),
            width: CyberDimensions.borderNormal,
          ),
        ),
        child: const Center(
          child: Text(
            '拒绝并退出',
            style: TextStyle(
              color: CyberColors.neonPink,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}

// ── 同意按钮（霓虹青渐变，主语义）──────────────────────────────────────────
class _AgreeButton extends StatelessWidget {
  final VoidCallback onTap;
  const _AgreeButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding:
            const EdgeInsets.symmetric(vertical: CyberDimensions.spacingMS),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [CyberColors.neonCyan, CyberColors.neonPurple],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(CyberDimensions.radiusS),
        ),
        child: const Center(
          child: Text(
            '同意接入',
            style: TextStyle(
              color: CyberColors.background,
              fontSize: 14,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      ),
    );
  }
}
