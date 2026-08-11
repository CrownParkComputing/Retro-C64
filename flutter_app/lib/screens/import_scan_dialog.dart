// "Find my downloads" -- the bulk alternative to picking files one by one.
//
// Points at a folder (Downloads by default, where it can be read without
// asking), lists every C64 file it can reach INCLUDING the ones still
// inside zips, and imports the ticked ones into the library in a single
// action. Disk/tape/cart/prg land in Games, .sid in the SID Workstation,
// which is what the two counts under the list are saying.
import 'dart:io';

import 'package:flutter/material.dart';

import '../services/app_prefs.dart';
import '../services/import_scanner.dart';
import '../services/storage_access.dart';
import '../theme/vice_theme.dart';
import 'setup_wizard_screen.dart' show kGamesImportSubdir;

/// Shows the scanner as a modal. Returns the number of files imported (0 if
/// the user cancelled), so the caller can rescan the library and say so.
///
/// [initialDirectory] overrides the folder scanned on open; without it the
/// platform's Downloads folder is used, which is the whole point of the
/// feature and also the one thing a test must not touch.
Future<int> showImportScanDialog(BuildContext context,
    {String? initialDirectory}) async {
  final imported = await showDialog<int>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _ImportScanDialog(initialDirectory: initialDirectory),
  );
  return imported ?? 0;
}

class _ImportScanDialog extends StatefulWidget {
  final String? initialDirectory;

  const _ImportScanDialog({this.initialDirectory});

  @override
  State<_ImportScanDialog> createState() => _ImportScanDialogState();
}

class _ImportScanDialogState extends State<_ImportScanDialog> {
  final _storage = StorageAccess.instance;

  List<ImportCandidate> _found = const [];
  final Set<int> _selected = {};
  bool _busy = true;
  String? _scannedLocation;
  String? _message;

  @override
  void initState() {
    super.initState();
    _scanDownloads();
  }

  /// The opening move: scan the platform's Downloads folder without making
  /// the user find it. On iOS there is no such folder the app may read, so
  /// this lands on the "choose somewhere" state instead.
  Future<void> _scanDownloads() async {
    final downloads =
        widget.initialDirectory ?? ImportScanner.defaultDownloadsDirectory();
    if (downloads == null) {
      setState(() {
        _busy = false;
        _message = 'Choose a folder or some files to scan -- '
            'zips are opened and searched too.';
      });
      return;
    }
    await _scanDirectory(downloads);
  }

  Future<void> _scanDirectory(String path) async {
    setState(() {
      _busy = true;
      _message = null;
    });
    final found = await ImportScanner.scanDirectory(path);
    if (!mounted) return;
    setState(() {
      _found = found;
      _selected
        ..clear()
        ..addAll(List.generate(found.length, (i) => i));
      _scannedLocation = path;
      _busy = false;
      _message = found.isEmpty ? 'Nothing playable found in $path.' : null;
    });
  }

  Future<void> _chooseFolder() async {
    if (_storage.kind != StorageStrategyKind.folderScan) {
      await _chooseFiles();
      return;
    }
    final picked =
        await _storage.pickFolder(dialogTitle: 'Choose a folder to scan');
    if (picked == null) return;
    await _scanDirectory(picked.path);
  }

  /// The file-import path (iOS): the sandbox cannot read a folder, so the
  /// user hands over the files themselves -- zips included, which is the
  /// point, since one zip can carry a whole collection.
  Future<void> _chooseFiles() async {
    setState(() => _busy = true);
    final picked = await _storage.pickAndImportFiles(
      destinationSubdir: kImportScanStagingSubdir,
      extensions: [...kGameFileExtensions, 'zip'],
    );
    if (!mounted) return;
    if (picked.isEmpty) {
      setState(() {
        _busy = false;
        _message = 'Nothing chosen.';
      });
      return;
    }
    final found =
        await ImportScanner.scanFiles([for (final f in picked) f.path]);
    if (!mounted) return;
    setState(() {
      _found = found;
      _selected
        ..clear()
        ..addAll(List.generate(found.length, (i) => i));
      _scannedLocation = '${picked.length} chosen file(s)';
      _busy = false;
      _message = found.isEmpty
          ? 'No C64 files in what you chose.'
          : null;
    });
  }

