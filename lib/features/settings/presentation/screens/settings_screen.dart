import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:yueyou/core/config/app_info_config.dart';
import 'package:yueyou/core/database/storage_service.dart';
import 'package:yueyou/core/theme/cyber_animation_scope.dart';
import 'package:yueyou/core/theme/cyber_colors.dart';
import 'package:yueyou/core/theme/cyber_dimensions.dart';
import 'package:yueyou/core/theme/cyber_text_styles.dart';
import 'package:yueyou/core/utils/cyber_performance_detector.dart';
import 'package:yueyou/features/settings/constants/settings_texts.dart';
import 'package:yueyou/features/settings/providers/settings_provider.dart';
import 'package:yueyou/features/audio/providers/tts_audio_notifier.dart';
import 'package:yueyou/features/audio/services/tts_engine_service.dart';
import 'package:yueyou/features/audio/services/ambient_service.dart';
import 'package:yueyou/shared/widgets/cyber_toast.dart';
import 'package:yueyou/core/constants/cyber_error_messages.dart';
import 'package:yueyou/core/utils/cyber_logger.dart';

/// 阅游系统配置界面 - 极客/武侠融合视觉版
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    return Scaffold(
      backgroundColor: CyberColors.background,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(context),
            Expanded(child: _buildBody(context, ref, settings)),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final headerContent = Row(
      children: [
        const SizedBox(width: CyberDimensions.spacingM),
        Container(
          width: 4,
          height: 16,
          decoration: BoxDecoration(
            color: CyberColors.neonGreen,
            boxShadow: [
              BoxShadow(
                color: CyberColors.neonGreen.withValues(alpha: 0.5),
                blurRadius: CyberDimensions.shadowBlurXS,
              ),
            ],
          ),
        ),
        const SizedBox(width: CyberDimensions.spacingS),
        Text(
          SettingsTexts.screenTitle,
          style: CyberTextStyles.screenTitle.copyWith(
            color: CyberColors.neonGreen,
            letterSpacing: 1.2,
          ),
        ),
        const Spacer(),
        IconButton(
          icon: const Icon(Icons.close, color: CyberColors.whiteDim),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
    final isLowPerformance =
        CyberAnimationScope.of(context) == CyberAnimationLevel.low;

    return Container(
      height: CyberDimensions.headerHeight,
      decoration: BoxDecoration(
        color: CyberColors.panelBackground.withValues(alpha: 0.8),
        border: const Border(
          bottom: BorderSide(color: CyberColors.whiteFaint, width: 1),
        ),
      ),
      child: isLowPerformance
          ? headerContent
          : ClipRect(
              child: BackdropFilter(
                filter: ImageFilter.blur(
                  sigmaX: CyberDimensions.blurLight,
                  sigmaY: CyberDimensions.blurLight,
                ),
                child: headerContent,
              ),
            ),
    );
  }

  Widget _buildBody(
    BuildContext context,
    WidgetRef ref,
    SettingsProvider settings,
  ) {
    return ListView(
      padding: const EdgeInsets.symmetric(
        horizontal: CyberDimensions.spacingM,
        vertical: CyberDimensions.spacingL,
      ),
      physics: const BouncingScrollPhysics(),
      children: [
        // ── 语音播报 ──────────────────────────────────────────────
        const _SectionTitle(
          title: SettingsTexts.ttsSectionTitle,
          icon: Icons.record_voice_over,
        ),
        _ToggleTile(
          label: SettingsTexts.autoReadTitle,
          subtitle: SettingsTexts.autoReadSubtitle,
          value: settings.storyTts,
          activeColor: CyberColors.neonCyan,
          onChanged: (v) async {
            await settings.setStoryTts(v);
            if (v) {
              ref.read(ttsAudioProvider.notifier).refreshSession();
            } else {
              ref.read(ttsAudioProvider.notifier).stopAll();
            }
          },
        ),
        const SizedBox(height: CyberDimensions.spacingM),
        const _LabelRow(label: SettingsTexts.voiceLabel),
        _VoiceSelector(settings: settings),
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: CyberDimensions.spacingS,
            vertical: CyberDimensions.spacingS,
          ),
          child: Text(
            SettingsTexts.voiceHint,
            style: CyberTextStyles.captionHint.copyWith(
              color: CyberColors.neonCyan.withValues(alpha: 0.7),
              fontSize: 10,
            ),
          ),
        ),
        const SizedBox(height: CyberDimensions.spacingS),
        const _TtsTestButton(),
        const SizedBox(height: CyberDimensions.spacingXL),

        // ── 环境氛围 ──────────────────────────────────────────────
        const _SectionTitle(
          title: SettingsTexts.ambientSectionTitle,
          icon: Icons.waves,
        ),
        _ToggleTile(
          label: SettingsTexts.ambientSoundTitle,
          subtitle: SettingsTexts.ambientSoundSubtitle,
          value: settings.ambientEnabled,
          activeColor: CyberColors.neonPurple,
          onChanged: (v) async {
            await settings.setAmbientEnabled(v);
            await AmbientService.setEnabled(v);
          },
        ),
        if (settings.ambientEnabled) ...[
          const SizedBox(height: CyberDimensions.spacingM),
          const _LabelRow(label: SettingsTexts.ambientStyleLabel),
          _ChoiceSelector<String>(
            value: settings.ambientStyle,
            options: const {
              'wuxia': SettingsTexts.ambientStyleWuxia,
              'warm': SettingsTexts.ambientStyleWarm,
            },
            onChanged: (v) async {
              await settings.setAmbientStyle(v);
              await AmbientService.setStyle(v);
            },
          ),
          const SizedBox(height: CyberDimensions.spacingM),
          const _LabelRow(label: SettingsTexts.ambientVolumeLabel),
          _AmbientVolumeSlider(settings: settings),
        ],
        const SizedBox(height: CyberDimensions.spacingXL),

        // ── 静默暂停 ──────────────────────────────────────────────
        const _SectionTitle(
          title: SettingsTexts.powerSectionTitle,
          icon: Icons.timer_outlined,
        ),
        const _LabelRow(label: SettingsTexts.idleTimeoutLabel),
        _ChoiceSelector<int>(
          value: settings.idleTimeout,
          options: const {
            0: SettingsTexts.idleNever,
            1: SettingsTexts.idleOneMinute,
            5: SettingsTexts.idleFiveMinutes,
            10: SettingsTexts.idleTenMinutes,
            20: SettingsTexts.idleTwentyMinutes,
            30: SettingsTexts.idleThirtyMinutes,
            60: SettingsTexts.idleOneHour,
          },
          onChanged: (v) => settings.setIdleTimeout(v),
        ),
        const SizedBox(height: CyberDimensions.spacingXL),

        // ── 系统 ──────────────────────────────────────────────
        const _SectionTitle(
          title: SettingsTexts.systemSoundSectionTitle,
          icon: Icons.settings_input_component,
        ),
        _ToggleTile(
          label: SettingsTexts.mergeSoundTitle,
          subtitle: SettingsTexts.mergeSoundSubtitle,
          value: settings.sound,
          activeColor: CyberColors.neonGreen,
          onChanged: (v) => settings.setSound(v),
        ),
        const SizedBox(height: CyberDimensions.spacingXL),

        const _SectionTitle(
          title: SettingsTexts.privacyComplianceTitle,
          icon: Icons.privacy_tip_outlined,
        ),
        const _PrivacyPolicyTile(),
        const SizedBox(height: CyberDimensions.spacingM),
        const _PrivacyConsentRevokeTile(),
        const SizedBox(height: 100), // 留白，防止被底部按钮遮挡
      ],
    );
  }
}

