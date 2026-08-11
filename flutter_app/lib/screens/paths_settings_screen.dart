// Paths & Setup tab (WorkbenchCategory.paths). Shows what the setup wizard
// currently has on file for this platform's storage strategy, lets the user
// change folders directly with real Browse buttons (rather than only being
// able to re-run the whole wizard), and -- on Android -- exposes the
// shared-storage permission that everything else depends on.
import 'dart:io';

import 'package:flutter/material.dart';

import '../services/app_prefs.dart';
import '../services/import_scanner.dart';
import '../services/permissions_service.dart';
import '../services/rom_store.dart';
import '../services/storage_access.dart';
import '../theme/vice_theme.dart';
import 'import_scan_dialog.dart';
import 'setup_wizard_screen.dart';

class PathsSettingsScreen extends StatefulWidget {
  /// Called after a folder changes or storage access is granted, so the
  /// workbench can rescan its library without the user going anywhere.
  final VoidCallback? onLibraryShouldRescan;

  /// Called once ROMs are installed, so the app can load the core it could
  /// not load at startup.
  final VoidCallback? onRomsChanged;

  const PathsSettingsScreen(
      {super.key, this.onLibraryShouldRescan, this.onRomsChanged});

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
  String _romStatus = '';
  bool _romsReady = false;

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
    final romRoot = await RomStore.romRoot();
    final romsReady = RomStore.canBoot(romRoot);
    final romStatus = RomStore.missing(romRoot).isEmpty
        ? 'All ROMs installed'
        : (romsReady
            ? 'Missing: ${RomStore.describeMissing(romRoot)}'
            : 'NOT installed -- the emulator cannot start. '
                'Missing: ${RomStore.describeMissing(romRoot)}');
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
      _romsReady = romsReady;
      _romStatus = romStatus;
      _loading = false;
    });
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

  Future<void> _importFiles() async {
    final imported =
        await _storage.pickAndImportFiles(destinationSubdir: kGamesImportSubdir);
    if (!mounted) return;
    if (imported.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Imported ${imported.length} file(s).')),
      );
    }
    await _load();
    widget.onLibraryShouldRescan?.call();
  }

  /// Imports the user's own C64 ROMs. They are not shipped with the app,
  /// so until this has been done once the emulator cannot start at all --
  /// which is why this row sits at the top of the screen in red.
  ///
  /// Takes a folder, loose .bin files or a zip of them (ROM sets are almost
  /// always distributed zipped) and installs each recognised image under the
  /// name VICE opens it by; see RomStore.
  Future<void> _importRoms() async {
    final List<String> candidates;
    if (_isFolderScan) {
      final picked =
          await _storage.pickFolder(dialogTitle: 'Choose a folder of C64 ROMs');
      if (picked == null) return;
      final found = await ImportScanner.scanDirectory(picked.path,
          extensions: kRomFileExtensions);
      candidates = [for (final c in found) c.sourcePath];
      // A zip in there has to be expanded before RomStore can read the
      // images out of it.
      final staged = await _stageArchived(found);
      candidates
        ..clear()
        ..addAll(staged);
    } else {
      final picked = await _storage.pickAndImportFiles(
        destinationSubdir: kImportScanStagingSubdir,
        extensions: kRomFileExtensions,
      );
      if (picked.isEmpty) return;
      final found = await ImportScanner.scanFiles([for (final f in picked) f.path],
          extensions: kRomFileExtensions);
      candidates = await _stageArchived(found);
    }

    final root = await RomStore.romRoot();
    final installed = await RomStore.install(candidates, root);
    if (!mounted) return;
    final missing = RomStore.missing(root);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(installed.isEmpty
          ? 'No C64 ROMs recognised in what you chose.'
          : 'Installed ${installed.map((s) => s.description).join(', ')}.'
              '${missing.isEmpty ? '' : ' Still missing: ${RomStore.describeMissing(root)}.'}'),
    ));
    await _load();
    widget.onRomsChanged?.call();
  }

  /// Extracts any archived candidates to real files so RomStore can copy
  /// them, and returns every candidate as a plain path.
  Future<List<String>> _stageArchived(List<ImportCandidate> found) async {
    final archived = found.where((c) => c.isInArchive).toList();
    final loose = [for (final c in found) if (!c.isInArchive) c.sourcePath];
    if (archived.isEmpty) return loose;
    final staging = await _storage.importedDirectory(kImportScanStagingSubdir) ??
        Directory.systemTemp.createTempSync('vice_roms').path;
    final extracted = await ImportScanner.importAll(archived, staging);
    return [...loose, for (final f in extracted) f.path];
  }

  Future<void> _scanDownloads() async {
    final imported = await showImportScanDialog(context);
    if (!mounted || imported == 0) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Imported $imported file(s).')),
    );
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
        const Text('Paths & Setup',
            style: TextStyle(
                color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
        const SizedBox(height: 10),
        if (_loading)
          const Text('Loading...', style: TextStyle(color: Colors.white38))
        else ...[
          // Storage access first: on Android nothing below it works without
          // Above everything else: without ROMs there is no emulator at
          // all, so this is the first thing a new install has to deal with.
          _Row(
            label: 'C64 ROMs',
            value: _romStatus,
            valueColor: _romsReady ? ViceColors.accentTeal : Colors.redAccent,
            actionLabel: _romsReady ? 'Replace...' : 'Import ROMs...',
            onAction: _importRoms,
          ),
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
          // Available on every platform, not just the sandboxed ones: a
          // folder of downloads full of zips is the normal way C64 files
          // arrive, whichever OS you are on.
          _Row(
            label: 'Scan downloads',
            value: 'Find games and SIDs in a folder, zips included',
            actionLabel: 'Scan...',
            onAction: _scanDownloads,
          ),
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
