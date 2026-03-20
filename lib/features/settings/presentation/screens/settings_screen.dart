import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:yueyou/core/theme/cyber_colors.dart';
import 'package:yueyou/features/audio/services/tts_engine_service.dart';
import 'package:yueyou/features/game_2048/providers/game_provider.dart';
import 'package:yueyou/features/settings/providers/settings_provider.dart';

/// 设置界面
/// 完整复刻旧版 modal-settings：声音/TTS/发声人/空闲超时
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0E18),
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
          color: const Color(0xCC0D0E18),
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
                icon: const Icon(Icons.close, color: Colors.white70),
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
        _SectionTitle(title: '游戏音效'),
        _ToggleTile(
          label: '合并音效',
          subtitle: '方块合并时播放提示音',
          value: settings.sound,
          onChanged: (v) {
            settings.setSound(v);
            // 同步到 GameProvider
            context.read<GameProvider>().soundEnabled = v;
          },
        ),
        const SizedBox(height: 20),
        _SectionTitle(title: '语音播报'),
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
        _LabelRow(label: '播报倍速'),
        _SpeedSelector(settings: settings),
        const SizedBox(height: 12),
        _LabelRow(label: '发声人'),
        _VoiceSelector(settings: settings),
        const SizedBox(height: 20),
        _SectionTitle(title: '省电管理'),
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
          style: const TextStyle(color: Colors.white70, fontSize: 14)),
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
        color: const Color(0xFF1A1B28),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white12),
      ),
      child: SwitchListTile(
        title: Text(label,
            style: const TextStyle(color: Colors.white, fontSize: 14)),
        subtitle: Text(subtitle,
            style: const TextStyle(color: Colors.white38, fontSize: 12)),
        value: value,
        onChanged: onChanged,
        activeColor: CyberColors.neonGreen,
        inactiveThumbColor: Colors.white38,
        inactiveTrackColor: Colors.white12,
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
                  : const Color(0xFF1A1B28),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: selected ? CyberColors.neonPink : Colors.white24,
                width: selected ? 1.4 : 0.8,
              ),
            ),
            child: Text(
              '${s.toStringAsFixed(1)}x',
              style: TextStyle(
                color: selected ? CyberColors.neonPink : Colors.white54,
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
        color: const Color(0xFF1A1B28),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white12),
      ),
      child: DropdownButton<String>(
        value: _voices.containsKey(settings.voice) ? settings.voice : null,
        hint: Text(settings.voice,
            style: const TextStyle(color: Colors.white54, fontSize: 13)),
        isExpanded: true,
        dropdownColor: const Color(0xFF1A1B28),
        underline: const SizedBox.shrink(),
        icon: const Icon(Icons.expand_more, color: Colors.white38),
        items: _voices.entries.map((e) {
          return DropdownMenuItem(
            value: e.key,
            child: Text(e.value,
                style: const TextStyle(color: Colors.white70, fontSize: 13)),
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
class _IdleTimeoutSelector extends StatelessWidget {
  final SettingsProvider settings;
  const _IdleTimeoutSelector({required this.settings});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1A1B28),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white12),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('空闲自动暂停',
                    style: TextStyle(color: Colors.white, fontSize: 14)),
                SizedBox(height: 2),
                Text('长时间无操作后自动停止播报',
                    style: TextStyle(color: Colors.white38, fontSize: 12)),
              ],
            ),
          ),
          DropdownButton<int>(
            value: settings.idleTimeout,
            dropdownColor: const Color(0xFF1A1B28),
            underline: const SizedBox.shrink(),
            icon: const Icon(Icons.expand_more, color: Colors.white38),
            items: [
              const DropdownMenuItem(
                  value: 0,
                  child: Text('永不',
                      style: TextStyle(color: Colors.white70, fontSize: 13))),
              ...List.generate(5, (i) => i + 1).map((m) => DropdownMenuItem(
                    value: m,
                    child: Text('$m 分钟',
                        style: const TextStyle(
                            color: Colors.white70, fontSize: 13)),
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
