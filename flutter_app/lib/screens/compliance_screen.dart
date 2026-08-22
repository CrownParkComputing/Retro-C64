// The App Store / Play Store compliance page.
//
// One place that answers, on the device and without a network connection,
// every question a store review team asks about an emulator: what does it
// ship, what does it not ship, under what licences, what can it do with
// nothing supplied by the user, and where are the files that prove it.
//
// It exists because those answers were previously spread between a first-run
// wizard the reviewer may never see, a text file in the repository they
// certainly will not, and nowhere at all. The review notes point at this
// page by name.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../ffi/vice_native_paths.dart';
import '../services/app_prefs.dart';
import '../services/demo_roms_service.dart';
import '../theme/vice_theme.dart';
import '../view_models/workbench_view_model.dart';

class ComplianceScreen extends StatefulWidget {
  const ComplianceScreen({super.key});

  @override
  State<ComplianceScreen> createState() => _ComplianceScreenState();
}

class _ComplianceScreenState extends State<ComplianceScreen> {
  String _demoPath = '';
  List<String> _demoFiles = const [];
  bool _busy = false;
  bool _userRomsInstalled = false;
  bool _demoMode = false;
  bool _legacyBackup = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final dir = await DemoRomsService.demoRomDir();
    final files = await DemoRomsService.demoFiles();
    final userRoms = await ViceNativePaths.romsInstalled();
    final demoMode = await AppPrefs.getDemoRomMode();
    // Only true for installs that ran the older build, which put the free
    // ROMs on top of the user's. Offered so those copies can be recovered.
    final legacy = await DemoRomsService.hasUserRomBackup(
        Directory(await ViceNativePaths.romDir()));
    if (!mounted) return;
    setState(() {
      _demoPath = dir.path;
      _demoFiles = files;
      _userRomsInstalled = userRoms;
      _demoMode = demoMode;
      _legacyBackup = legacy;
    });
  }

  Future<void> _prepare() async {
    setState(() => _busy = true);
    try {
      await DemoRomsService.prepareDemoEnvironment();
    } finally {
      if (mounted) setState(() => _busy = false);
      await _load();
    }
  }

  /// Turns the mode on or off and tells the user what has to happen next.
  ///
  /// The restart is not an inconvenience that could be engineered away: the
  /// emulator loads its ROMs as the machine powers on, and the bridge has no
  /// supported way to tear that down and re-run it in the same process. An
  /// earlier version of this screen pretended otherwise -- it pointed the
  /// core at another ROM directory and started the program, which looked
  /// like it worked and silently kept using the ROMs already loaded.
  Future<void> _toggleDemoMode() async {
    final next = !_demoMode;
    setState(() => _busy = true);
    try {
      if (next) await DemoRomsService.prepareDemoEnvironment();
      await AppPrefs.setDemoRomMode(next);
    } finally {
      if (mounted) setState(() => _busy = false);
      await _load();
    }
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(next ? 'Free-ROM mode is on' : 'Free-ROM mode is off'),
        content: Text(
          next
              ? 'Close the app completely and open it again. It will then be '
                  'running on the free ROMs, with none of your own ROMs '
                  'involved, and "Run the demo program" here will start a '
                  'real C64 on them.'
              : 'Close the app completely and open it again to go back to '
                  'your own ROMs. Nothing of yours was changed while free-ROM '
                  'mode was on.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> _runDemo() async {
    setState(() => _busy = true);
    try {
      await context.read<WorkbenchViewModel>().launchFreeRomDemo(context);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restoreLegacy() async {
    final n = await DemoRomsService.restoreUserRoms(
        Directory(await ViceNativePaths.romDir()));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(n == 0
          ? 'Nothing was stored away.'
          : 'Restored $n ROM file(s) of yours.'),
    ));
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
      children: [
        const Text('App Store / Play Store compliance',
            style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        const Text(
          'Everything a store review needs, on the device. No network '
          'connection is required to check any of it.',
          style: TextStyle(color: Colors.white54, fontSize: 12),
        ),

        const _Head('1. See it working with nothing supplied'),
        _Body(
          'The app ships free, open-source ROMs and a small demo program. '
          'Together they boot a real emulated Commodore 64 and run it, with '
          'no files, no account and no network.\n\n'
          'Free-ROM mode is a SEPARATE WORLD, not a swap. In it the emulator '
          'boots from the demo\'s own ROM directory and never reads, writes '
          'or touches any ROMs of yours. Turning it on or off takes effect '
          'when the app is next started, because the emulator loads its ROMs '
          'once, as the machine powers on, and cannot be handed a different '
          'set while it is running.\n\n'
          'Right now this app is running on: '
          '${_demoMode ? "THE FREE ROMS." : _userRomsInstalled ? "your own ROMs." : "your own ROM directory (no ROM set found in it)."}',
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            if (_demoMode)
              FilledButton.icon(
                onPressed: _busy ? null : _runDemo,
                icon: const Icon(Icons.play_arrow, size: 18),
                label: const Text('Run the demo program'),
              ),
            OutlinedButton.icon(
              onPressed: _busy ? null : _toggleDemoMode,
              icon: Icon(_demoMode ? Icons.undo : Icons.science, size: 18),
              label: Text(_demoMode
                  ? 'Turn free-ROM mode off'
                  : 'Turn free-ROM mode on'),
            ),
            OutlinedButton(
              onPressed: _busy ? null : _prepare,
              child: const Text('Write the files out'),
            ),
          ],
        ),

        const _Head('2. The demo files, and where they are'),
        _Body(
          _demoFiles.isEmpty
              ? 'Not written out yet. Use "Write the files out" above, or run '
                  'the demo once, and every file the demo uses appears here '
                  'where you can open, read and copy it.'
              : 'These are the actual files the demo runs on. They are in a '
                  'folder you can open, not buried inside the app:',
        ),
        _Mono(_demoPath.isEmpty ? '...' : _demoPath),
        if (_demoFiles.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final f in _demoFiles)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 1),
                    child: Text('  •  $f',
                        style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                            fontFamily: 'monospace')),
                  ),
              ],
            ),
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: _demoPath.isEmpty
                ? null
                : () {
                    Clipboard.setData(ClipboardData(text: _demoPath));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Path copied.')),
                    );
                  },
            icon: const Icon(Icons.copy, size: 16),
            label: const Text('Copy the path'),
          ),
        ),

        const _Head('3. What the free ROMs are'),
        const _Body(
          'They are the MEGA65 project\'s Open ROMs: a clean-room BASIC, '
          'KERNAL and character set, written from scratch. They are NOT '
          'Commodore\'s code and contain none of it.\n\n'
          'Licence: GNU Lesser General Public License v3 or later. '
          'Copyright Paul Gardner-Stephen and Roman Standzikowski; some BASIC '
          'routines are MIT-licensed, copyright Microsoft Corporation. Both '
          'licence texts ship with the app and are written into the folder '
          'above, next to the ROMs they cover.\n\n'
          'Source: github.com/MEGA65/open-roms\n\n'
          'They are an unfinished project. They boot, and they run the demo, '
          'but their BASIC is incomplete and most commercial software will '
          'not run on them. That is why the app still offers to import real '
          'ROMs, and why the two are kept apart.',
        ),

        const _Head('4. Commodore\'s ROMs are never shipped'),
        _Body(
          'The C64\'s own BASIC and KERNAL, and the 1541 disk drive ROM, are '
          'still under copyright. The app contains none of them and never '
          'distributes them. Commercial C64 software was written against '
          'those ROMs, so to run your old games you supply them yourself, '
          'exactly as with every other C64 emulator.\n\n'
          'Legitimate ways to obtain them:\n'
          '  •  Dump them from a Commodore 64 you own.\n'
          '  •  Buy a licensed set — C64 Forever (Cloanto) includes them.\n'
          '  •  Copy them from a VICE installation you already have.\n\n'
          'Import them with Paths > Scan for ROMs. A zipped set works as it '
          'is, without unpacking.\n\n'
          'On this device right now: '
          '${_userRomsInstalled ? "a ROM set is installed." : "no ROM set is installed, and the app still runs the demo above."}',
        ),

        const _Head('5. Games are never shipped'),
        const _Body(
          'The app contains no games. Everything playable comes from the '
          'user. It is a hardware emulator for a 1982 home computer, '
          'permitted under App Review Guideline 4.7.',
        ),

        const _Head('6. Free software, and where its source is'),
        const _Body(
          'The emulation core is VICE, with reSID for sound, both under the '
          'GNU General Public License v2 or later. The licences require the '
          'app to say so and to point at the source, which it does here and '
          'in About > Licences and source:\n\n'
          '  github.com/CrownParkComputing/Retro-C64\n'
          '  vice-emu.sourceforge.io\n'
          '  github.com/MEGA65/open-roms',
        ),

        const _Head('7. Privacy'),
        const _Body(
          'No accounts, no sign-in, no analytics, no tracking, no data '
          'collected and none transmitted. The app makes no network request '
          'of its own. The one feature that can is cover artwork, which does '
          'nothing until you enter a URL of your own in Settings.',
        ),

        if (_legacyBackup) ...[
          const _Head('Left over from an earlier version'),
          const _Body(
            'An earlier build installed the free ROMs over the top of yours '
            'and kept a copy. That copy is still here and can be put back.',
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton(
              onPressed: _restoreLegacy,
              child: const Text('Restore my own ROMs'),
            ),
          ),
        ],
      ],
    );
  }
}

class _Head extends StatelessWidget {
  const _Head(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 22, bottom: 6),
        child: Text(text.toUpperCase(),
            style: const TextStyle(
                color: ViceColors.accentTeal,
                fontSize: 12,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.1)),
      );
}

class _Body extends StatelessWidget {
  const _Body(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(text,
            style: const TextStyle(
                color: Colors.white70, fontSize: 13, height: 1.4)),
      );
}

class _Mono extends StatelessWidget {
  const _Mono(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: const Color(0xFF10151A),
          border: Border.all(color: ViceColors.panelStroke),
          borderRadius: BorderRadius.circular(4),
        ),
        child: SelectableText(text,
            style: const TextStyle(
                color: Colors.white, fontSize: 12, fontFamily: 'monospace')),
      );
}
