import 'dart:io';

import 'package:flutter/material.dart';

import '../data/category.dart';
import '../data/media_entry.dart';
import '../services/artwork_service.dart';

/// What a title is and what its artwork pack holds: format, size, how it
/// loads, then box render, screenshot, title screen and logo.
///
/// Opened by LONG-PRESSING a tile, not tapping it -- a tap launches the game,
/// which is what the grid is for. The facts are shown whether or not artwork
/// exists, so a library with no packs installed still gets something useful
/// out of the gesture.
Future<void> showGameMediaSheet(
  BuildContext context, {
  required MediaEntry entry,
  required VoidCallback onPlay,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: const Color(0xFF11161B),
    builder: (context) => _GameMediaSheet(entry: entry, onPlay: onPlay),
  );
}

class _GameMediaSheet extends StatefulWidget {
  const _GameMediaSheet({required this.entry, required this.onPlay});

  final MediaEntry entry;
  final VoidCallback onPlay;

  @override
  State<_GameMediaSheet> createState() => _GameMediaSheetState();
}

class _GameMediaSheetState extends State<_GameMediaSheet> {
  GameArtwork? _artwork;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final artwork = await ArtworkService.artworkFor(widget.entry.displayName);
    if (!mounted) return;
    setState(() {
      _artwork = artwork;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final media = _artwork?.all ?? const [];

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.entry.baseName,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold),
                    ),
                  ),
                  FilledButton.icon(
                    onPressed: () {
                      Navigator.of(context).pop();
                      widget.onPlay();
                    },
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('Play'),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              _InfoGrid(entry: widget.entry),
              const SizedBox(height: 14),
              Flexible(child: _body(media)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _body(List<({String label, dynamic file})> media) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 40),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (media.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 28),
        child: Column(
          children: [
            Icon(Icons.image_not_supported, size: 36, color: Colors.white38),
            SizedBox(height: 8),
            Text(
              'No artwork for this title.',
              style: TextStyle(color: Colors.white54, fontSize: 13),
            ),
            SizedBox(height: 4),
            // Names the way out rather than leaving a dead end: artwork is
            // installed by a scan, not fetched on demand.
            Text(
              'Add <name>.zip packs and run Paths > Scan for artwork.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white38, fontSize: 11),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      shrinkWrap: true,
      itemCount: media.length,
      separatorBuilder: (_, _) => const SizedBox(height: 16),
      itemBuilder: (context, index) {
        final item = media[index];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              item.label.toUpperCase(),
              style: const TextStyle(
                  color: Colors.white54,
                  fontSize: 11,
                  letterSpacing: 1.1,
                  fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.file(
                item.file,
                fit: BoxFit.contain,
                errorBuilder: (_, _, _) => const SizedBox.shrink(),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// The facts about a title that are worth seeing before launching it.
///
/// Shown whether or not artwork exists, so the sheet is never just an empty
/// box: the file is the thing being launched, and its format decides how the
/// core loads it.
class _InfoGrid extends StatelessWidget {
  const _InfoGrid({required this.entry});

  final MediaEntry entry;

  static String _formatLabel(MediaFormatFilter type, String extension) =>
      switch (type) {
        MediaFormatFilter.disk => 'Disk image ($extension)',
        MediaFormatFilter.tape => 'Tape image ($extension)',
        MediaFormatFilter.cartridge => 'Cartridge ($extension)',
        MediaFormatFilter.prg => 'Program ($extension)',
        MediaFormatFilter.none => extension,
      };

  static String _size(String path) {
    try {
      final bytes = File(path).lengthSync();
      if (bytes < 1024) return '$bytes bytes';
      if (bytes < 1024 * 1024) return '${(bytes / 1024).round()} KB';
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    } catch (_) {
      return 'unknown';
    }
  }

  /// How this title will actually load, which is the part people care about
  /// and the part that differs most between formats.
  static String _loadNote(MediaFormatFilter type) => switch (type) {
        MediaFormatFilter.disk =>
          'Autostarts from disk. Needs the 1541 DOS ROM.',
        MediaFormatFilter.tape =>
          'Loads from tape -- this can take several minutes.',
        MediaFormatFilter.cartridge => 'Starts immediately on reset.',
        MediaFormatFilter.prg => 'Loaded straight into memory.',
        MediaFormatFilter.none => '',
      };

  @override
  Widget build(BuildContext context) {
    final note = _loadNote(entry.mediaType);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 20,
          runSpacing: 6,
          children: [
            _Fact(label: 'Format', value: _formatLabel(entry.mediaType, entry.extensionLabel)),
            _Fact(label: 'Size', value: _size(entry.path)),
            _Fact(label: 'File', value: entry.displayName),
          ],
        ),
        if (note.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            note,
            style: const TextStyle(color: Colors.white54, fontSize: 11),
          ),
        ],
      ],
    );
  }
}

class _Fact extends StatelessWidget {
  const _Fact({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label.toUpperCase(),
          style: const TextStyle(
              color: Colors.white38,
              fontSize: 9,
              letterSpacing: 1.1,
              fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: const TextStyle(color: Colors.white, fontSize: 12),
        ),
      ],
    );
  }
}
