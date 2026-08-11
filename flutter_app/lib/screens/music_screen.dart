import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../ffi/vice_native_paths.dart';
import '../services/app_prefs.dart';
import '../services/storage_access.dart';
import '../services/vsid_service.dart';
import '../theme/vice_theme.dart';
import 'setup_wizard_screen.dart' show kGamesImportSubdir;

/// One card in the playlist: the bundled Top-20 with their known titles and
/// composers, plus every .sid the user has of their own.
class SidTrack {
  final String title;
  final String artist;

  /// Null only for a bundled tune whose file isn't on disk (extraction
  /// failed) -- that card renders greyed out, as it always has.
  final String? path;

  const SidTrack(this.title, this.artist, this.path);
}

/// Port of MainActivity.createMusicContent's Top-10 SID playlist: a grid
/// that fills the whole page (weight 1.0 -- explicitly NOT a side-by-side
/// layout, see the vice-android-porting skill's "UI layout rules").
///
/// Real SID playback is wired up via VsidService (lazily loads
/// libvicecore_vsid.so the first time a track is tapped -- see that file's
/// header for why it's lazy and why loading it alongside the already-loaded
/// game core is safe). Tapping a track plays it for real through ALSA;
/// tapping the play/pause pill actually pauses/resumes the vsid core.
///
/// No graphic EQ (removed deliberately in an earlier pass) -- the "now
/// playing" indicator is a plain text/icon state driven by
/// vice_vsid_is_running() / a paused flag, not a fake animation.
class MusicScreen extends StatefulWidget {
  const MusicScreen({super.key});

  /// (title, artist, filename-within-the-music-folder). All 20 ship inside
  /// the app as assets/sids/ (see ViceNativePaths.extractBundledSidDir), so
  /// the playlist works out of the box on every platform.
  static const List<(String, String, String)> playlist = [
    ('Commando', 'Rob Hubbard', 'Commando.sid'),
    ('Arkanoid', 'Martin Galway', 'Arkanoid.sid'),
    ('Monty on the Run', 'Rob Hubbard', 'Monty_on_the_Run.sid'),
    ('Delta', 'Rob Hubbard', 'Delta.sid'),
    ('Sanxion', 'Rob Hubbard', 'Sanxion.sid'),
    ('Spellbound', 'Rob Hubbard', 'Spellbound.sid'),
    ('International Karate', 'Rob Hubbard', 'International_Karate.sid'),
    ('Warhawk', 'Rob Hubbard', 'Warhawk.sid'),
    ('The Last V8', 'Rob Hubbard', 'Last_V8.sid'),
    ('Cybernoid II', 'Jeroen Tel', 'Cybernoid_II.sid'),
    ('Lightforce', 'Rob Hubbard', 'Lightforce.sid'),
    ('Thing on a Spring', 'Rob Hubbard', 'Thing_on_a_Spring.sid'),
    ('Crazy Comets', 'Rob Hubbard', 'Crazy_Comets.sid'),
    ('Zoids', 'Rob Hubbard', 'Zoids.sid'),
    ('Auf Wiedersehen Monty', 'Rob Hubbard', 'Auf_Wiedersehen_Monty.sid'),
    ('Nemesis the Warlock', 'Rob Hubbard', 'Nemesis_the_Warlock.sid'),
    ('Comic Bakery', 'Martin Galway', 'Comic_Bakery.sid'),
    ('Wizball', 'Martin Galway', 'Wizball.sid'),
    ('Parallax', 'Martin Galway', 'Parallax.sid'),
    ('Rambo: First Blood Part II', 'Martin Galway', 'Rambo_First_Blood_Part_II.sid'),
  ];

  @override
  State<MusicScreen> createState() => _MusicScreenState();
}

class _MusicScreenState extends State<MusicScreen> {
  final _vsid = VsidService.instance;

  bool _loading = true;

