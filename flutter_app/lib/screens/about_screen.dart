import 'package:flutter/material.dart';

import '../services/platform_info.dart';
import 'logs_screen.dart';
import 'music_screen.dart';

/// About / credits tab. Three things the user explicitly asked to be
/// credited here: the VICE emulator project itself (this whole app is a
/// multiplatform shell around VICE's C64 core), the SID composers whose
/// tunes ship in the Music tab, and a personal dedication.
///
/// Also embeds the [LogsView] below the credits, so logs live under About
/// rather than as a separate sidebar entry. The logs answer "what
/// actually happened" -- the most useful artifact a user can hand back
/// to a developer -- and a single canonical place keeps them in the
/// user's eye rather than in a tab that nobody visits.
class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final composers = {for (final (_, artist, _) in MusicScreen.playlist) artist}.toList()
      ..sort();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text('About',
            style:
                TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        const Text('Retro-C64', style: TextStyle(color: Colors.white70)),
        const SizedBox(height: 20),
        _Card(
          title: 'What this is',
          body: 'A single Commodore 64 workbench that runs the same way on '
              'Linux, Android and iOS: browse your disks, tapes, cartridges and '
              'PRG files, launch them, and play SID music -- all driven by one '
              'shared native core rather than a separate app per platform.\n\n'
              'Running on: ${platformName()}',
        ),
        _Card(
          title: 'VICE',
          body:
              'The real Commodore 64 hardware emulation -- the 6510 CPU, VIC-II '
              'video, SID sound, and the 1541 and friends disk drives -- all '
              'comes from the VICE project. This app is a workbench around that '
              'core, not a re-implementation of it. Huge thanks to the VICE team '
              'for decades of open, meticulously accurate emulation.\n\n'
              'https://vice-emu.sourceforge.io',
        ),
        const _Card(
          title: 'reSID',
          body: 'SID playback uses reSID, Dag Lem\'s cycle-accurate emulation of '
              'the MOS 6581/8580 sound chip -- the reason these tunes sound like '
              'the real hardware and not an approximation of it.',
        ),
        const _Card(
          title: 'HVSC',
          body: 'The bundled SID tunes come from the High Voltage SID Collection, '
              'the archive that has preserved C64 music for decades.\n\n'
              'https://hvsc.c64.org',
        ),
        _Card(
          title: 'SID Composers',
          body: 'The bundled SID playlist in the Music tab plays real music by:\n'
              '${composers.map((c) => '  •  $c').join('\n')}\n\n'
              'All credit for these tunes belongs to the original composers -- '
              'this app just plays them back through VICE\'s SID emulation.',
        ),
        const _Card(
          title: 'Licences and source',
          body: 'This app is built on free software, and the licences require '
              'that it says so and tells you where the source is.\n\n'
              'VICE -- GNU General Public License v2 or later.\n'
              'reSID -- GNU General Public License v2 or later.\n'
              'Open ROMs (the built-in BASIC, KERNAL and character set from '
              'the MEGA65 project) -- GNU LESSER General Public License v3 '
              'or later, copyright Paul Gardner-Stephen and Roman '
              'Standzikowski. Both licence texts ship with the app.\n\n'
              'The complete source for this app, and for the native core it '
              'is built from, is at:\n'
              'https://github.com/CrownParkComputing/Retro-C64\n'
              'https://vice-emu.sourceforge.io\n'
              'https://github.com/MEGA65/open-roms\n\n'
              'No Commodore ROM is included. Those are still under copyright '
              'and are yours to supply.',
        ),
        const _Card(
          title: 'Dedication',
          body: 'Thanks to my wife Jules, who is my inspiration.',
          accent: true,
        ),
        const SizedBox(height: 24),
        const Divider(color: Colors.white24, height: 1),
        const SizedBox(height: 12),
        const LogsView(),
      ],
    );
  }
}

class _Card extends StatelessWidget {
  final String title;
  final String body;
  final bool accent;

  const _Card({required this.title, required this.body, this.accent = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF191D22),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: accent ? const Color(0xFF3DDC97) : const Color(0xFF353B44)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: TextStyle(
                  color: accent ? const Color(0xFF3DDC97) : Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text(body, style: const TextStyle(color: Colors.white70, height: 1.4)),
        ],
      ),
    );
  }
}
