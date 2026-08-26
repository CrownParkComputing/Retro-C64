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

import 'package:package_info_plus/package_info_plus.dart';

import 'package:retro_c64/data/category.dart';
import 'package:retro_c64/ffi/vice_native_paths.dart';
import 'package:retro_c64/services/app_prefs.dart';
import 'package:retro_c64/services/demo_roms_service.dart';
import 'package:retro_c64/services/service_locator.dart';
import 'package:retro_c64/theme/vice_theme.dart';
import 'package:retro_c64/view_models/workbench_view_model.dart';

class ComplianceScreen extends StatefulWidget {
  /// Reopens the setup wizard. Supplied by the workbench, which owns that
  /// flag -- this screen does not navigate on its own.
  final VoidCallback? onRerunSetup;

  const ComplianceScreen({super.key, this.onRerunSetup});

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
    // Everything here is reporting, so a lookup that fails should cost a
    // line of the report rather than the page. This is the screen a store
    // reviewer is sent to; it has to render whatever else is wrong.
    final demoMode = await getIt<AppPrefs>().getDemoRomMode();
    var path = '';
    var files = const <String>[];
    var userRoms = false;
    var legacy = false;
    try {
      path = (await getIt<DemoRomsService>().demoRomDir()).path;
      files = await getIt<DemoRomsService>().demoFiles();
    } catch (_) {
      // Leaves the path blank and the list empty, which the wording below
      // already covers.
    }
    try {
      userRoms = await ViceNativePaths.romsInstalled();
      // Only true for installs that ran the older build, which put the free
      // ROMs on top of the user's. Offered so those copies can be recovered.
      legacy = await getIt<DemoRomsService>().hasUserRomBackup(
          Directory(await ViceNativePaths.romDir()));
    } catch (_) {
      // Same again: report what is known rather than nothing.
    }
    if (!mounted) return;
    setState(() {
      _demoPath = path;
      _demoFiles = files;
      _userRomsInstalled = userRoms;
      _demoMode = demoMode;
      _legacyBackup = legacy;
    });
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
      // Writing the files out is part of turning it on, not a separate
      // button to remember: a mode you have to prepare by hand is one that
      // can be half on.
      if (next) await getIt<DemoRomsService>().prepareDemoEnvironment();
      await getIt<AppPrefs>().setDemoRomMode(next);
      if (mounted) await context.read<WorkbenchViewModel>().refreshDemoMode();
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
              ? 'The free ROMs and the demo program have been written out. '
                  'Close the app completely and open it again: it will then '
                  'be running on them, with none of your own ROMs involved, '
                  'and Games and Music will be hidden because your own '
                  'folders are not in use.'
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

  /// Takes them to the library rather than starting anything.
  ///
  /// The demo is opened the way any other file is opened. An earlier version
  /// started it from here, which both failed and taught the user nothing
  /// about how to open their own files.
  void _goToGames() =>
      context.read<WorkbenchViewModel>().setCategory(WorkbenchCategory.games);

  Future<void> _restoreLegacy() async {
    final n = await getIt<DemoRomsService>().restoreUserRoms(
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
        FutureBuilder<PackageInfo>(
          future: PackageInfo.fromPlatform(),
          builder: (context, snap) {
            final info = snap.data;
            if (info == null) return const SizedBox.shrink();
            return Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'Version ${info.version} (build ${info.buildNumber})',
                style: const TextStyle(
                    color: Colors.white38,
                    fontSize: 11,
                    fontFamily: 'monospace'),
              ),
            );
          },
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
        Card(
          color: const Color(0xFF10151A),
          shape: RoundedRectangleBorder(
            side: const BorderSide(color: ViceColors.panelStroke),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Column(
            children: [
              SwitchListTile(
                value: _demoMode,
                onChanged: _busy ? null : (_) => _toggleDemoMode(),
                title: const Text('Free-ROM mode',
                    style: TextStyle(color: Colors.white)),
                subtitle: Text(
                  _demoMode
                      ? 'On. The app is running on the free ROMs.'
                      : 'Off. The app is running on your own ROMs.',
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
                activeThumbColor: ViceColors.accentTeal,
              ),
              if (_demoMode)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'To run the demo:',
                        style: TextStyle(
                            color: Colors.white, fontSize: 13,
                            fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '  1.  Open Games in the sidebar.\n'
                        '  2.  Tap "${DemoRomsService.demoFileName}".\n\n'
                        'In this mode Games lists the demo folder above, not '
                        'your own library: your games were written against '
                        'Commodore ROMs and this machine is not booted on '
                        'them, so offering them would be offering titles that '
                        'cannot run.\n\n'
                        'It loads the same way a tape, a disk or any other '
                        'program does -- nothing here is typed in or started '
                        'for you, so what you see the demo do is what the '
                        'emulator does with any file you give it.',
                        style: const TextStyle(
                            color: Colors.white70, fontSize: 13, height: 1.4),
                      ),
                      const SizedBox(height: 10),
                      OutlinedButton.icon(
                        onPressed: _busy ? null : _goToGames,
                        icon: const Icon(Icons.videogame_asset, size: 18),
                        label: const Text('Open Games'),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),

        const _Head('2. What changes in free-ROM mode'),
        const _Body(
          'It is a different machine, not a setting. For as long as it is on:'
          '\n\n'
          '  •  The emulator boots from the demo\'s own ROM folder. Your ROM '
          'folder is not read, written or looked at.\n'
          '  •  Games and Music are not offered. Your library and your tunes '
          'live in your own folders, which this mode does not use, so those '
          'screens would be doors onto an empty room.\n'
          '  •  The only things on offer are the demo, this page and About.'
          '\n\n'
          'Turning it off puts everything back exactly as it was. Nothing of '
          'yours is moved, copied or changed either way.',
        ),

        const _Head('3. The demo files, and where they are'),
        _Body(
          _demoFiles.isEmpty
              ? 'Not written out yet. Turn free-ROM mode on and every file '
                  'the demo uses appears here, in a folder you can open, '
                  'read and copy from.'
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

        const _Head('4. What the free ROMs are'),
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

        const _Head('5. Commodore\'s ROMs are never shipped'),
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

        const _Head('6. Games are never shipped'),
        const _Body(
          'The app contains no games. Everything playable comes from the '
          'user. It is a hardware emulator for a 1982 home computer, '
          'permitted under App Review Guideline 4.7.',
        ),

        const _Head('7. Free software, and where its source is'),
        const _Body(
          'The emulation core is VICE, with reSID for sound, both under the '
          'GNU General Public License v2 or later. The licences require the '
          'app to say so and to point at the source, which it does here and '
          'in About > Licences and source:\n\n'
          '  github.com/CrownParkComputing/Retro-C64\n'
          '  vice-emu.sourceforge.io\n'
          '  github.com/MEGA65/open-roms',
        ),

        const _Head('8. Privacy'),
        const _Body(
          'No accounts, no sign-in, no analytics, no tracking, no data '
          'collected and none transmitted. The app makes no network request '
          'of its own. The app makes no network request at all: cover artwork comes from a local zip pack the user supplies in Paths.',
        ),

        if (widget.onRerunSetup != null) ...[
          const _Head('Start over'),
          const _Body(
            'Reopens the first-run screen, where the same choice is offered '
            'again. Worth knowing because compliance mode hides Paths, which '
            'is the other way back to it -- without this there would be no '
            'way out of the mode except turning the switch off above.',
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: _busy ? null : widget.onRerunSetup,
              icon: const Icon(Icons.replay, size: 18),
              label: const Text('Back to the setup screen'),
            ),
          ),
        ],

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
