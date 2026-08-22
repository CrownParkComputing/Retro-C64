import 'dart:io';

import 'package:flutter/material.dart';
import 'package:retro_c64/services/artwork_service.dart';

import 'package:retro_c64/data/media_entry.dart';
import 'package:retro_c64/theme/vice_theme.dart';

/// Port of MainActivity.createMediaCard (grid mode only -- the carousel
/// mode is used by a "list view" toggle deferred in this pass).
///
/// The cover slot shows the game's 3D box render once its artwork pack has
/// been fetched (see ArtworkService), falling back to the extension/format
/// label -- which is also what a title with no artwork keeps forever.
class MediaCard extends StatefulWidget {
  final MediaEntry entry;
  final VoidCallback onTap;

  /// Opens the media sheet. Separate from [onTap] on purpose: tapping a game
  /// launches it, which is what the grid is for -- browsing its artwork is a
  /// deliberate second gesture, not something to trip over.
  final VoidCallback? onShowMedia;

  const MediaCard({
    super.key,
    required this.entry,
    required this.onTap,
    this.onShowMedia,
  });

  @override
  State<MediaCard> createState() => _MediaCardState();
}

class _MediaCardState extends State<MediaCard> {
  GameArtwork? _artwork;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(MediaCard old) {
    super.didUpdateWidget(old);
    if (old.entry.path != widget.entry.path) _load();
  }

  Future<void> _load() async {
    final artwork = await ArtworkService.artworkFor(widget.entry.displayName);
    if (!mounted) return;
    setState(() => _artwork = artwork);
  }

  MediaEntry get entry => widget.entry;
  VoidCallback get onTap => widget.onTap;

  File? get _box3d => _artwork?.box3d;

  /// The format label, which is what a title shows before its artwork
  /// arrives and permanently if it has none.
  Widget _placeholder() => Text(
        entry.extensionLabel,
        style: const TextStyle(color: Color(0xFFB9C2CE), fontSize: 12),
      );

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: ViceMetrics.mediaCardWidth,
      height: ViceMetrics.mediaCardHeight,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          onLongPress: widget.onShowMedia,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: ViceColors.cardFill,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: ViceColors.cardStroke),
            ),
            child: Column(
              children: [
                Container(
                  height: ViceMetrics.mediaCoverHeight,
                  width: double.infinity,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: ViceColors.coverFill,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: ViceColors.coverStroke),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: _box3d != null
                      ? Image.file(
                          _box3d!,
                          fit: BoxFit.contain,
                          // A pack deleted underneath us must not take the
                          // whole grid down with it.
                          errorBuilder: (_, _, _) => _placeholder(),
                        )
                      : _placeholder(),
                ),
                SizedBox(
                  height: 28,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      entry.baseName,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white, fontSize: 10),
                    ),
                  ),
                ),
                SizedBox(
                  height: 16,
                  child: Text(
                    '.${entry.extensionLabel.toLowerCase()}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        color: ViceColors.textMuted, fontSize: 8),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
