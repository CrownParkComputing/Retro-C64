// Paths & Setup tab (WorkbenchCategory.paths). Shows what the setup wizard
// currently has on file for this platform's storage strategy, lets the user
// change folders directly with real Browse buttons (rather than only being
// able to re-run the whole wizard), and -- on Android -- exposes the
// shared-storage permission that everything else depends on.
import 'dart:io';

import 'package:flutter/material.dart';

import '../services/app_prefs.dart';
import '../services/demo_roms_service.dart';
import '../services/artwork_service.dart';
import '../services/rom_install_service.dart';
import '../ffi/vice_native_paths.dart';
import '../services/permissions_service.dart';
import '../services/storage_access.dart';
import '../services/startup_import.dart';
import '../theme/vice_theme.dart';
import 'setup_wizard_screen.dart';

class PathsSettingsScreen extends StatefulWidget {
  /// Called after a folder changes or storage access is granted, so the
  /// workbench can rescan its library without the user going anywhere.
  final VoidCallback? onLibraryShouldRescan;

  /// Re-opens the setup wizard. Clears the completed flag first so the
  /// wizard is what the app comes back to on next launch too, rather than
  /// being a one-shot visit that forgets itself.
  final VoidCallback? onRerunSetup;

  const PathsSettingsScreen({
    super.key,
    this.onLibraryShouldRescan,
    this.onRerunSetup,
  });

  @override
  State<PathsSettingsScreen> createState() => _PathsSettingsScreenState();
}

class _PathsSettingsScreenState extends State<PathsSettingsScreen> {
  final _storage = StorageAccess.instance;
  String? _appFolderPath;
  String? _gamesFolderPath;
  int _importedCount = 0;
  bool _loading = true;
  bool _hasStorageAccess = true;
  bool _romsInstalled = false;

  /// Whether the ROMs in place are the bundled free ones rather than the
  /// user's, and whether a set of theirs is waiting underneath to be restored.
  bool _demoRomsActive = false;
  bool _hasUserRomBackup = false;
  bool _demoBusy = false;
  bool _driveRomInstalled = false;
  String? _driveRomFile;
  List<String> _drivesDirFiles = const [];
  String _romDirPath = '';
  int _artworkPacks = 0;