  Future<void> _import() async {
    final chosen = [
      for (var i = 0; i < _found.length; i++)
        if (_selected.contains(i)) _found[i],
    ];
    if (chosen.isEmpty) return;
    setState(() => _busy = true);

    // Where the library actually lives: the sandbox import directory on
    // iOS, the user's chosen games folder everywhere else. Deliberately NOT
    // the folder just scanned -- importing Downloads into Downloads would
    // do nothing useful and would look like it had worked.
    final destination = await _storage.importedDirectory(kGamesImportSubdir) ??
        await AppPrefs.getGamesFolderPath();
    if (destination == null) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _message = 'Set a games folder first (Paths -> Games folder), '
            'then scan again.';
      });
      return;
    }

    final imported = await ImportScanner.importAll(chosen, destination);
    await _clearStaging();
    if (!mounted) return;
    Navigator.of(context).pop(imported.length);
  }

  /// Throws away what the file-import flow staged. The zips and anything
  /// not ticked have served their purpose by now, and leaving them in the
  /// sandbox would quietly double the disk cost of every import.
  Future<void> _clearStaging() async {
    final staging = await _storage.importedDirectory(kImportScanStagingSubdir);
    if (staging == null) return;
    try {
      final dir = Directory(staging);
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    } catch (_) {
      // Tidying is best-effort; a file we cannot remove is not worth
      // failing an otherwise successful import over.
    }
  }

  @override
  Widget build(BuildContext context) {
    final sids = _found.where((c) => c.isSid).length;
    final games = _found.length - sids;
    return AlertDialog(
      backgroundColor: ViceColors.panelFill,
      title: const Text('Import from downloads',
          style: TextStyle(color: Colors.white, fontSize: 18)),
      content: SizedBox(
        width: 460,
        height: 420,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              _scannedLocation == null
                  ? 'Looking for .d64, .t64, .crt, .prg, .sid and friends'
                  : 'Scanned: $_scannedLocation',
              style: const TextStyle(
                  color: ViceColors.sidebarLabelIdle, fontSize: 12),
            ),
            const SizedBox(height: 8),
            if (_busy)
              const Expanded(child: Center(child: CircularProgressIndicator()))
            else if (_found.isEmpty)
              Expanded(
                child: Center(
                  child: Text(
                    _message ?? 'Nothing found.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white54, fontSize: 13),
                  ),
                ),
              )
            else
              Expanded(
                child: ListView.builder(
                  itemCount: _found.length,
                  itemBuilder: (context, i) {
                    final candidate = _found[i];
                    return CheckboxListTile(
                      dense: true,
                      value: _selected.contains(i),
                      onChanged: (on) => setState(() {
                        if (on == true) {
                          _selected.add(i);
                        } else {
                          _selected.remove(i);
                        }
                      }),
                      title: Text(candidate.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: Colors.white, fontSize: 13)),
                      subtitle: Text(
                        '${candidate.sourceLabel}  ${_size(candidate.sizeBytes)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: candidate.isInArchive
                                ? ViceColors.accentTeal
                                : Colors.white38,
                            fontSize: 11),
                      ),
                    );
                  },
                ),
              ),
            if (!_busy && _found.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  '$games game(s), $sids tune(s) -- '
                  '${_selected.length} selected',
                  style: const TextStyle(
                      color: ViceColors.accentTeal, fontSize: 12),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : _chooseFolder,
          child: Text(_storage.kind == StorageStrategyKind.folderScan
              ? 'Choose folder...'
              : 'Choose files...'),
        ),
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(0),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _busy || _selected.isEmpty ? null : _import,
          child: Text('Import ${_selected.length}'),
        ),
      ],
    );
  }

  static String _size(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).round()} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

/// Where the file-import platforms stage what the user hands over before it
/// is scanned. Kept apart from the library itself so a zip full of junk --
/// or a zip at all -- never lands in the games folder.
const String kImportScanStagingSubdir = 'incoming';