class _PrivacyConsentRevokeTile extends ConsumerWidget {
  const _PrivacyConsentRevokeTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      decoration: BoxDecoration(
        color: CyberColors.surface,
        borderRadius: BorderRadius.circular(CyberDimensions.radiusM),
        border: Border.all(color: CyberColors.neonPink.withValues(alpha: 0.4)),
      ),
      child: Material(
        color: CyberColors.transparent,
        child: InkWell(
          onTap: () => _revokeConsent(context, ref),
          borderRadius: BorderRadius.circular(CyberDimensions.radiusM),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: CyberDimensions.spacingM,
              vertical: CyberDimensions.spacingMS,
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.logout_rounded,
                  color: CyberColors.neonPink,
                  size: 16,
                ),
                const SizedBox(width: CyberDimensions.spacingM),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        SettingsTexts.privacyRevokeTitle,
                        style: CyberTextStyles.tileTitle.copyWith(
                          color: CyberColors.whiteDim,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: CyberDimensions.spacingXXS),
                      Text(
                        SettingsTexts.privacyRevokeSubtitle,
                        style: CyberTextStyles.tileSubtitle.copyWith(
                          color: CyberColors.whiteMuted,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.chevron_right,
                  color: CyberColors.whiteMuted,
                  size: 14,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _revokeConsent(BuildContext context, WidgetRef ref) async {
    await ref.read(ttsAudioProvider.notifier).stopAll();
    AmbientService.dispose();
    await StorageService.setHasAgreedPrivacy(false);
    await CyberLogger.closeSentrySession();
    CyberLogger.captureMessage('用户撤回隐私授权，应用将退出并在下次启动进入同意页', tag: 'privacy');
    if (!context.mounted) return;
    SystemNavigator.pop();
  }
}

class _PrivacyPolicyTile extends StatelessWidget {
  const _PrivacyPolicyTile();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: CyberColors.surface,
        borderRadius: BorderRadius.circular(CyberDimensions.radiusM),
        border: Border.all(color: CyberColors.whiteFaint),
      ),
      child: Material(
        color: CyberColors.transparent,
        child: InkWell(
          onTap: () => launchUrl(
            Uri.parse(AppInfoConfig.privacyPolicyUrl),
            mode: LaunchMode.externalApplication,
          ),
          borderRadius: BorderRadius.circular(CyberDimensions.radiusM),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: CyberDimensions.spacingM,
              vertical: CyberDimensions.spacingMS,
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.policy_outlined,
                  color: CyberColors.neonCyan,
                  size: 16,
                ),
                const SizedBox(width: CyberDimensions.spacingM),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        SettingsTexts.privacyPolicyTitle,
                        style: CyberTextStyles.tileTitle.copyWith(
                          color: CyberColors.whiteDim,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: CyberDimensions.spacingXXS),
                      Text(
                        SettingsTexts.privacyPolicySubtitle,
                        style: CyberTextStyles.tileSubtitle.copyWith(
                          color: CyberColors.whiteMuted,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.open_in_new,
                  color: CyberColors.whiteMuted,
                  size: 14,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;
  final IconData icon;
  const _SectionTitle({required this.title, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: CyberDimensions.spacingM),
      child: Row(
        children: [
          Icon(icon, size: 14, color: CyberColors.whiteMuted),
          const SizedBox(width: 8),
          Text(
            title.toUpperCase(),
            style: CyberTextStyles.sectionLabel.copyWith(
              letterSpacing: 2,
              fontSize: 10,
              color: CyberColors.whiteMuted,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Container(
              height: 1,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [CyberColors.whiteFaint, CyberColors.transparent],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LabelRow extends StatelessWidget {
  final String label;
  const _LabelRow({required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(
        left: CyberDimensions.spacingXS,
        bottom: CyberDimensions.spacingS,
      ),
      child: Text(
        label,
        style: CyberTextStyles.labelMedium.copyWith(
          color: CyberColors.whiteDim,
          fontSize: 11,
          fontFamily: CyberTextStyles.monoFont,
        ),
      ),
    );
  }
}

class _ToggleTile extends StatelessWidget {
  final String label;
  final String subtitle;
  final bool value;
  final Color activeColor;
  final ValueChanged<bool> onChanged;

  const _ToggleTile({
    required this.label,
    required this.subtitle,
    required this.value,
    required this.activeColor,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: CyberDimensions.animNormal,
      decoration: BoxDecoration(
        color: value
            ? CyberColors.surface.withValues(alpha: 0.6)
            : CyberColors.surface,
        borderRadius: BorderRadius.circular(CyberDimensions.radiusM),
        border: Border.all(
          color: value
              ? activeColor.withValues(alpha: 0.4)
              : CyberColors.whiteFaint,
          width: 1,
        ),
        boxShadow: value
            ? [
                BoxShadow(
                  color: activeColor.withValues(alpha: 0.05),
                  blurRadius: CyberDimensions.shadowBlurS,
                  spreadRadius: -2,
                ),
              ]
            : null,
      ),
      child: Material(
        color: CyberColors.transparent,
        borderRadius: BorderRadius.circular(CyberDimensions.radiusM),
        clipBehavior: Clip.antiAlias,
        child: SwitchListTile(
          title: Text(
            label,
            style: CyberTextStyles.tileTitle.copyWith(
              color: value ? CyberColors.white : CyberColors.whiteDim,
              fontSize: 14,
            ),
          ),
          subtitle: Text(
            subtitle,
            style: CyberTextStyles.tileSubtitle.copyWith(
              color: CyberColors.whiteMuted,
              fontSize: 11,
            ),
          ),
          value: value,
          onChanged: onChanged,
          activeTrackColor: activeColor.withValues(alpha: 0.2),
          activeThumbColor: activeColor,
          inactiveThumbColor: CyberColors.whiteDim,
          inactiveTrackColor: CyberColors.whiteFaint,
        ),
      ),
    );
  }
}

class _ChoiceSelector<T> extends StatelessWidget {
  final T value;
  final Map<T, String> options;
  final ValueChanged<T> onChanged;

  const _ChoiceSelector({
    required this.value,
    required this.options,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(CyberDimensions.spacingXS),
      decoration: BoxDecoration(
        color: CyberColors.surface,
        borderRadius: BorderRadius.circular(CyberDimensions.radiusL),
        border: Border.all(color: CyberColors.whiteFaint),
      ),
      child: Row(
        children: options.entries.map((entry) {
          final isSelected = entry.key == value;
          return Expanded(
            child: GestureDetector(
              onTap: () => onChanged(entry.key),
              child: AnimatedContainer(
                duration: CyberDimensions.animFast,
                padding: const EdgeInsets.symmetric(
                  vertical:
                      CyberDimensions.spacingS + CyberDimensions.spacingXXS,
                ),
                decoration: BoxDecoration(
                  gradient: isSelected
                      ? LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            CyberColors.whiteFaint.withValues(alpha: 0.2),
                            CyberColors.whiteFaint.withValues(alpha: 0.05),
                          ],
                        )
                      : null,
                  borderRadius: BorderRadius.circular(CyberDimensions.radiusL),
                  boxShadow: isSelected
                      ? [
                          BoxShadow(
                            color: CyberColors.background.withValues(
                              alpha: 0.4,
                            ),
                            blurRadius: CyberDimensions.shadowBlurXS,
                            offset: const Offset(0, 2),
                          ),
                        ]
                      : null,
                ),
                child: Center(
                  child: Text(
                    entry.value,
                    style: CyberTextStyles.bodySmall.copyWith(
                      color: isSelected
                          ? CyberColors.white
                          : CyberColors.whiteMuted,
                      fontWeight:
                          isSelected ? FontWeight.bold : FontWeight.normal,
                      fontSize: 12,
                    ),
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _VoiceSelector extends ConsumerWidget {
  final SettingsProvider settings;
  static const Map<String, String> _voices = {
    'zh-CN-XiaoxiaoNeural': SettingsTexts.voiceXiaoxiao,
    'zh-CN-YunxiNeural': SettingsTexts.voiceYunxi,
    'zh-CN-YunjianNeural': SettingsTexts.voiceYunjian,
    'zh-CN-XiaoyiNeural': SettingsTexts.voiceXiaoyi,
    'zh-CN-XiaomengNeural': SettingsTexts.voiceXiaomeng,
  };

  const _VoiceSelector({required this.settings});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: CyberDimensions.spacingM),
      decoration: BoxDecoration(
        color: CyberColors.surface,
        borderRadius: BorderRadius.circular(CyberDimensions.radiusM),
        border: Border.all(color: CyberColors.whiteFaint),
      ),
      child: DropdownButton<String>(
        value: _voices.containsKey(settings.voice) ? settings.voice : null,
        isExpanded: true,
        dropdownColor: CyberColors.surface,
        underline: const SizedBox.shrink(),
        icon: const Icon(
          Icons.keyboard_arrow_down,
          color: CyberColors.whiteMuted,
        ),
        items: _voices.entries.map((e) {
          return DropdownMenuItem(
            value: e.key,
            child: Text(
              e.value,
              style: CyberTextStyles.bodySmall.copyWith(
                color: CyberColors.whiteDim,
                fontSize: 13,
              ),
            ),
          );
        }).toList(),
        onChanged: (v) async {
          if (v == null) return;
          await settings.setVoice(v);
          if (settings.storyTts) {
            ref.read(ttsAudioProvider.notifier).refreshSession();
          }
        },
      ),
    );
  }
}

class _TtsTestButton extends ConsumerStatefulWidget {
  const _TtsTestButton();

  @override
  ConsumerState<_TtsTestButton> createState() => _TtsTestButtonState();
}

class _TtsTestButtonState extends ConsumerState<_TtsTestButton> {
  bool _isTesting = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: _isTesting ? CyberColors.surface : CyberColors.transparent,
        borderRadius: BorderRadius.circular(CyberDimensions.radiusM),
        border: Border.all(color: CyberColors.neonCyan.withValues(alpha: 0.3)),
      ),
      child: Material(
        color: CyberColors.transparent,
        child: InkWell(
          onTap: _isTesting ? null : _testTtsConnection,
          borderRadius: BorderRadius.circular(CyberDimensions.radiusM),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: CyberDimensions.spacingM,
              vertical: CyberDimensions.spacingMS,
            ),
            child: Row(
              children: [
                if (_isTesting)
                  const SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(
                      color: CyberColors.neonCyan,
                      strokeWidth: 2,
                    ),
                  )
                else
                  const Icon(
                    Icons.terminal,
                    color: CyberColors.neonCyan,
                    size: 14,
                  ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _isTesting
                        ? SettingsTexts.ttsTestingLabel
                        : SettingsTexts.ttsTestButtonLabel,
                    style: CyberTextStyles.bodySmallBold.copyWith(
                      color: CyberColors.neonCyan,
                      fontSize: 12,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
                const Icon(
                  Icons.chevron_right,
                  color: CyberColors.whiteMuted,
                  size: 14,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _testTtsConnection() async {
    final tts = ref.read(ttsEngineProvider);
    setState(() => _isTesting = true);
    try {
      final result = await tts.testConnection();
      if (!mounted) return;
      setState(() => _isTesting = false);
      showDialog<void>(
        context: context,
        builder: (context) => _TtsTestResultDialog(result: result),
      );
    } catch (e, st) {
      CyberLogger.captureWarning(
        e is Exception ? e : Exception('$e'),
        stack: st,
        tag: 'tts',
        extra: {'context': SettingsTexts.ttsTestExceptionContext},
      );
      if (!mounted) return;
      setState(() => _isTesting = false);
      CyberToast.show(
        CyberErrorMessages.testFailedUnresponsive,
        context: context,
        type: ToastType.error,
      );
    }
  }
}

class _TtsTestResultDialog extends StatelessWidget {
  final Map<String, dynamic> result;
  const _TtsTestResultDialog({required this.result});

  @override
  Widget build(BuildContext context) {
    final success = result['success'] as bool;
    final steps = result['steps'] as List<Map<String, dynamic>>;

    return Dialog(
      backgroundColor: CyberColors.panelBackground,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(CyberDimensions.radiusL),
        side: BorderSide(
          color: success ? CyberColors.neonGreen : CyberColors.neonPink,
          width: 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(CyberDimensions.spacingML),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              success
                  ? SettingsTexts.ttsTestSuccessTitle
                  : SettingsTexts.ttsTestFailureTitle,
              style: CyberTextStyles.dialogTitle.copyWith(
                color: success ? CyberColors.neonGreen : CyberColors.neonPink,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: CyberDimensions.spacingM),
            ...steps.take(4).map(
                  (step) => Padding(
                    padding: const EdgeInsets.only(bottom: 8.0),
                    child: Row(
                      children: [
                        Icon(
                          step['status'] == 'success'
                              ? Icons.check
                              : Icons.close,
                          size: 14,
                          color: step['status'] == 'success'
                              ? CyberColors.neonGreen
                              : CyberColors.neonPink,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          step['name'] as String,
                          style: CyberTextStyles.bodySmall.copyWith(
                            color: CyberColors.whiteDim,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            const SizedBox(height: CyberDimensions.spacingML),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.of(context).pop(),
                style: ElevatedButton.styleFrom(
                  backgroundColor:
                      success ? CyberColors.neonGreen : CyberColors.neonPink,
                  foregroundColor: CyberColors.background,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(
                      CyberDimensions.radiusS,
                    ),
                  ),
                ),
                child: const Text(
                  SettingsTexts.confirmButtonLabel,
                  style: CyberTextStyles.buttonLabel,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AmbientVolumeSlider extends StatelessWidget {
  final SettingsProvider settings;
  const _AmbientVolumeSlider({required this.settings});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: CyberDimensions.spacingS),
      decoration: BoxDecoration(
        color: CyberColors.surface,
        borderRadius: BorderRadius.circular(CyberDimensions.radiusM),
        border: Border.all(color: CyberColors.whiteFaint),
      ),
      child: Row(
        children: [
          const SizedBox(width: 12),
          const Icon(
            Icons.volume_down,
            size: 14,
            color: CyberColors.whiteMuted,
          ),
          Expanded(
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                activeTrackColor: CyberColors.neonPurple,
                inactiveTrackColor: CyberColors.whiteFaint,
                thumbColor: CyberColors.white,
                overlayColor: CyberColors.neonPurple.withValues(alpha: 0.1),
                trackHeight: 2.0,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
              ),
              child: Slider(
                value: settings.ambientVol,
                onChanged: (v) async {
                  await settings.setAmbientVol(v);
                  await AmbientService.setVolume(v);
                },
              ),
            ),
          ),
          Text(
            '${(settings.ambientVol * 100).round()}%',
            style: CyberTextStyles.captionBold.copyWith(
              color: CyberColors.neonPurple,
              fontSize: 10,
              fontFamily: CyberTextStyles.monoFont,
            ),
          ),
          const SizedBox(width: 12),
        ],
      ),
    );
  }
}
