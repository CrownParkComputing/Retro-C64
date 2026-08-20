import 'package:flutter/material.dart';

import '../data/media_entry.dart';
import '../theme/vice_theme.dart';
import '../widgets/game_media_sheet.dart';
import '../widgets/media_card.dart';

/// Port of MainActivity.createLibraryContent + layoutMediaGridColumns:
/// a search box + Grid/Sort buttons row, a status line, then a GridView
/// whose column count comes from measured width / (card + margins), same
/// `cell = 126dp` constant the Android app uses, floor of 2 columns.
///
/// The library is browsed by TITLE, not by file format: an A-Z row across
/// the top jumps to a section of a large collection, matching Retro-Dosbox.
/// The old All/Disks/Tapes/Carts/PRG tabs are gone -- which format a title
/// happens to be stored in is a property of the file, not a way anybody
/// looks for a game. The card still shows the format, and the media type is
/// still what decides how the core is started.
class LibraryGrid extends StatefulWidget {
  final List<MediaEntry> allEntries;
  final void Function(MediaEntry entry) onLaunch;

  const LibraryGrid({
    super.key,
    required this.allEntries,
    required this.onLaunch,
  });

  @override
  State<LibraryGrid> createState() => _LibraryGridState();
}

class _LibraryGridState extends State<LibraryGrid> {
  String _search = '';

  /// null means "all letters". Otherwise the first character every shown
  /// title must start with, case-insensitive.
  String? _letterFilter;

  List<MediaEntry> get _filtered {
    final letter = _letterFilter;
    final entries = widget.allEntries.where((e) {
      if (letter != null && !_startsWith(e.displayName, letter)) return false;
      return _search.isEmpty ||
          e.displayName.toLowerCase().contains(_search.toLowerCase());
    }).toList();
    // Browsing by letter only means anything if the grid is in title order.
    entries.sort((a, b) =>
        a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()));
    return entries;
  }

  /// '#' is the catch-all bucket: digits and any other non-alphabetic first
  /// character. A tile per digit would dominate the row in a collection full
  /// of "1942", "720" and "007" without buying any useful filtering.
  static bool _isAlpha(String c) =>
      c.length == 1 && c.codeUnitAt(0) >= 0x61 && c.codeUnitAt(0) <= 0x7A;

  static bool _startsWith(String title, String letter) {
    final first = title.isEmpty ? '' : title[0].toLowerCase();
    return letter == '#' ? !_isAlpha(first) : first == letter;
  }

  /// Only the letters some title actually starts with, so no tile ever leads
  /// to an empty grid.
  List<String> get _presentLetters {
    final alpha = <String>{};
    var other = false;
    for (final e in widget.allEntries) {
      if (e.displayName.isEmpty) continue;
      final c = e.displayName[0].toLowerCase();
      if (_isAlpha(c)) {
        alpha.add(c);
      } else {
        other = true;
      }
    }
    return [
      if (other) '#',
      for (final l in 'abcdefghijklmnopqrstuvwxyz'.split(''))
        if (alpha.contains(l)) l,
    ];
  }

  Widget _letterRow() {
    return SizedBox(
      height: 26,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        children: [
          for (final l in _presentLetters) ...[
            _LetterChip(
              label: l == '#' ? '#' : l.toUpperCase(),
              selected: _letterFilter == l,
              onTap: () => setState(
                  () => _letterFilter = _letterFilter == l ? null : l),
            ),
            const SizedBox(width: 4),
          ],
          if (_letterFilter != null)
            _LetterChip(
              label: '\u00d7',
              selected: false,
              onTap: () => setState(() => _letterFilter = null),
              tooltip: 'Clear letter filter',
            ),
        ],
      ),
    );
  }

  /// Long-press on a tile: box art, screenshot, title screen and logo for
  /// that title, with Play still one tap away inside the sheet.
  void _showMedia(MediaEntry entry) {
    showGameMediaSheet(
      context,
      entry: entry,
      onPlay: () => widget.onLaunch(entry),
    );
  }

  @override
  Widget build(BuildContext context) {
    final entries = _filtered;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
          child: Text(
            'Game Library',
            style: const TextStyle(
                color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
          ),
        ),
        if (_presentLetters.length > 1) _letterRow(),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 4),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  onChanged: (v) => setState(() => _search = v),
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                  decoration: const InputDecoration(
                    hintText: 'Search games...',
                    hintStyle: TextStyle(color: ViceColors.sidebarLabelIdle),
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
          child: Text(
            widget.allEntries.isEmpty
                ? 'No C64 media found. Supported: PRG, P00, D64, G64, D71, D81, TAP, T64, CRT.'
                : '${entries.length} of ${widget.allEntries.length} files | IGDB deferred (placeholder tiles)',
            style: const TextStyle(color: ViceColors.textMuted2, fontSize: 12),
          ),
        ),
        Expanded(
          child: entries.isEmpty
              ? const Center(
                  child: Text('No media in this category.',
                      style: TextStyle(color: ViceColors.textMuted)))
              : LayoutBuilder(builder: (context, constraints) {
                  final cell = ViceMetrics.mediaCardCell;
                  final columns =
                      (constraints.maxWidth / cell).floor().clamp(2, 100);
                  final grid = SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: columns,
                    mainAxisExtent: ViceMetrics.mediaCardHeight + 6,
                  );

                  return GridView.builder(
                    padding: const EdgeInsets.all(8),
                    gridDelegate: grid,
                    itemCount: entries.length,
                    itemBuilder: (context, i) {
                      final entry = entries[i];
                      return Center(
                        child: MediaCard(
                          entry: entry,
                          onTap: () => widget.onLaunch(entry),
                          onShowMedia: () => _showMedia(entry),
                        ),
                      );
                    },
                  );
                }),
        ),
      ],
    );
  }
}

/// One letter tile in the A-Z row. Styled off the card chrome so the row
/// reads as part of the same shelf, with the teal accent marking the
/// active letter -- the same role the format tabs used to play.
class _LetterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final String? tooltip;

  const _LetterChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    final chip = Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Container(
          width: 26,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? ViceColors.selectedFill : ViceColors.cardFill,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: selected ? ViceColors.accentTeal : ViceColors.cardStroke,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
              color: selected
                  ? ViceColors.sidebarLabelSelected
                  : ViceColors.textMuted,
            ),
          ),
        ),
      ),
    );
    if (tooltip == null) return chip;
    return Tooltip(message: tooltip!, child: chip);
  }
}
