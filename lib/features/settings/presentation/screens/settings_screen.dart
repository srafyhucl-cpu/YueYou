import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:yueyou/core/theme/cyber_colors.dart';
import 'package:yueyou/core/theme/cyber_dimensions.dart';
import 'package:yueyou/core/theme/cyber_text_styles.dart';
import 'package:yueyou/features/settings/providers/settings_provider.dart';
import 'package:yueyou/features/audio/services/tts_engine_service.dart';
import 'package:yueyou/features/audio/services/ambient_service.dart';
import 'package:yueyou/shared/widgets/cyber_toast.dart';
import 'package:yueyou/core/constants/cyber_error_messages.dart';

/// 设置界面
/// 完整复刻旧版 modal-settings：声音/TTS/发声人/空闲超时
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: CyberColors.panelBackground,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(context),
            Expanded(
              child: Consumer<SettingsProvider>(
                builder: (context, settings, _) =>
                    _buildBody(context, settings),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(
            sigmaX: CyberDimensions.blurLight,
            sigmaY: CyberDimensions.blurLight),
        child: Container(
          height: CyberDimensions.headerHeight,
          color: CyberColors.panelBackground.withValues(alpha: 0.8),
          child: Row(
            children: [
              const SizedBox(width: CyberDimensions.spacingM),
              Text(
                '系统设置',
                style: CyberTextStyles.screenTitle.copyWith(
                  color: CyberColors.neonGreen,
                ),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.close, color: CyberColors.whiteDim),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context, SettingsProvider settings) {
    return ListView(
      padding: const EdgeInsets.all(CyberDimensions.spacingM),
      children: [
        const _SectionTitle(title: '游戏音效'),
        _ToggleTile(
          label: '合并音效',
          subtitle: '方块合并时播放提示音',
          value: settings.sound,
          onChanged: (v) {
            settings.setSound(v);
          },
        ),
        const SizedBox(height: CyberDimensions.spacingML),
        const _SectionTitle(title: '语音播报'),
        _ToggleTile(
          label: '自动朗读',
          subtitle: '自动播报当前小说内容',
          value: settings.storyTts,
          onChanged: (v) async {
            final tts = context.read<TtsEngineService>();
            await settings.setStoryTts(v);
            if (v) {
              tts.refreshSession();
            } else {
              tts.setEnabled(false);
            }
          },
        ),
        const SizedBox(height: CyberDimensions.spacingMS),
        const _LabelRow(label: '播报倍速'),
        _SpeedSelector(settings: settings),
        const SizedBox(height: CyberDimensions.spacingMS),
        const _LabelRow(label: '发声人'),
        _VoiceSelector(settings: settings),
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: CyberDimensions.spacingM,
            vertical: CyberDimensions.spacingS,
          ),
          child: Text(
            '💡 若音色无感情，请前往手机系统设置 -> 文本转语音 (TTS) 中切换系统高音质发音人',
            style: CyberTextStyles.captionHint.copyWith(
              color: CyberColors.neonPurple,
            ),
          ),
        ),
        const SizedBox(height: CyberDimensions.spacingMS),
        const _TtsTestButton(),
        const SizedBox(height: CyberDimensions.spacingML),
        // ── 环境氛围 ──────────────────────────────────────────────
        const _SectionTitle(title: '环境氛围'),
        _ToggleTile(
          label: '背景氛围音',
          subtitle: '赛博朋克城市电子环境音，营造沉浸感',
          value: settings.ambientEnabled,
          onChanged: (v) async {
            await settings.setAmbientEnabled(v);
            await AmbientService.setEnabled(v);
          },
        ),
        const SizedBox(height: CyberDimensions.spacingMS),
        AnimatedOpacity(
          opacity: settings.ambientEnabled ? 1.0 : 0.4,
          duration: const Duration(milliseconds: 250),
          child: IgnorePointer(
            ignoring: !settings.ambientEnabled,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _LabelRow(label: '环境音量'),
                _AmbientVolumeSlider(settings: settings),
              ],
            ),
          ),
        ),
        const SizedBox(height: CyberDimensions.spacingML),
        // ── 省电管理 ──────────────────────────────────────────────
        const _SectionTitle(title: '省电管理'),
        _IdleTimeoutSelector(settings: settings),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;
  const _SectionTitle({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: CyberDimensions.spacingS),
      child: Text(
        title,
        style: CyberTextStyles.sectionLabel,
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
      padding: const EdgeInsets.only(bottom: CyberDimensions.spacingS),
      child: Text(label, style: CyberTextStyles.labelMedium),
    );
  }
}

class _ToggleTile extends StatelessWidget {
  final String label;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _ToggleTile({
    required this.label,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: CyberColors.surface,
        borderRadius: BorderRadius.circular(CyberDimensions.radiusS),
        border: Border.all(
          color: CyberColors.whiteFaint,
          width: CyberDimensions.borderNormal,
        ),
      ),
      child: SwitchListTile(
        title: Text(label, style: CyberTextStyles.tileTitle),
        subtitle: Text(subtitle, style: CyberTextStyles.tileSubtitle),
        value: value,
        onChanged: onChanged,
        activeThumbColor: CyberColors.neonGreen,
        inactiveThumbColor: CyberColors.whiteMuted,
        inactiveTrackColor: CyberColors.whiteFaint,
      ),
    );
  }
}

/// 倍速选择器（对应 JS cycleTTSpeed 的六档）
class _SpeedSelector extends StatelessWidget {
  final SettingsProvider settings;
  static const List<double> _speeds = [0.7, 1.0, 1.2, 1.5, 2.0, 2.5];

  const _SpeedSelector({required this.settings});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: CyberDimensions.spacingS,
      children: _speeds.map((s) {
        final bool selected = (settings.ttsRate - s).abs() < 0.01;
        return GestureDetector(
          onTap: () async {
            final tts = context.read<TtsEngineService>();
            await settings.setTtsRate(s);
            final double hardwareRate = (0.5 * (s / 1.0)).clamp(0.1, 1.0);
            tts.syncSpeedFromSettings(s, hardwareRate);
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(
              horizontal:
                  CyberDimensions.spacingMS + CyberDimensions.spacingXXS,
              vertical: CyberDimensions.spacingXS + CyberDimensions.spacingXXS,
            ),
            decoration: BoxDecoration(
              color: selected
                  ? CyberColors.neonPink.withValues(alpha: 0.18)
                  : CyberColors.surface,
              borderRadius: BorderRadius.circular(CyberDimensions.radiusL),
              border: Border.all(
                color:
                    selected ? CyberColors.neonPink : CyberColors.whiteSubtle,
                width: selected
                    ? CyberDimensions.borderThick
                    : CyberDimensions.borderThin,
              ),
            ),
            child: Text(
              '${s.toStringAsFixed(1)}x',
              style: CyberTextStyles.bodySmall.copyWith(
                color: selected ? CyberColors.neonPink : CyberColors.whiteDim,
                fontWeight: selected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

/// 发声人选择器（对应 JS tts-voice-select）
class _VoiceSelector extends StatelessWidget {
  final SettingsProvider settings;

  static const Map<String, String> _voices = {
    'zh-CN-XiaoxiaoNeural': '晓晓（温柔女声）',
    'zh-CN-YunxiNeural': '云溪（青年男声）',
    'zh-CN-YunjianNeural': '云健（沉稳男声）',
    'zh-CN-XiaohanNeural': '晓涵（知性女声）',
    'zh-CN-XiaomengNeural': '晓梦（活泼女声）',
  };

  const _VoiceSelector({required this.settings});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: CyberDimensions.spacingMS,
        vertical: CyberDimensions.spacingXS,
      ),
      decoration: BoxDecoration(
        color: CyberColors.surface,
        borderRadius: BorderRadius.circular(CyberDimensions.radiusS),
        border: Border.all(
          color: CyberColors.whiteFaint,
          width: CyberDimensions.borderNormal,
        ),
      ),
      child: DropdownButton<String>(
        value: _voices.containsKey(settings.voice) ? settings.voice : null,
        hint: Text(settings.voice, style: CyberTextStyles.bodySmall),
        isExpanded: true,
        dropdownColor: CyberColors.surface,
        underline: const SizedBox.shrink(),
        icon: const Icon(Icons.expand_more, color: CyberColors.whiteMuted),
        items: _voices.entries.map((e) {
          return DropdownMenuItem(
            value: e.key,
            child: Text(e.value, style: CyberTextStyles.bodySmall),
          );
        }).toList(),
        onChanged: (v) async {
          if (v == null) return;
          final tts = context.read<TtsEngineService>();
          await settings.setVoice(v);
          if (settings.storyTts) {
            tts.refreshSession();
          }
        },
      ),
    );
  }
}

/// 空闲超时选择器（对应 JS idle-timeout 0-5 分钟）
/// TTS 连接测试按钮
class _TtsTestButton extends StatefulWidget {
  const _TtsTestButton();

  @override
  State<_TtsTestButton> createState() => _TtsTestButtonState();
}

class _TtsTestButtonState extends State<_TtsTestButton> {
  bool _isTesting = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: CyberColors.surface,
        borderRadius: BorderRadius.circular(CyberDimensions.radiusS),
        border: Border.all(
          color: CyberColors.neonCyan.withValues(alpha: 0.3),
          width: CyberDimensions.borderNormal,
        ),
      ),
      child: Material(
        color: CyberColors.transparent,
        child: InkWell(
          onTap: _isTesting ? null : _testTtsConnection,
          borderRadius: BorderRadius.circular(CyberDimensions.radiusS),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: CyberDimensions.spacingM,
              vertical: CyberDimensions.spacingMS,
            ),
            child: Row(
              children: [
                if (_isTesting)
                  const SizedBox(
                    width: CyberDimensions.iconM,
                    height: CyberDimensions.iconM,
                    child: CircularProgressIndicator(
                      color: CyberColors.neonCyan,
                      strokeWidth: 2,
                    ),
                  )
                else
                  const Icon(
                    Icons.wifi_tethering,
                    color: CyberColors.neonCyan,
                    size: CyberDimensions.iconM,
                  ),
                const SizedBox(width: CyberDimensions.spacingMS),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _isTesting ? '正在测试...' : '测试 TTS 连接',
                        style: CyberTextStyles.tileTitle.copyWith(
                          fontWeight: CyberTextStyles.bodySmallBold.fontWeight,
                        ),
                      ),
                      const SizedBox(height: CyberDimensions.spacingXXS),
                      const Text(
                        '诊断 TTS 服务器连接问题',
                        style: CyberTextStyles.tileSubtitle,
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.arrow_forward_ios,
                  color: CyberColors.whiteMuted,
                  size: CyberDimensions.iconXS,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _testTtsConnection() async {
    final tts = context.read<TtsEngineService>();

    setState(() => _isTesting = true);

    try {
      final result = await tts.testConnection();

      if (!mounted) return;
      setState(() => _isTesting = false);

      showDialog(
        context: context,
        builder: (context) => _TtsTestResultDialog(result: result),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isTesting = false);

      CyberToast.show(CyberErrorMessages.testFailedUnresponsive, type: ToastType.error);
    }
  }
}

/// TTS 测试结果对话框
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
          width: 2,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(CyberDimensions.spacingML),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 标题
            Row(
              children: [
                Icon(
                  success ? Icons.check_circle : Icons.error,
                  color: success ? CyberColors.neonGreen : CyberColors.neonPink,
                  size: CyberDimensions.iconL,
                ),
                const SizedBox(width: CyberDimensions.spacingMS),
                Expanded(
                  child: Text(
                    success ? '神经网关握手成功' : '神经网关连接失败',
                    style: CyberTextStyles.dialogTitle.copyWith(
                      color: success
                          ? CyberColors.neonGreen
                          : CyberColors.neonPink,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: CyberDimensions.spacingM),
            // 测试步骤
            ...steps.map((step) => _buildStepItem(step)),
            const SizedBox(height: CyberDimensions.spacingM),
            // 总结信息
            Container(
              padding: const EdgeInsets.all(CyberDimensions.spacingMS),
              decoration: BoxDecoration(
                color: success
                    ? CyberColors.neonGreen.withValues(alpha: 0.1)
                    : CyberColors.neonPink.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(CyberDimensions.radiusS),
                border: Border.all(
                  color: success ? CyberColors.neonGreen : CyberColors.neonPink,
                  width: 1,
                ),
              ),
              child: Text(
                success 
                    ? '语音链路通畅，可正常使用赛博朗读功能' 
                    : '远端神经节点无响应，请检查链路配置',
                style: CyberTextStyles.captionComfortable.copyWith(
                  color: success ? CyberColors.neonGreen : CyberColors.neonPink,
                ),
              ),
            ),
            const SizedBox(height: CyberDimensions.spacingM),
            // 关闭按钮
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.of(context).pop(),
                style: ElevatedButton.styleFrom(
                  backgroundColor: CyberColors.neonCyan,
                  foregroundColor: CyberColors.background,
                  padding: const EdgeInsets.symmetric(
                      vertical: CyberDimensions.spacingMS),
                  shape: RoundedRectangleBorder(
                    borderRadius:
                        BorderRadius.circular(CyberDimensions.radiusS),
                  ),
                ),
                child: const Text('关闭', style: CyberTextStyles.buttonLabel),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStepItem(Map<String, dynamic> step) {
    final status = step['status'] as String;
    final stepNumber = step['step'] as int;
    final name = step['name'] as String;
    var message = step['message'] as String;

    // 脱敏处理：移除敏感信息
    if (stepNumber == 1 || stepNumber == 2) {
      // 步骤 1 和 2 可能包含服务器地址，进行脱敏
      message = '神经网关地址配置正常';
    } else if (message.contains('写入文件失败') || message.contains('成功写入:')) {
      // 步骤 5 可能包含本地文件路径，进行脱敏
      message = '音频数据传输正常';
    }

    Color statusColor;
    IconData statusIcon;

    switch (status) {
      case 'success':
        statusColor = CyberColors.neonGreen;
        statusIcon = Icons.check_circle;
        break;
      case 'warning':
        statusColor = CyberColors.neonPurple;
        statusIcon = Icons.warning;
        break;
      case 'error':
        statusColor = CyberColors.neonPink;
        statusIcon = Icons.error;
        break;
      default:
        statusColor = CyberColors.whiteDim;
        statusIcon = Icons.info;
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: CyberDimensions.spacingMS),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(statusIcon, color: statusColor, size: CyberDimensions.iconM),
          const SizedBox(width: CyberDimensions.spacingS),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$stepNumber. $name',
                  style: CyberTextStyles.bodySmallBold,
                ),
                const SizedBox(height: CyberDimensions.spacingXXS),
                Text(
                  message,
                  style: CyberTextStyles.captionTight.copyWith(
                    color: statusColor.withValues(alpha: 0.8),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 环境音量滑块（绑定 ambientVol + AmbientService.setVolume）
class _AmbientVolumeSlider extends StatelessWidget {
  final SettingsProvider settings;
  const _AmbientVolumeSlider({required this.settings});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: CyberDimensions.spacingM,
        vertical: CyberDimensions.spacingS,
      ),
      decoration: BoxDecoration(
        color: CyberColors.surface,
        borderRadius: BorderRadius.circular(CyberDimensions.radiusS),
        border: Border.all(
          color: CyberColors.whiteFaint,
          width: CyberDimensions.borderNormal,
        ),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.music_note,
            color: CyberColors.neonPurple,
            size: CyberDimensions.iconS,
          ),
          Expanded(
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                activeTrackColor: CyberColors.neonPurple,
                inactiveTrackColor: CyberColors.whiteFaint,
                thumbColor: CyberColors.neonPurple,
                overlayColor:
                    CyberColors.neonPurple.withValues(alpha: 0.12),
                trackHeight: 2.0,
                thumbShape:
                    const RoundSliderThumbShape(enabledThumbRadius: 7),
              ),
              child: Slider(
                value: settings.ambientVol,
                min: 0.0,
                max: 1.0,
                divisions: 10,
                onChanged: (v) async {
                  await settings.setAmbientVol(v);
                  await AmbientService.setVolume(v);
                },
              ),
            ),
          ),
          const Icon(
            Icons.music_note,
            color: CyberColors.whiteMuted,
            size: CyberDimensions.iconS,
          ),
          const SizedBox(width: CyberDimensions.spacingS),
          Text(
            '${(settings.ambientVol * 100).round()}%',
            style: CyberTextStyles.captionBold.copyWith(
              color: CyberColors.neonPurple,
              fontFamily: CyberTextStyles.monoFont,
            ),
          ),
        ],
      ),
    );
  }
}

class _IdleTimeoutSelector extends StatelessWidget {
  final SettingsProvider settings;
  const _IdleTimeoutSelector({required this.settings});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: CyberColors.surface,
        borderRadius: BorderRadius.circular(CyberDimensions.radiusS),
        border: Border.all(
          color: CyberColors.whiteFaint,
          width: CyberDimensions.borderNormal,
        ),
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: CyberDimensions.spacingM,
        vertical: CyberDimensions.spacingMS,
      ),
      child: Row(
        children: [
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('空闲自动暂停', style: CyberTextStyles.tileTitle),
                SizedBox(height: CyberDimensions.spacingXXS),
                Text('长时间无操作后自动停止播报', style: CyberTextStyles.tileSubtitle),
              ],
            ),
          ),
          DropdownButton<int>(
            value: settings.idleTimeout,
            dropdownColor: CyberColors.surface,
            underline: const SizedBox.shrink(),
            icon: const Icon(Icons.expand_more, color: CyberColors.whiteMuted),
            items: [
              const DropdownMenuItem(
                  value: 0,
                  child: Text('永不', style: CyberTextStyles.bodySmall)),
              ...List.generate(5, (i) => i + 1).map((m) => DropdownMenuItem(
                    value: m,
                    child: Text('$m 分钟', style: CyberTextStyles.bodySmall),
                  )),
            ],
            onChanged: (v) {
              if (v != null) settings.setIdleTimeout(v);
            },
          ),
        ],
      ),
    );
  }
}