  bool get _isFolderScan => _storage.kind == StorageStrategyKind.folderScan;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final app = await AppPrefs.getAppFolderPath();
    final games = await AppPrefs.getGamesFolderPath();
    final access = await PermissionsService.hasStorageAccess();
    final roms = await ViceNativePaths.romsInstalled();
    final viceDir = Directory(await ViceNativePaths.romDir());
    final demoActive = await DemoRomsService.installed(viceDir);
    final userBackup = await DemoRomsService.hasUserRomBackup(viceDir);
    final driveRom = await ViceNativePaths.driveRomInstalled();
    final driveRomFile = await ViceNativePaths.driveRomFile();
    final drivesFiles = await ViceNativePaths.driveRomsPresent();
    final romPath = await ViceNativePaths.romDir();
    final artPacks = await ArtworkService.installedPackCount();
    int imported = 0;
    if (!_isFolderScan) {
      imported = (await _storage.listImported(kGamesImportSubdir)).length;
    }
    if (!mounted) return;
    setState(() {
      _appFolderPath = app;
      _gamesFolderPath = games;
      _importedCount = imported;
      _hasStorageAccess = access;
      _romsInstalled = roms;
      _demoRomsActive = demoActive;
      _hasUserRomBackup = userBackup;
      _driveRomInstalled = driveRom;
      _driveRomFile = driveRomFile;
      _drivesDirFiles = drivesFiles;
      _romDirPath = romPath;
      _artworkPacks = artPacks;
      _loading = false;
    });
  }

  /// Extracts any artwork packs sitting in the app's folder or Downloads.
  ///
  /// Separate from the ROM scan on purpose: they look for different things in
  /// different places and either can be useful without the other.
  /// Sweeps for game media and imports it, the same scan the wizard runs.
  ///
  /// Separate from the ROM scan: one looks for d64/tap/prg/sid, the other for
  /// the three BIOS .bin files, and needing one says nothing about the other.
  Future<void> _scanGames() async {
    final pending =
        await _storage.listImportable(destinationSubdir: kGamesImportSubdir);
    final imported = pending.isEmpty
        ? const <ImportedFile>[]
        : await _storage.importFiles(pending,
            destinationSubdir: kGamesImportSubdir);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(imported.isEmpty
            ? 'No new game files found.'
            : 'Imported ${imported.length} game file(s).'),
      ),
    );
    await _load();
    widget.onLibraryShouldRescan?.call();
  }

  Future<void> _scanArtwork() async {
    final count = await ArtworkService.scanAndImport();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(count == 0
            ? 'No artwork packs found. Add <game>.zip files and rescan.'
            : 'Installed artwork for $count game(s).'),
      ),
    );
    await _load();
    widget.onLibraryShouldRescan?.call();
  }

  Future<void> _importRoms() async {
    final result = await RomInstallService.scanAndImport();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(result.summary)),
    );
    await _load();
    widget.onLibraryShouldRescan?.call();
  }

  Future<void> _rerunWizard() async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => SetupWizardScreen(
        onComplete: () => Navigator.of(context).pop(),
      ),
    ));
    await _load();
    widget.onLibraryShouldRescan?.call();
  }

  Future<void> _browseGamesFolder() async {
    final picked =
        await _storage.pickFolder(dialogTitle: 'Choose your C64 games folder');
    if (picked == null) return;
    await AppPrefs.setGamesFolderPath(picked.path);
    await _load();
    widget.onLibraryShouldRescan?.call();
  }

  Future<void> _browseAppFolder() async {
    final picked = await _storage.pickFolder(
        dialogTitle: 'Choose the app data folder');
    if (picked == null) return;
    await AppPrefs.setAppFolderPath(picked.path);
    await _load();
  }

  /// Clears the completed flag and hands control back to the wizard. The
  /// flag is cleared rather than just navigating, so a relaunch mid-setup
  /// still lands on the wizard instead of silently reverting.
  Future<void> _rerunSetup() async {
    await AppPrefs.setSetupCompleted(false);
    if (!mounted) return;
    widget.onRerunSetup?.call();
  }

  /// Everything arrives through the app's folder now - drop zips there and
  /// this reruns the startup import over them. The Files picker is gone: it
  /// filed .sid tunes onto the games shelf (sid is a game extension to the
  /// picker) and offered a second road when the folder must be the only one.
  Future<void> _importFiles() async {
    final imported = await StartupImport.run();
    if (!mounted) return;
    final total = imported.roms + imported.tunes + imported.games;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text(total == 0
              ? 'Nothing new. Put zips in this app\'s folder in Files first.'
              : 'Imported ${imported.roms} ROM(s), ${imported.tunes} '
                  'tune(s), ${imported.games} game(s).')),
    );
    await _load();
    widget.onLibraryShouldRescan?.call();
  }

  Future<void> _grantStorage() async {
    await PermissionsService.requestStorageAccess();
    await _load();
    widget.onLibraryShouldRescan?.call();
  }

  /// Puts the machine into demo mode on demand, not just on a first run.
  ///
  /// This is what makes the compliance claim demonstrable at any time: the
  /// app can be shown working on free ROMs whenever somebody asks, without
  /// wiping the app or hunting for a first-launch state. The user's own ROMs
  /// are moved aside, not overwritten, and [_restoreUserRoms] puts them back.
  Future<void> _useDemoRoms() async {
    setState(() => _demoBusy = true);
    try {
      final viceDir = Directory(await ViceNativePaths.romDir());
      await DemoRomsService.install(viceDir);
      await DemoRomsService.installDemoProgram(
          Directory(await libraryScanRoot() ??
              await ViceNativePaths.mediaDirPath()));
      widget.onLibraryShouldRescan?.call();
      if (!mounted) return;
      _toast('Free ROMs installed. "${DemoRomsService.demoTitle}" is in '
          'Games. Restart the emulator for the ROM change to take effect.');
    } catch (e) {
      if (mounted) _toast('Could not switch to the demo ROMs: $e');
    } finally {
      if (mounted) setState(() => _demoBusy = false);
      await _load();
    }
  }

  Future<void> _restoreUserRoms() async {
    setState(() => _demoBusy = true);
    try {
      final n = await DemoRomsService.restoreUserRoms(
          Directory(await ViceNativePaths.romDir()));
      if (!mounted) return;
      _toast(n == 0
          ? 'No ROMs of yours were stored away.'
          : 'Restored $n of your own ROM file(s). Restart the emulator for '
              'the change to take effect.');
    } catch (e) {
      if (mounted) _toast('Could not restore your ROMs: $e');
    } finally {
      if (mounted) setState(() => _demoBusy = false);
      await _load();
    }
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      children: [
        Row(
          children: [
            const Expanded(
              child: Text('Paths & Setup',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold)),
            ),
            if (widget.onRerunSetup != null)
              OutlinedButton.icon(
                onPressed: _rerunSetup,
                icon: const Icon(Icons.replay, size: 16),
                label: const Text('Run setup again'),
              ),
          ],
        ),
        const SizedBox(height: 10),
        if (_loading)
          const Text('Loading...', style: TextStyle(color: Colors.white38))
        else ...[
          // ROMs before everything else: without them the core cannot boot,
          // so a missing set makes every other setting on this screen moot.
          _Row(
            label: 'C64 ROMs',
            value: _romsInstalled
                ? 'Installed -- kernal, basic and chargen found'
                : 'MISSING in $_romDirPath/C64/',
            valueColor:
                _romsInstalled ? ViceColors.accentTeal : Colors.orangeAccent,
            actionLabel: _romsInstalled ? 'Rescan' : 'Scan for ROMs',
            onAction: _importRoms,
          ),
          const _SectionHeader('App Store / Play Store compliance'),
          // Everything a store submission turns on, in one place, so it can
          // be checked or demonstrated on demand rather than reconstructed
          // from memory on the day. See docs/LICENCE_COMPLIANCE.md and
          // store/SIGNOFF.md in the repository.
          _Row(
            label: 'Show it working with no Commodore ROMs',
            value: _demoRomsActive
                ? 'ON -- running the bundled Open ROMs. Pick '
                    '"${DemoRomsService.demoTitle}" in Games to see a real '
                    'C64 boot and run. Most commercial software needs real '
                    'ROMs, so switch back when you are done.'
                : _hasUserRomBackup
                    ? 'Off -- your own ROMs are in use, and a copy of them '
                        'from an earlier demo is stored away.'
                    : 'Off -- installs free ROMs and a demo program so the '
                        'emulator can be shown working with nothing supplied '
                        'by you. This is the path the review notes give '
                        'Apple. Your own ROMs are moved aside, not '
                        'overwritten.',
            valueColor:
                _demoRomsActive ? Colors.orangeAccent : ViceColors.accentTeal,
            actionLabel: _demoBusy
                ? null
                : (_demoRomsActive || _hasUserRomBackup)
                    ? 'Restore my ROMs'
                    : 'Use free ROMs',
            onAction: _demoBusy
                ? null
                : (_demoRomsActive || _hasUserRomBackup)
                    ? _restoreUserRoms
                    : _useDemoRoms,
          ),
          const _Row(
            label: 'Commodore ROMs',
            value: 'Never shipped. The C64 BASIC, KERNAL and the 1541 drive '
                'ROM are still under copyright, so the app carries none of '
                'them and the user supplies their own. Nothing above changes '
                'that -- the free ROMs are an independent reimplementation, '
                'not Commodore code.',
            valueColor: ViceColors.accentTeal,
          ),
          const _Row(
            label: 'Emulator rules',
            value: 'Permitted under App Review Guideline 4.7 (retro game '
                'console emulators). The app ships no games; everything '
                'playable comes from the user.',
            valueColor: ViceColors.accentTeal,
          ),
          const _Row(
            label: 'Free software licences',
            value: 'VICE and reSID are GPL v2 or later; the bundled Open ROMs '
                'are LGPL v3 or later. Both licences require the app to say '
                'so and to point at its source, which it does in About > '
                'Licences and source.',
            valueColor: ViceColors.accentTeal,
          ),
          const _Row(
            label: 'Privacy',
            value: 'No accounts, no analytics, no data collected and none '
                'sent anywhere. The app makes no network request of its own; '
                'the optional cover-artwork URL is the only thing that can, '
                'and only once you fill it in.',
            valueColor: ViceColors.accentTeal,
          ),
          const SizedBox(height: 6),
          const _SectionHeader('Paths'),
          // Reported separately from the machine ROMs, because it is missed
          // separately: the emulator boots and looks completely healthy
          // without it, right up until a disk image refuses to load.
          _Row(
            label: '1541 drive ROM',
            // Names the file. "Installed" on its own is how the wrong ROM
            // hides: dos1541ii shares the first seven characters with the one
            // VICE actually wants, so a folder holding only that reads as
            // ready and then fails on every disk.
            value: _driveRomInstalled
                ? 'Installed -- disk images can load ($_driveRomFile)'
                : _drivesDirFiles.isEmpty
                    ? 'MISSING in $_romDirPath/DRIVES/ -- .d64 files will fail '
                        'with ?DEVICE NOT PRESENT'
                    : 'MISSING -- DRIVES/ holds '
                        '${_drivesDirFiles.join(", ")}, but none of those is '
                        'the plain 1541 ROM. dos1541ii is the 1541-II, a '
                        'different drive. Add dos1541 or .d64 files fail with '
                        '?DEVICE NOT PRESENT.',
            valueColor: _driveRomInstalled
                ? ViceColors.accentTeal
                : Colors.orangeAccent,
            actionLabel: _driveRomInstalled ? 'Rescan' : 'Scan for ROMs',
            onAction: _importRoms,
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 2, 12, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final req in RomInstallService.requirements)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: RichText(
                      text: TextSpan(
                        style: const TextStyle(
                            color: Colors.white54, fontSize: 11),
                        children: [
                          TextSpan(
                            text: req.what,
                            style: const TextStyle(
                                color: Colors.white70,
                                fontWeight: FontWeight.bold),
                          ),
                          TextSpan(text: '  ->  $_romDirPath/${req.folder}/\n'),
                          TextSpan(text: req.why),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: 2),
                const Text(
                  RomInstallService.guidance,
                  style: TextStyle(color: Colors.white54, fontSize: 11),
                ),
              ],
            ),
          ),
          if (!_isFolderScan)
            _Row(
              label: 'Game files',
              value: '$_importedCount imported',
              actionLabel: 'Scan for games',
              onAction: _scanGames,
            ),
          _Row(
            label: 'Game artwork',
            value: _artworkPacks == 0
                ? 'none installed -- tiles show format labels'
                : '$_artworkPacks pack(s) installed',
            valueColor:
                _artworkPacks == 0 ? null : ViceColors.accentTeal,
            actionLabel: 'Scan for artwork',
            onAction: _scanArtwork,
          ),
          // Storage access first: on Android nothing below it works without
          // this, and the failure mode (games listed but unreadable) is
          // confusing enough to deserve top billing.
          if (PermissionsService.isRelevant)
            _Row(
              label: 'Shared storage access',
              value: _hasStorageAccess
                  ? 'Granted -- game files are readable'
                  : 'NOT granted -- games can be listed but not opened',
              valueColor:
                  _hasStorageAccess ? ViceColors.accentTeal : Colors.orangeAccent,
              actionLabel: _hasStorageAccess ? 'Re-check' : 'Grant access',
              onAction: _grantStorage,
            ),
          if (_isFolderScan) ...[
            _Row(
              label: 'Games folder',
              value: _gamesFolderPath ?? 'not set',
              actionLabel: 'Browse...',
              onAction: _browseGamesFolder,
            ),
            _Row(
              label: 'App data folder',
              value: _appFolderPath ?? 'not set',
              actionLabel: 'Browse...',
              onAction: _browseAppFolder,
            ),
          ] else ...[
            const _Row(
              label: 'App data folder',
              value: 'automatic (app sandbox storage)',
            ),
            _Row(
              label: 'Imported game / SID files',
              value: '$_importedCount file(s) in app storage',
              actionLabel: 'Scan',
              onAction: _importFiles,
            ),
            // The whole growing-the-library story, told where the button is.
            // Nothing here is a control - it is the answer to "how do I add
            // more?", asked at the moment it gets asked.
            const Padding(
              padding: EdgeInsets.fromLTRB(4, 10, 4, 4),
              child: Text(
                'Adding more games and music\n'
                '1.  In the Files app, open On My iPad > Retro-C64.\n'
                '2.  Drop in a zip - add games to your games zip, tunes to '
                'your music zip, or bring a whole new zip; the name does '
                'not matter.\n'
                '3.  Tap Scan above (or just relaunch the app).\n'
                'Games (.d64 .tap .t64 .crt .prg) go to the shelf, .sid '
                'tunes go to Music. A zip is removed once everything in it '
                'is imported, so the folder stays a drop zone.',
                style: TextStyle(
                  fontSize: 12,
                  height: 1.5,
                  color: Color(0xFF9AA4AE),
                ),
              ),
            ),
          ],
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: ElevatedButton(
              onPressed: _rerunWizard,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF242A31),
                foregroundColor: Colors.white,
                side: const BorderSide(color: Color(0xFF526173)),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(6)),
              ),
              child: const Text('Run Setup Wizard'),
            ),
          ),
        ],
      ],
    );
  }
}

class _Row extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;
  final String? actionLabel;
  final VoidCallback? onAction;

  const _Row({
    required this.label,
    required this.value,
    this.valueColor,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
        decoration: BoxDecoration(
          color: ViceColors.cardFill,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: ViceColors.cardStroke),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: const TextStyle(
                          color: Colors.white, fontSize: 13)),
                  const SizedBox(height: 2),
                  Text(
                    value,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: valueColor ?? ViceColors.textMuted, fontSize: 12),
                  ),
                ],
              ),
            ),
            if (actionLabel != null) ...[
              const SizedBox(width: 8),
              OutlinedButton(
                onPressed: onAction,
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: const BorderSide(color: Color(0xFF526173)),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(6)),
                ),
                child: Text(actionLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// A heading inside the Paths list.
///
/// Added for the compliance block: those rows answer a different question
/// from the rest of the screen -- "can this be submitted, and can that be
/// demonstrated" rather than "where do my files live" -- and running them
/// together as one undifferentiated list buried them.
class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 18, bottom: 6),
      child: Text(
        title.toUpperCase(),
        style: const TextStyle(
          color: Colors.white70,
          fontSize: 12,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.1,
        ),
      ),
    );
  }
}
