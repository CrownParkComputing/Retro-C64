import 'package:flutter/material.dart';

import '../data/media_entry.dart';
import '../theme/vice_theme.dart';

/// Port of MainActivity.createMediaCard (grid mode only -- the carousel
/// mode is used by a "list view" toggle deferred in this pass).
///
/// Box art (IGDB) is deferred; the cover slot always shows the
/// extension/format placeholder label, same fallback the Android card uses
/// while art hasn't loaded.
class MediaCard extends StatelessWidget {
  final MediaEntry entry;
  final VoidCallback onTap;

  const MediaCard({super.key, required this.entry, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: ViceMetrics.mediaCardWidth,
      height: ViceMetrics.mediaCardHeight,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
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
                  child: Text(
                    entry.extensionLabel,
                    style: const TextStyle(
                      color: Color(0xFFB9C2CE),
                      fontSize: 12,
                    ),
                  ),
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
