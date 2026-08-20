import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../data/vice_resource_catalog.dart';
import '../ffi/vice_core.dart';
import '../ffi/vice_native_paths.dart';
import '../theme/vice_theme.dart';

/// The emulated machine's own settings -- VICE resources, edited live.
///
/// Two halves, and the split is the point:
///
///   * the curated sections at the top ([kViceCommonResources]) put a real
///     label, an explanation and named values on the settings people reach
///     for. `SidModel=1` is not a user interface.
///   * "All resources" below is the machine's ENTIRE option set, read out of
///     the core itself via resources_dump(). It cannot go stale when VICE is
///     updated, and it is the answer to "the option I want isn't here".
///
/// Everything is read from and written to the live core, so a change takes
/// effect on the running game -- writes are queued for the core thread and
/// land at the next frame boundary (see the bridge's resource mailbox).
///
/// With no core running there is no resource table to show: VICE builds it
/// during init_main. The screen says so rather than showing an empty list.
class CoreSettingsScreen extends StatefulWidget {
  final ViceCore core;

  const CoreSettingsScreen({super.key, required this.core});

  @override
  State<CoreSettingsScreen> createState() => _CoreSettingsScreenState();
}

class _CoreSettingsScreenState extends State<CoreSettingsScreen> {
  /// name -> value, as dumped by the core. Empty until the first dump lands.
  Map<String, String> _all = const {};
  String _filter = '';
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    if (!widget.core.hasResourceApi) {
      setState(() {
        _loading = false;
        _all = const {};
        _error = 'This build of the core has no resource access. The native '
            'core is older than the app -- rebuild it (see '
            'docs/NATIVE_BUILD.md) and the machine\'s settings appear here.';
      });
      return;
    }
    if (!widget.core.isRunning) {
      setState(() {
        _loading = false;
        _all = const {};
        _error =
            'No machine is running. VICE builds its resource table when '
            'the machine starts, so there is nothing to list until you '
            'launch a title.';
      });
      return;
    }
    try {
      final dir = await ViceNativePaths.supportDirPath().timeout(
        const Duration(seconds: 5),
      );
      final path = p.join(dir, 'resources.dump');
      if (!widget.core.dumpResources(path)) {
        throw const FileSystemException('the core refused to dump resources');
      }
      // Bounded: a path lookup or a read that never returns must degrade to
      // "no list", not to a screen that waits forever.
      final text = await File(
        path,
      ).readAsString().timeout(const Duration(seconds: 5));
      if (!mounted) return;
      setState(() {
        _all = _parse(text);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not read the machine\'s settings: $e';
      });
    }
  }

  /// resources_dump() writes `Name=value` per line, strings quoted. Lines it
  /// cannot represent are skipped rather than guessed at.
  static Map<String, String> _parse(String text) {
    final out = <String, String>{};
    for (final line in text.split('\n')) {
      final eq = line.indexOf('=');
      if (eq <= 0) continue;
      final name = line.substring(0, eq).trim();
      var value = line.substring(eq + 1).trim();
      if (value.length >= 2 && value.startsWith('"') && value.endsWith('"')) {
        value = value.substring(1, value.length - 1);
      }
      if (name.isEmpty) continue;
      out[name] = value;
    }
    return out;
  }

  int? _intOf(String name) {
    final live = widget.core.getResourceInt(name);
    if (live != null) return live;
    return int.tryParse(_all[name] ?? '');
  }

  Future<void> _setInt(String name, int value) async {
    final ok = widget.core.setResourceInt(name, value);
    if (!ok && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('The core refused $name')));
      return;
    }
    // Optimistic, then re-read: the write lands on the core thread at the
    // next frame, so reading straight back would show the old value.
    setState(() => _all = {..._all, name: '$value'});
    await Future<void>.delayed(const Duration(milliseconds: 120));
    if (mounted) setState(() {});
  }

  Widget _card({required Widget child}) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
    child: Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: ViceColors.cardFill,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: ViceColors.cardStroke),
      ),
      child: child,
    ),
  );

  Widget _sectionHeader(String title) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
    child: Text(
      title.toUpperCase(),
      style: const TextStyle(
        color: ViceColors.accentTeal,
        fontSize: 12,
        fontWeight: FontWeight.bold,
        letterSpacing: 1.2,
      ),
    ),
  );

  Widget _option(ViceResourceOption option) {
    final value = _intOf(option.name);
    // A resource this machine does not have is not shown at all -- an
    // unusable row is worse than a missing one.
    if (value == null) return const SizedBox.shrink();
    return _card(
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  option.label,
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                ),
                const SizedBox(height: 2),
                Text(
                  option.description,
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
                Text(
                  option.name,
                  style: const TextStyle(color: Colors.white24, fontSize: 10),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          switch (option.kind) {
            ViceResourceKind.toggle => Switch(
              value: value != 0,
              activeThumbColor: ViceColors.accentTeal,
              onChanged: (on) => _setInt(option.name, on ? 1 : 0),
            ),
            ViceResourceKind.choice => DropdownButton<int>(
              value: option.choices.any((c) => c.value == value)
                  ? value
                  // A value the catalogue does not name is still shown, so
                  // the dropdown never silently rewrites what the machine
                  // is actually set to.
                  : null,
              hint: Text(
                '$value',
                style: const TextStyle(color: Colors.white70),
              ),
              dropdownColor: ViceColors.panelFill,
              style: const TextStyle(color: Colors.white, fontSize: 13),
              underline: const SizedBox.shrink(),
              items: [
                for (final c in option.choices)
                  DropdownMenuItem(value: c.value, child: Text(c.label)),
              ],
              onChanged: (v) => v == null ? null : _setInt(option.name, v),
            ),
          },
        ],
      ),
    );
  }

  Widget _rawRow(String name, String value) {
    final asInt = int.tryParse(value);
    return _card(
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                ),
                Text(
                  value.isEmpty ? '(empty)' : value,
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
              ],
            ),
          ),
          // Only int resources are editable here. A string resource is a
          // path or a device name, and a free-text box that can point the
          // machine at a file that does not exist is a way to break it from
          // a settings screen.
          if (asInt != null) ...[
            IconButton(
              icon: const Icon(Icons.remove, size: 18),
              color: ViceColors.textMuted,
              onPressed: () => _setInt(name, asInt - 1),
              tooltip: 'Decrease',
            ),
            IconButton(
              icon: const Icon(Icons.add, size: 18),
              color: ViceColors.textMuted,
              onPressed: () => _setInt(name, asInt + 1),
              tooltip: 'Increase',
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Deliberately no full-screen loading state. The curated options are read
    // one resource at a time straight from the core and are ready on the
    // first frame; only the full list waits on a file. Gating the whole
    // screen on that left it saying "Reading the machine..." forever when the
    // path lookup wedged, with settings that had been available all along.
    final running = widget.core.isRunning && widget.core.hasResourceApi;

    final error = _error;
    final filtered =
        _all.entries
            .where(
              (e) =>
                  _filter.isEmpty ||
                  e.key.toLowerCase().contains(_filter.toLowerCase()),
            )
            .toList()
          ..sort((a, b) => a.key.compareTo(b.key));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
          child: Row(
            children: [
              const Expanded(
                child: Text(
                  'Core',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.refresh, size: 20),
                color: ViceColors.textMuted,
                tooltip: 'Re-read the machine',
                onPressed: _reload,
              ),
            ],
          ),
        ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              error,
              style: const TextStyle(
                color: ViceColors.textMuted2,
                fontSize: 12,
              ),
            ),
          ),
        Expanded(
          child: ListView(
            children: [
              // A section header over nothing is worse than no section: with
              // no machine running every option is unreadable, so the whole
              // curated block goes rather than leaving five empty bands.
              if (running)
                for (final section in kViceCommonResources)
                  if (section.options.any((o) => _intOf(o.name) != null)) ...[
                    _sectionHeader(section.title),
                    for (final option in section.options) _option(option),
                  ],
              if (running) _sectionHeader('All resources (${_all.length})'),
              if (_loading)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    'Listing...',
                    style: TextStyle(color: Colors.white38, fontSize: 12),
                  ),
                ),
              if (running)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
                  child: TextField(
                    onChanged: (v) => setState(() => _filter = v),
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                    decoration: const InputDecoration(
                      hintText: 'Filter by name (drive, sid, vicii...)',
                      hintStyle: TextStyle(color: ViceColors.sidebarLabelIdle),
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
              if (running)
                for (final e in filtered) _rawRow(e.key, e.value),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ],
    );
  }
}
