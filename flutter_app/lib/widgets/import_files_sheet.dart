// In-app import sheet for the file-import platforms (iOS).
//
// The system document picker (UIDocumentPickerViewController, reached through
// file_picker) can browse other providers, but it cannot see files that are
// already inside this app's own sandbox -- and that is exactly where C64 media
// arrives from every route that does not involve the picker:
//
//   * dragged into "C64-Retro" in the Files app (UIFileSharingEnabled);
//   * opened into the app from another app, landing in Documents/Inbox;
//   * pushed over USB from the build machine.
//
// So this sheet lists what StorageAccess.listImportable() finds in the
// container and imports the selection. The system picker is still available
// from the same sheet for files that live elsewhere on the device.
import 'package:flutter/material.dart';

import '../services/storage_access.dart';

/// Shows the import sheet and returns the files that were imported, or an
/// empty list if the user cancelled or nothing was selected.
Future<List<ImportedFile>> showImportFilesSheet(
  BuildContext context, {
  required String destinationSubdir,
  List<String> extensions = kGameFileExtensions,
}) async {
  final result = await showModalBottomSheet<List<ImportedFile>>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => _ImportFilesSheet(
      destinationSubdir: destinationSubdir,
      extensions: extensions,
    ),
  );
  return result ?? const [];
}

class _ImportFilesSheet extends StatefulWidget {
  const _ImportFilesSheet({
    required this.destinationSubdir,
    required this.extensions,
  });

  final String destinationSubdir;
  final List<String> extensions;

  @override
  State<_ImportFilesSheet> createState() => _ImportFilesSheetState();
}

class _ImportFilesSheetState extends State<_ImportFilesSheet> {
  final StorageAccess _storage = StorageAccess.instance;
  final Set<String> _selected = <String>{};

  List<ImportedFile>? _available;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() {
      _available = null;
      _error = null;
    });
    try {
      final files = await _storage.listImportable(
        destinationSubdir: widget.destinationSubdir,
        extensions: widget.extensions,
      );
      if (!mounted) return;
      setState(() {
        _available = files;
        // Pre-select everything: the common case is "I just put these here,
        // take them all".
        _selected
          ..clear()
          ..addAll(files.map((f) => f.path));
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    }
  }

  Future<void> _importSelected() async {
    final files = (_available ?? const <ImportedFile>[])
        .where((f) => _selected.contains(f.path))
        .toList();
    if (files.isEmpty) return;

    setState(() => _busy = true);
    try {
      final imported = await _storage.importFiles(
        files,
        destinationSubdir: widget.destinationSubdir,
      );
      if (!mounted) return;
      Navigator.of(context).pop(imported);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _useSystemPicker() async {
    setState(() => _busy = true);
    try {
      final imported = await _storage.pickAndImportFiles(
        destinationSubdir: widget.destinationSubdir,
        extensions: widget.extensions,
      );
      if (!mounted) return;
      if (imported.isEmpty) {
        setState(() => _busy = false);
        return;
      }
      Navigator.of(context).pop(imported);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final available = _available;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.8,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Import games', style: theme.textTheme.titleLarge),
              const SizedBox(height: 4),
              Text(
                'Files already on this device, in the app’s folder.',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              Flexible(child: _buildBody(theme, available)),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _busy ? null : _useSystemPicker,
                      icon: const Icon(Icons.folder_open),
                      label: const Text('Browse Files…'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed:
                          _busy || _selected.isEmpty ? null : _importSelected,
                      icon: const Icon(Icons.download),
                      label: Text(_selected.isEmpty
                          ? 'Import'
                          : 'Import ${_selected.length}'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody(ThemeData theme, List<ImportedFile>? available) {
    if (_error != null) {
      return SingleChildScrollView(
        child: Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
      );
    }
    if (available == null) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 32),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (available.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Column(
          children: [
            const Icon(Icons.inbox, size: 40),
            const SizedBox(height: 8),
            Text(
              'Nothing waiting to import.\n'
              'Add .d64/.tap files to "C64-Retro" in the Files app, '
              'then pull to refresh.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium,
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView.builder(
        shrinkWrap: true,
        itemCount: available.length,
        itemBuilder: (context, index) {
          final file = available[index];
          return CheckboxListTile(
            value: _selected.contains(file.path),
            onChanged: _busy
                ? null
                : (checked) => setState(() {
                      if (checked ?? false) {
                        _selected.add(file.path);
                      } else {
                        _selected.remove(file.path);
                      }
                    }),
            title: Text(file.displayName),
            dense: true,
          );
        },
      ),
    );
  }
}
