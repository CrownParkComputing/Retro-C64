import 'package:flutter/material.dart';

import '../data/category.dart';
import '../data/media_entry.dart';
import '../theme/vice_theme.dart';
import '../widgets/media_card.dart';

/// Port of MainActivity.createLibraryContent + layoutMediaGridColumns:
/// a search box + Grid/Sort buttons row, a status line, then a GridView
/// whose column count comes from measured width / (card + margins), same
/// `cell = 126dp` constant the Android app uses, floor of 2 columns.
///
/// The media-format filters (All/Disks/Tapes/Carts/PRG) are tabs across the
/// top of this view rather than sidebar destinations -- they are one
/// library seen through different filters, not different places to be.
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
  MediaTab _tab = MediaTab.all;

  List<MediaEntry> get _filtered {
    final filter = _tab.filter;
    return widget.allEntries.where((e) {
      final matchesFormat =
          filter == MediaFormatFilter.none || e.mediaType == filter;
      final matchesSearch = _search.isEmpty ||
          e.displayName.toLowerCase().contains(_search.toLowerCase());
      return matchesFormat && matchesSearch;
    }).toList();
  }

  /// How many entries a given tab would show, ignoring the search box --
  /// shown as a count pill so an empty tab is obviously empty rather than
  /// looking broken.
  int _countFor(MediaTab tab) => tab.filter == MediaFormatFilter.none
      ? widget.allEntries.length
      : widget.allEntries.where((e) => e.mediaType == tab.filter).length;

  Widget _tabBar() {
    return SizedBox(
      height: 38,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        children: [
          for (final tab in MediaTab.values)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: _MediaTabButton(
                label: tab.label,
                count: _countFor(tab),
                selected: tab == _tab,
                onTap: () => setState(() => _tab = tab),
              ),
            ),
        ],
      ),
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
            _tab.title,
            style: const TextStyle(
                color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
          ),
        ),
        _tabBar(),
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

                  // The "All" view is grouped by media type with section
                  // headers rather than one undifferentiated jumble -- the
                  // formats are still visibly separate even when you're
                  // looking at everything at once.
                  if (_tab == MediaTab.all) {
                    final slivers = <Widget>[];
                    for (final section in MediaTab.values) {
                      if (section == MediaTab.all) continue;
                      final rows = entries
                          .where((e) => e.mediaType == section.filter)
                          .toList();
                      if (rows.isEmpty) continue;
                      slivers.add(SliverToBoxAdapter(
                        child: _SectionHeader(
                            label: section.title, count: rows.length),
                      ));
                      slivers.add(SliverPadding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        sliver: SliverGrid(
                          gridDelegate: grid,
                          delegate: SliverChildBuilderDelegate(
                            (context, i) => Center(
                              child: MediaCard(
                                entry: rows[i],
                                onTap: () => widget.onLaunch(rows[i]),
                              ),
                            ),
                            childCount: rows.length,
                          ),
                        ),
                      ));
                    }
                    return CustomScrollView(
                      slivers: [
                        ...slivers,
                        const SliverToBoxAdapter(child: SizedBox(height: 12)),
                      ],
                    );
                  }

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

/// Section divider used by the grouped "All" view.
class _SectionHeader extends StatelessWidget {
  final String label;
  final int count;

  const _SectionHeader({required this.label, required this.count});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
      child: Row(
        children: [
          Text(
            label.toUpperCase(),
            style: const TextStyle(
              color: ViceColors.accentTeal,
              fontSize: 12,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(width: 8),
          Text('$count',
              style: const TextStyle(
                  color: ViceColors.textMuted, fontSize: 12)),
          const SizedBox(width: 10),
          const Expanded(child: Divider(color: ViceColors.cardStroke, height: 1)),
        ],
      ),
    );
  }
}

/// One media-format tab. Styled off the sidebar's selected-button chrome
/// (same fills/strokes from vice_theme) so the tabs read as the same app,
/// with the teal accent marking the active one.
class _MediaTabButton extends StatelessWidget {
  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  const _MediaTabButton({
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? ViceColors.selectedFill : ViceColors.cardFill,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: selected ? ViceColors.accentTeal : ViceColors.cardStroke,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                  color: selected
                      ? ViceColors.sidebarLabelSelected
                      : ViceColors.sidebarLabelIdle,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                '$count',
                style: TextStyle(
                  fontSize: 11,
                  color: selected ? ViceColors.accentTeal : ViceColors.textMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
