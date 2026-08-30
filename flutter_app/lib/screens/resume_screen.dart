import 'dart:io';

import 'package:flutter/material.dart';

import 'package:retro_c64/services/save_state_service.dart';
import 'package:retro_c64/theme/vice_theme.dart';

/// The sidebar's Resume destination.
///
/// This used to be a hardcoded `SettingsPlaceholder` that always said "No
/// game in progress", which was wrong in the one case that mattered: the
/// user leaves a running game, opens Resume, and is told nothing is running
/// while the core is still going in the background. It now shows two real
/// things:
///
///   - the CURRENT session, if a title is loaded, with a Resume action that
///     goes straight back to the emulator screen (and unpauses it -- the
///     workbench pauses the core on the way out, so without that you'd get
///     a frozen picture);
///   - the last few SAVED sessions (real VICE machine snapshots, see
///     services/save_state_service.dart), each resumable to the exact cycle
///     it was left at.
class ResumeScreen extends StatefulWidget {
  /// Title of the session currently loaded in the core, or null if none.
  final String? currentTitle;

  /// Returns to the emulator screen with the current session.
  final VoidCallback onResumeCurrent;

  /// Restores [entry] and shows the emulator screen.
  final Future<void> Function(SaveStateEntry entry) onResumeSaved;

  /// Where the saved sessions come from and how one is deleted. Both
  /// default to [SaveStateService], which is what the app uses; they are
  /// injectable so this screen can be tested without touching the real
  /// application-support directory (widget tests run on a fake clock, which
  /// filesystem I/O never completes under).
  final Future<List<SaveStateEntry>> Function() loadSaved;
  final Future<void> Function(SaveStateEntry entry) deleteSaved;

  const ResumeScreen({
    super.key,
    required this.currentTitle,
    required this.onResumeCurrent,
    required this.onResumeSaved,
    this.loadSaved = SaveStateService.list,
    this.deleteSaved = SaveStateService.remove,
  });

  @override
  State<ResumeScreen> createState() => _ResumeScreenState();
}

class _ResumeScreenState extends State<ResumeScreen> {
  List<SaveStateEntry>? _saved;
  String? _busyPath;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final entries = await widget.loadSaved();
    if (mounted) setState(() => _saved = entries);
  }

  Future<void> _resume(SaveStateEntry entry) async {
    setState(() => _busyPath = _keyOf(entry));
    try {
      await widget.onResumeSaved(entry);
    } finally {
      if (mounted) setState(() => _busyPath = null);
    }
  }

  /// Identifies a row for the busy spinner. Not snapshotPath: a restart-only
  /// entry has none, and null == null would have spun every such row at once.
  static String _keyOf(SaveStateEntry entry) =>
      '${entry.title} ${entry.mediaPath}';

  Future<void> _delete(SaveStateEntry entry) async {
    await widget.deleteSaved(entry);
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    final saved = _saved;
    final current = widget.currentTitle;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text('Resume',
            style: TextStyle(
                color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        Text(
          'The last ${SaveStateService.maxEntries} titles you played. Most are '
          'kept as a full machine snapshot and pick up exactly where you left '
          'off; any the emulator cannot snapshot are marked Restart and start '
          'again from the beginning.',
          style: const TextStyle(color: Colors.white54, fontSize: 12),
        ),
        const SizedBox(height: 16),
        if (current != null) ...[
          const _SectionLabel('In progress'),
          _CurrentSessionCard(
            title: current,
            onResume: widget.onResumeCurrent,
          ),
          const SizedBox(height: 20),
        ],
        const _SectionLabel('Saved sessions'),
        if (saved == null)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (saved.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Text(
              current == null
                  ? 'Nothing saved yet. Launch something from Games -- when you '
                      'come back to the workbench, that session is saved here '
                      'automatically.'
                  : 'No earlier sessions saved yet. Leaving this game will save it here.',
              style: const TextStyle(color: Colors.white54, fontSize: 13),
            ),
          )
        else
          for (final entry in saved)
            _SavedSessionCard(
              entry: entry,
              busy: _busyPath == _keyOf(entry),
              onResume: () => _resume(entry),
              onDelete: () => _delete(entry),
            ),
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text.toUpperCase(),
        style: const TextStyle(
            color: ViceColors.accentCyan,
            fontSize: 11,
            letterSpacing: 1.2,
            fontWeight: FontWeight.bold),
      ),
    );
  }
}

