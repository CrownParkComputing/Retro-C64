import 'package:flutter/material.dart';

import '../services/video_settings.dart';
import '../theme/vice_theme.dart';

/// Video Settings tab.
///
/// These used to live as rows in the in-game Quick Settings panel, where
/// they were also broken: the panel flipped local booleans on the emulator
/// screen and relabelled its own rows, but the render path reads
/// [VideoSettings.instance], so nothing on screen ever changed. They are
/// set-once display preferences rather than mid-game actions, so they belong
/// here -- and here they are wired to the object FramebufferView actually
/// consumes, which is what makes them work at all.
class VideoSettingsScreen extends StatelessWidget {
  const VideoSettingsScreen({super.key});

  Widget _card({required Widget child}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFF191D22),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFF353B44)),
        ),
        child: child,
      ),
    );
  }

  Widget _switchRow({
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: const TextStyle(color: Colors.white, fontSize: 14)),
              const SizedBox(height: 4),
              Text(subtitle,
                  style: const TextStyle(color: Colors.white70, fontSize: 12)),
            ],
          ),
        ),
        Switch(
          value: value,
          activeThumbColor: ViceColors.accentTeal,
          onChanged: onChanged,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = VideoSettings.instance;
    return AnimatedBuilder(
      animation: settings,
      builder: (context, _) {
        return ListView(
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text('Video Settings',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold)),
            ),
            _card(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Screen size',
                      style: TextStyle(color: Colors.white, fontSize: 14)),
                  const SizedBox(height: 4),
                  const Text(
                    'How the C64 picture is fitted to the screen. Integer '
                    'scale keeps every C64 pixel the same size, so scrolling '
                    'never shimmers.',
                    style: TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final mode in AspectMode.values)
                        ChoiceChip(
                          label: Text(mode.label),
                          selected: settings.aspect == mode,
                          onSelected: (_) => settings.setAspect(mode),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            _card(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _switchRow(
                    title: 'CRT effect',
                    subtitle: 'Scanlines and a soft vignette over the picture.',
                    value: settings.crt,
                    onChanged: settings.setCrt,
                  ),
                  if (settings.crt) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Text('Scanline strength',
                            style:
                                TextStyle(color: Colors.white70, fontSize: 12)),
                        Expanded(
                          child: Slider(
                            value: settings.scanlineIntensity,
                            activeColor: ViceColors.accentTeal,
                            onChanged: settings.setScanlineIntensity,
                          ),
                        ),
                        Text(
                          '${(settings.scanlineIntensity * 100).round()}%',
                          style: const TextStyle(
                              color: ViceColors.accentTeal, fontSize: 12),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            _card(
              child: _switchRow(
                title: 'Bezel',
                subtitle:
                    'Draws a monitor surround around the picture instead of '
                    'running it to the screen edge.',
                value: settings.bezel,
                onChanged: settings.setBezel,
              ),
            ),
            _card(
              child: _switchRow(
                title: 'Smooth scaling',
                subtitle:
                    'Filters the picture when it is scaled. Off gives hard, '
                    'authentic pixel edges.',
                value: settings.smooth,
                onChanged: settings.setSmooth,
              ),
            ),
            _card(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Rotation',
                      style: TextStyle(color: Colors.white, fontSize: 14)),
                  const SizedBox(height: 4),
                  const Text(
                    'For vertically-oriented games on a handheld held sideways.',
                    style: TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                  const SizedBox(height: 10),
                  SegmentedButton<int>(
                    segments: const [
                      ButtonSegment(value: 0, label: Text('0°')),
                      ButtonSegment(value: 1, label: Text('90°')),
                      ButtonSegment(value: 2, label: Text('180°')),
                      ButtonSegment(value: 3, label: Text('270°')),
                    ],
                    selected: {settings.rotationQuarterTurns},
                    showSelectedIcon: false,
                    onSelectionChanged: (s) =>
                        settings.setRotationQuarterTurns(s.first),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}
