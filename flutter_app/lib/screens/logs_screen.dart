import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/app_log.dart';
import '../theme/vice_theme.dart';

/// The log, so a user can tell you what actually happened.
///
/// This exists because the interesting failures are invisible from outside
/// the app. The emulator core writes to stdout, which on iOS reaches no
/// system log at all -- a disk image failing with ?DEVICE NOT PRESENT
/// produced not one line in 14,000 lines of device log. Without this screen
/// the only report anyone can make is "it doesn't work".
///
/// Deliberately shows the RAW text rather than a prettied list: the whole
/// value is that it can be copied verbatim into a bug report, and anything
/// this screen reformats is something the reader has to un-reformat.
class LogsScreen extends StatefulWidget {
  const LogsScreen({super.key});

  @override
  State<LogsScreen> createState() => _LogsScreenState();
}

class _LogsScreenState extends State<LogsScreen> {
  String _text = 'Loading...';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final text = await AppLog.read();
    if (!mounted) return;
    setState(() {
      _text = text.trimRight();
      _loading = false;
    });
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: _text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Log copied to the clipboard.')),
    );
  }

  Future<void> _clear() async {
    await AppLog.clear();
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final path = AppLog.filePath;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
          child: Row(
            children: [
              const Expanded(
                child: Text('Logs',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold)),
              ),
              TextButton.icon(
                onPressed: _loading ? null : _copy,
                icon: const Icon(Icons.copy, size: 16),
                label: const Text('Copy'),
              ),
              const SizedBox(width: 4),
              TextButton.icon(
                onPressed: _loading ? null : _load,
                icon: const Icon(Icons.refresh, size: 16),
                label: const Text('Refresh'),
              ),
              const SizedBox(width: 4),
              TextButton.icon(
                onPressed: _loading ? null : _clear,
                icon: const Icon(Icons.delete_outline, size: 16),
                label: const Text('Clear'),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Reproduce the problem, come back here, and send this to the '
                'developer. It captures the emulator core as well as the app, '
                'which is the half that is otherwise invisible.',
                style: TextStyle(color: Colors.white70, fontSize: 12),
              ),
              if (path != null) ...[
                const SizedBox(height: 6),
                // Named so the file can be fetched without the app: on iOS
                // Documents is exposed through the Files app, so this path is
                // something the user can actually navigate to and attach to
                // an email.
                SelectableText(
                  Platform.isIOS
                      ? 'Also saved in the Files app under "C64-Retro '
                          'Emulator": ${_basename(path)}'
                      : path,
                  style: const TextStyle(color: Colors.white38, fontSize: 11),
                ),
              ],
              if (!AppLog.nativeCaptureActive) ...[
                const SizedBox(height: 6),
                const Text(
                  'Note: emulator-core output could not be captured on this '
                  'device, so this log covers the app only.',
                  style: TextStyle(color: Colors.orangeAccent, fontSize: 11),
                ),
              ],
            ],
          ),
        ),
        Expanded(
          child: Container(
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFF0E1114),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFF353B44)),
            ),
            child: _loading
                ? const Center(
                    child: Text('Loading...',
                        style: TextStyle(color: Colors.white38)))
                : SingleChildScrollView(
                    child: SelectableText(
                      _text.isEmpty ? '(nothing logged yet)' : _text,
                      style: const TextStyle(
                        color: ViceColors.accentTeal,
                        fontSize: 11,
                        fontFamily: 'monospace',
                        height: 1.35,
                      ),
                    ),
                  ),
          ),
        ),
      ],
    );
  }

  static String _basename(String path) =>
      path.contains('/') ? path.split('/').last : path;
}