class _CurrentSessionCard extends StatelessWidget {
  final String title;
  final VoidCallback onResume;

  const _CurrentSessionCard({required this.title, required this.onResume});

  @override
  Widget build(BuildContext context) {
    return _Card(
      onTap: onResume,
      child: Row(
        children: [
          Container(
            width: 56,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: const Color(0xFF1B3A36),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: ViceColors.accentCyan),
            ),
            child: const Icon(Icons.play_arrow,
                color: ViceColors.accentCyan, size: 26),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontSize: 15)),
                const SizedBox(height: 2),
                const Text('Loaded and paused in the background',
                    style: TextStyle(color: Colors.white54, fontSize: 12)),
              ],
            ),
          ),
          const Text('RESUME',
              style: TextStyle(
                  color: ViceColors.accentCyan,
                  fontSize: 12,
                  fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}

class _SavedSessionCard extends StatelessWidget {
  final SaveStateEntry entry;
  final bool busy;
  final VoidCallback onResume;
  final VoidCallback onDelete;

  const _SavedSessionCard({
    required this.entry,
    required this.busy,
    required this.onResume,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final thumb = entry.thumbnailPath;
    // The single most important string on this screen. A session with no
    // usable snapshot says RESTART, because tapping it really does start the
    // game from the beginning -- promising RESUME and then booting to the
    // title screen is the failure this label exists to prevent.
    final canResume = entry.canResume;
    return _Card(
      onTap: busy ? null : onResume,
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: SizedBox(
              width: 72,
              height: 52,
              child: (thumb != null && File(thumb).existsSync())
                  ? Image.file(File(thumb), fit: BoxFit.cover,
                      errorBuilder: (context, error, stack) =>
                          const _ThumbFallback())
                  : const _ThumbFallback(),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(entry.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontSize: 15)),
                const SizedBox(height: 2),
                Text(
                  canResume
                      ? _formatWhen(entry.savedAt)
                      : entry.unsupportedReason ??
                          'No save state -- this one starts from the beginning.',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: canResume ? Colors.white54 : const Color(0xFFD9A441),
                      fontSize: 12),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: Text(
              canResume ? 'RESUME' : 'RESTART',
              style: TextStyle(
                  color: canResume
                      ? ViceColors.accentCyan
                      : const Color(0xFFD9A441),
                  fontSize: 12,
                  fontWeight: FontWeight.bold),
            ),
          ),
          if (busy)
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else
            IconButton(
              tooltip: 'Delete this save',
              icon: const Icon(Icons.delete_outline, color: Colors.white38),
              onPressed: onDelete,
            ),
        ],
      ),
    );
  }

  static String _two(int n) => n.toString().padLeft(2, '0');

  static String _formatWhen(DateTime when) {
    final diff = DateTime.now().difference(when);
    if (diff.inMinutes < 1) return 'Saved just now';
    if (diff.inMinutes < 60) return 'Saved ${diff.inMinutes}m ago';
    if (diff.inHours < 24) return 'Saved ${diff.inHours}h ago';
    if (diff.inDays < 7) return 'Saved ${diff.inDays}d ago';
    return 'Saved ${when.year}-${_two(when.month)}-${_two(when.day)} '
        '${_two(when.hour)}:${_two(when.minute)}';
  }
}

class _ThumbFallback extends StatelessWidget {
  const _ThumbFallback();
  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF11151A),
      alignment: Alignment.center,
      child: const Icon(Icons.videogame_asset_outlined,
          color: Colors.white24, size: 22),
    );
  }
}

class _Card extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;
  const _Card({required this.child, this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: ViceColors.cardFill,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFF353B44)),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}
