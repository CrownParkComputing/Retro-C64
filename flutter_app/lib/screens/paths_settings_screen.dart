// Paths & Setup tab (WorkbenchCategory.paths). Shows what the setup wizard
// currently has on file for this platform's storage strategy, lets the user
// change folders directly with real Browse buttons (rather than only being
// able to re-run the whole wizard), and -- on Android -- exposes the
// shared-storage permission that everything else depends on.
import 'package:flutter/material.dart';

import '../services/app_prefs.dart';
import '../services/artwork_service.dart';
import '../services/rom_install_service.dart';
import '../ffi/vice_native_paths.dart';
import '../services/permissions_service.dart';
import '../services/storage_access.dart';
import '../widgets/import_files_sheet.dart';
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

  Future<void> _importFiles() async {
    final imported = await showImportFilesSheet(
      context,
      destinationSubdir: kGamesImportSubdir,
    );
    if (!mounted) return;
    if (imported.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Imported ${imported.length} file(s).')),
      );
    }
    await _load();
    widget.onLibraryShouldRescan?.call();
  }

  Future<void> _grantStorage() async {
    await PermissionsService.requestStorageAccess();
    await _load();
    widget.onLibraryShouldRescan?.call();
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
          const Padding(
            padding: EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: Text(
              RomInstallService.guidance,
              style: TextStyle(color: Colors.white54, fontSize: 11),
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
              actionLabel: 'Add files...',
              onAction: _importFiles,
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