  /// The playlist as shown: the bundled tunes first, then the user's own.
  List<SidTrack> _tracks = const [];
  String? _nowPlayingTitle;
  String? _statusMessage;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _loadTracks();
    // Polls the real vsid state twice a second so the "PLAYING"/"PAUSED"
    // text and audio-level readout reflect what the native core is
    // actually doing, not just what button was last tapped.
    _pollTimer = Timer.periodic(const Duration(milliseconds: 300), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  /// Builds the playlist out of every place a .sid can come from:
  ///
  ///  - a sibling `Music/` directory next to the configured Games folder
  ///    (e.g. .../Vice/Games -> .../Vice/Music), for anyone who curates
  ///    their own collection on desktop;
  ///  - the import directory, which is where iOS puts everything the user
  ///    imports (there is no folder to point at on that platform);
  ///  - the bundled Top-20 extracted from the app's own assets, which is
  ///    what makes the playlist work out of the box everywhere.
  ///
  /// The bundled tunes keep their known titles and composers. Everything
  /// else found in those directories is listed after them under its own
  /// filename -- importing a .sid is all it takes to have it playable here.
  Future<void> _loadTracks() async {
    final dirs = <String>[];
    final gamesFolder = await AppPrefs.getGamesFolderPath();
    if (gamesFolder != null) {
      final candidate = p.join(p.dirname(gamesFolder), 'Music');
      if (Directory(candidate).existsSync()) dirs.add(candidate);
    }
    final importDir =
        await StorageAccess.instance.importedDirectory(kGamesImportSubdir);
    if (importDir != null) dirs.add(importDir);
    try {
      dirs.add(await ViceNativePaths.extractBundledSidDir());
    } catch (_) {
      // Extraction failure just means the bundled fallback is unavailable;
      // any user folder found above still works.
    }

    String? pathFor(String filename) {
      for (final dir in dirs) {
        final path = p.join(dir, filename);
        if (File(path).existsSync()) return path;
      }
      return null;
    }

    final tracks = <SidTrack>[];
    final bundledNames = <String>{};
    for (final (title, artist, filename) in MusicScreen.playlist) {
      bundledNames.add(filename.toLowerCase());
      tracks.add(SidTrack(title, artist, pathFor(filename)));
    }

    final seen = <String>{};
    final own = <SidTrack>[];
    for (final dir in dirs) {
      final directory = Directory(dir);
      if (!directory.existsSync()) continue;
      for (final file in directory.listSync(recursive: true, followLinks: false)) {
        if (file is! File) continue;
        if (p.extension(file.path).toLowerCase() != '.sid') continue;
        final name = p.basename(file.path);
        final key = name.toLowerCase();
        // The bundled twenty are already listed with better metadata, and
        // the same tune found in two directories is still one tune.
        if (bundledNames.contains(key) || !seen.add(key)) continue;
        own.add(SidTrack(_titleFromFilename(name), 'Imported', file.path));
      }
    }
    own.sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));

