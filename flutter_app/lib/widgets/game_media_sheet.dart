import 'package:flutter/material.dart';

import '../data/media_entry.dart';
import '../services/artwork_service.dart';

/// Everything the artwork pack holds for one game: box render, screenshot,
/// title screen, logo.
///
/// Reached by tapping a tile's info affordance rather than the tile itself --
/// tapping a game should still launch it, which is the whole point of the
/// grid.
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
              const SizedBox(height: 4),
              Text(
                '${widget.entry.extensionLabel} image',
                style: const TextStyle(color: Colors.white54, fontSize: 12),
              ),
              const SizedBox(height: 12),
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
        padding: EdgeInsets.symmetric(vertical: 32),
        child: Column(
          children: [
            Icon(Icons.image_not_supported, size: 36, color: Colors.white38),
            SizedBox(height: 8),
            Text(
              'No artwork for this title.',
              style: TextStyle(color: Colors.white54, fontSize: 13),
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
