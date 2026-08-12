import 'package:flutter/material.dart';

import '../services/app_prefs.dart';
import '../services/music_library.dart';
import '../services/vsid_service.dart';
import '../theme/vice_theme.dart';

/// Audio settings. Currently one thing that matters: whether the workbench
/// plays music.
///
/// Reads and writes AppPrefs directly rather than being plumbed down from the
/// workbench. The two places that care -- the workbench, which starts the
/// tune, and this switch -- are not in a parent/child relationship, so a
/// callback chain would only add wiring with no extra reader.
class AudioSettingsScreen extends StatefulWidget {
  const AudioSettingsScreen({super.key});

  @override
  State<AudioSettingsScreen> createState() => _AudioSettingsScreenState();
}

class _AudioSettingsScreenState extends State<AudioSettingsScreen> {
  bool? _music;

  @override
  void initState() {
    super.initState();
    AppPrefs.getWorkbenchMusic().then((v) {
      if (mounted) setState(() => _music = v);
    });
  }

  /// Applies the change immediately as well as saving it.
  ///
  /// A music toggle that only takes effect next launch is a broken toggle:
  /// the whole point is that you flip it because you want silence *now*.
  Future<void> _set(bool on) async {
    setState(() => _music = on);
    await AppPrefs.setWorkbenchMusic(on);
    final vsid = VsidService.instance;
    if (!on) {
      vsid.pause();
      return;
    }
    if (vsid.currentPath != null) {
      if (vsid.isPaused) vsid.togglePause();
      return;
    }
    final dirs = await MusicLibrary.searchDirs();
    final pick = MusicLibrary.firstAvailable(dirs);
    if (pick == null) return;
    if (await vsid.ensureLoaded()) vsid.play(pick.$2);
  }

  Widget _card({required Widget child}) => Padding(
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

  @override
  Widget build(BuildContext context) {
    final music = _music;
    return ListView(
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text('Audio',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold)),
        ),
        _card(
          child: Row(
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Music in the workbench',
                        style: TextStyle(color: Colors.white, fontSize: 14)),
                    SizedBox(height: 4),
                    Text(
                      'Plays a SID tune while you browse, and drives the '
                      'equaliser on the demo backdrop. Music always stops '
                      'when a game launches, whatever this is set to. Pick '
                      'the tune on the Music tab.',
                      style: TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                  ],
                ),
              ),
              Switch(
                value: music ?? true,
                activeThumbColor: ViceColors.accentTeal,
                onChanged: music == null ? null : _set,
              ),
            ],
          ),
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 10, 16, 0),
          child: Text(
            'Emulator audio (sample rate, SID engine) is fixed for now.',
            style: TextStyle(color: Colors.white38, fontSize: 11),
          ),
        ),
      ],
    );
  }
}