    if (!mounted) return;
    setState(() {
      _tracks = [...tracks, ...own];
      _loading = false;
    });
  }

  /// "Comic_Bakery.sid" -> "Comic Bakery". A filename is all the metadata
  /// an imported SID comes with; the header is not parsed (yet).
  static String _titleFromFilename(String filename) {
    final stem = p.basenameWithoutExtension(filename).replaceAll('_', ' ').trim();
    return stem.isEmpty ? filename : stem;
  }

  Future<void> _tap(String title, String? path) async {
    if (path == null) {
      setState(() => _statusMessage = '$title: SID file not downloaded');
      return;
    }
    if (!await _vsid.ensureLoaded()) {
      if (!mounted) return;
      setState(() =>
          _statusMessage = 'SID player unavailable: ${_vsid.loadError}');
      return;
    }
    if (!mounted) return;
    if (_nowPlayingTitle == title && _vsid.currentPath == path) {
      // Already the loaded tune -- treat a re-tap as play/pause toggle.
      _vsid.togglePause();
      setState(() => _statusMessage = null);
      return;
    }
    final ok = _vsid.play(path);
    setState(() {
      _statusMessage = ok ? null : 'Failed to play $title';
      _nowPlayingTitle = ok ? title : _nowPlayingTitle;
    });
  }

  Widget _statusBar() {
    final playing = _nowPlayingTitle != null && _vsid.isRunning;
    final paused = _vsid.isPaused;
    String label;
    IconData icon;
    Color color;
    if (_nowPlayingTitle == null) {
      label = 'No track loaded';
      icon = Icons.music_off;
      color = Colors.white38;
    } else if (paused) {
      label = 'PAUSED -- $_nowPlayingTitle';
      icon = Icons.pause_circle_filled;
      color = Colors.orangeAccent;
    } else if (playing) {
      label = 'PLAYING -- $_nowPlayingTitle  (level ${_vsid.audioLevel})';
      icon = Icons.graphic_eq;
      color = ViceColors.accentTeal;
    } else {
      label = 'Stopped';
      icon = Icons.stop_circle;
      color = Colors.white38;
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _statusMessage ?? label,
              style: TextStyle(
                  color: _statusMessage != null ? Colors.redAccent : color,
                  fontSize: 13,
                  fontWeight: FontWeight.w600),
            ),
          ),
          if (_nowPlayingTitle != null)
            IconButton(
              tooltip: paused ? 'Resume' : 'Pause',
              icon: Icon(paused ? Icons.play_arrow : Icons.pause,
                  color: Colors.white),
              onPressed: () => setState(() => _vsid.togglePause()),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
          child: Text(
            'SID Workstation - ${_tracks.length} tunes',
            style: const TextStyle(
                color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
          ),
        ),
        if (_loading)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Text('Loading...', style: TextStyle(color: Colors.white38)),
          )
        else
          _statusBar(),
        // Playlist fills the rest of the page (weight 1.0, no side panel,
        // no EQ header eating vertical space).
        Expanded(
          // Narrow cards, more columns: with 20 tunes the whole playlist has
          // to fit on one landscape screen without scrolling, so the cards
          // are sized from a ~150dp minimum width and a compact row height
          // rather than the old fixed 2-up 200dp/64dp cells.
          child: LayoutBuilder(builder: (context, constraints) {
            final columns = (constraints.maxWidth / 150).floor().clamp(2, 6);
            final rows = (_tracks.length / columns).ceil().clamp(1, 1 << 30);
            // Shrink rows to fit the available height when they otherwise
            // wouldn't, with a floor that still leaves the two text lines
            // room.
            final available = constraints.maxHeight - 16 - (rows - 1) * 6;
            final rowHeight = (available / rows).clamp(44.0, 56.0);
            return GridView.builder(
              padding: const EdgeInsets.all(8),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: columns,
                mainAxisExtent: rowHeight,
                crossAxisSpacing: 6,
                mainAxisSpacing: 6,
              ),
              itemCount: _tracks.length,
              itemBuilder: (context, i) {
                final track = _tracks[i];
                final title = track.title;
                final artist = track.artist;
                final path = track.path;
                final available = path != null;
                final playing = title == _nowPlayingTitle && _vsid.isRunning;
                final paused = title == _nowPlayingTitle && _vsid.isPaused;
                return Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: _loading ? null : () => _tap(title, path),
                    borderRadius: BorderRadius.circular(8),
                    child: Opacity(
                      opacity: available ? 1.0 : 0.4,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: ViceColors.sidCardFill,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: playing
                                ? ViceColors.accentTeal
                                : paused
                                    ? Colors.orangeAccent
                                    : ViceColors.sidCardStroke,
                            width: playing || paused ? 2 : 1,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 12)),
                                ),
                                if (playing)
                                  const Icon(Icons.graphic_eq, color: ViceColors.accentTeal, size: 14)
                                else if (paused)
                                  const Icon(Icons.pause, color: Colors.orangeAccent, size: 14)
                                else if (!available)
                                  const Icon(Icons.download_outlined, color: Colors.white38, size: 14),
                              ],
                            ),
                            Text(
                              available ? artist : '$artist (not downloaded)',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  color: available
                                      ? ViceColors.accentTeal
                                      : Colors.white38,
                                  fontSize: 10),
                            ),
                          ],
                        ),
                      ),
                    ),
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
