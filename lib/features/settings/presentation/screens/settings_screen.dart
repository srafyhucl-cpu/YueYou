import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:yueyou/core/theme/cyber_colors.dart';
import 'package:yueyou/core/theme/cyber_dimensions.dart';
import 'package:yueyou/features/audio/services/tts_engine_service.dart';
import 'package:yueyou/features/settings/providers/settings_provider.dart';

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
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          height: 56,
          color: CyberColors.panelBackground.withOpacity(0.8),
          child: Row(
            children: [
              const SizedBox(width: 16),
              const Text(
                '系统设置',
                style: TextStyle(
                  color: CyberColors.neonGreen,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 2,
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
      padding: const EdgeInsets.all(16),
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
        const SizedBox(height: 20),
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
        const SizedBox(height: 12),
        const _LabelRow(label: '朗读音量'),
        _VolumeSlider(settings: settings),
        const SizedBox(height: 12),
        const _LabelRow(label: '播报倍速'),
        _SpeedSelector(settings: settings),
        const SizedBox(height: 12),
        const _LabelRow(label: '发声人'),
        _VoiceSelector(settings: settings),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Text(
            '💡 若音色无感情，请前往手机系统设置 -> 文本转语音 (TTS) 中切换系统高音质发音人',
            style: TextStyle(
              color: CyberColors.neonPurple,
              fontSize: 11,
              height: 1.5,
            ),
          ),
        ),
        const SizedBox(height: 12),
        const _TtsTestButton(),
        const SizedBox(height: 12),
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
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        title,
        style: const TextStyle(
          color: CyberColors.neonGreen,
          fontSize: 12,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.5,
        ),
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
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(label,
          style: const TextStyle(color: CyberColors.whiteDim, fontSize: 14)),
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
        title: Text(label,
            style: const TextStyle(color: CyberColors.whiteHigh, fontSize: 14)),
        subtitle: Text(subtitle,
            style:
                const TextStyle(color: CyberColors.whiteMuted, fontSize: 12)),
        value: value,
        onChanged: onChanged,
        activeColor: CyberColors.neonGreen,
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
      spacing: 8,
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
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              color: selected
                  ? CyberColors.neonPink.withOpacity(0.18)
                  : CyberColors.surface,
              borderRadius: BorderRadius.circular(CyberDimensions.radiusL),
              border: Border.all(
                color:
                    selected ? CyberColors.neonPink : CyberColors.whiteSubtle,
                width: selected ? 1.4 : 0.8,
              ),
            ),
            child: Text(
              '${s.toStringAsFixed(1)}x',
              style: TextStyle(
                color: selected ? CyberColors.neonPink : CyberColors.whiteDim,
                fontSize: 13,
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
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
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
        hint: Text(settings.voice,
            style: const TextStyle(color: CyberColors.whiteDim, fontSize: 13)),
        isExpanded: true,
        dropdownColor: CyberColors.surface,
        underline: const SizedBox.shrink(),
        icon: const Icon(Icons.expand_more, color: CyberColors.whiteMuted),
        items: _voices.entries.map((e) {
          return DropdownMenuItem(
            value: e.key,
            child: Text(e.value,
                style:
                    const TextStyle(color: CyberColors.whiteDim, fontSize: 13)),
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
class _TtsTestButton extends StatelessWidget {
  const _TtsTestButton();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: CyberColors.surface,
        borderRadius: BorderRadius.circular(CyberDimensions.radiusS),
        border: Border.all(
          color: CyberColors.neonCyan.withOpacity(0.3),
          width: CyberDimensions.borderNormal,
        ),
      ),
      child: Material(
        color: CyberColors.transparent,
        child: InkWell(
          onTap: () => _testTtsConnection(context),
          borderRadius: BorderRadius.circular(CyberDimensions.radiusS),
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Icon(
                  Icons.wifi_tethering,
                  color: CyberColors.neonCyan,
                  size: 20,
                ),
                SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '测试 TTS 连接',
                        style: TextStyle(
                          color: CyberColors.whiteHigh,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        '诊断 TTS 服务器连接问题',
                        style: TextStyle(
                          color: CyberColors.whiteMuted,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.arrow_forward_ios,
                  color: CyberColors.whiteMuted,
                  size: 16,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _testTtsConnection(BuildContext context) async {
    final tts = context.read<TtsEngineService>();

    // 显示加载对话框
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: CircularProgressIndicator(color: CyberColors.neonCyan),
      ),
    );

    try {
      // 执行测试
      final result = await tts.testConnection();

      // 关闭加载对话框
      if (context.mounted) Navigator.of(context).pop();

      // 显示测试结果
      if (context.mounted) {
        showDialog(
          context: context,
          builder: (context) => _TtsTestResultDialog(result: result),
        );
      }
    } catch (e) {
      // 关闭加载对话框
      if (context.mounted) Navigator.of(context).pop();

      // 显示错误
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('测试失败: $e'),
            backgroundColor: CyberColors.neonPink,
          ),
        );
      }
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
        padding: const EdgeInsets.all(20),
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
                  size: 28,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    success ? 'TTS 连接成功' : 'TTS 连接失败',
                    style: TextStyle(
                      color: success
                          ? CyberColors.neonGreen
                          : CyberColors.neonPink,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            // 服务器地址
            Text(
              '服务器: ${result['serverUrl']}',
              style: const TextStyle(
                color: CyberColors.whiteDim,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 16),
            // 测试步骤
            ...steps.map((step) => _buildStepItem(step)),
            const SizedBox(height: 16),
            // 总结信息
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: success
                    ? CyberColors.neonGreen.withOpacity(0.1)
                    : CyberColors.neonPink.withOpacity(0.1),
                borderRadius: BorderRadius.circular(CyberDimensions.radiusS),
                border: Border.all(
                  color: success ? CyberColors.neonGreen : CyberColors.neonPink,
                  width: 1,
                ),
              ),
              child: Text(
                result['message'] as String,
                style: TextStyle(
                  color: success ? CyberColors.neonGreen : CyberColors.neonPink,
                  fontSize: 13,
                  height: 1.4,
                ),
              ),
            ),
            const SizedBox(height: 16),
            // 关闭按钮
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.of(context).pop(),
                style: ElevatedButton.styleFrom(
                  backgroundColor: CyberColors.neonCyan,
                  foregroundColor: CyberColors.background,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius:
                        BorderRadius.circular(CyberDimensions.radiusS),
                  ),
                ),
                child: const Text(
                  '关闭',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
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
    final message = step['message'] as String;

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
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(statusIcon, color: statusColor, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$stepNumber. $name',
                  style: const TextStyle(
                    color: CyberColors.whiteHigh,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  message,
                  style: TextStyle(
                    color: statusColor.withOpacity(0.8),
                    fontSize: 12,
                    height: 1.3,
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

/// 朗读音量滑块（对应 ambientVol，0.0 ~ 1.0）
class _VolumeSlider extends StatelessWidget {
  final SettingsProvider settings;
  const _VolumeSlider({required this.settings});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
          const Icon(Icons.volume_down,
              color: CyberColors.whiteMuted, size: 18),
          Expanded(
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                activeTrackColor: CyberColors.neonCyan,
                inactiveTrackColor: CyberColors.whiteFaint,
                thumbColor: CyberColors.neonCyan,
                overlayColor: CyberColors.neonCyan.withOpacity(0.12),
                trackHeight: 2.0,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
              ),
              child: Slider(
                value: settings.ambientVol,
                min: 0.0,
                max: 1.0,
                divisions: 10,
                onChanged: (v) async {
                  await settings.setAmbientVol(v);
                },
              ),
            ),
          ),
          const Icon(Icons.volume_up, color: CyberColors.whiteMuted, size: 18),
          const SizedBox(width: 8),
          Text(
            '${(settings.ambientVol * 100).round()}%',
            style: const TextStyle(
              color: CyberColors.neonCyan,
              fontSize: 12,
              fontFamily: 'JetBrains Mono',
              fontWeight: FontWeight.bold,
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
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('空闲自动暂停',
                    style:
                        TextStyle(color: CyberColors.whiteHigh, fontSize: 14)),
                SizedBox(height: 2),
                Text('长时间无操作后自动停止播报',
                    style:
                        TextStyle(color: CyberColors.whiteMuted, fontSize: 12)),
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
                  child: Text('永不',
                      style: TextStyle(
                          color: CyberColors.whiteDim, fontSize: 13))),
              ...List.generate(5, (i) => i + 1).map((m) => DropdownMenuItem(
                    value: m,
                    child: Text('$m 分钟',
                        style: const TextStyle(
                            color: CyberColors.whiteDim, fontSize: 13)),
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
