import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import 'package:retro_c64/ffi/vice_native_paths.dart';
import 'package:retro_c64/services/app_prefs.dart';
import 'setup_wizard_screen.dart' show kGamesImportSubdir;
import 'package:retro_c64/services/storage_access.dart';
import 'package:retro_c64/services/music_library.dart';
import 'package:retro_c64/services/service_locator.dart';
import 'package:retro_c64/services/vsid_service.dart';
import 'package:retro_c64/theme/vice_theme.dart';

/// Port of MainActivity.createMusicContent's Top-10 SID playlist: a grid
/// that fills the whole page (weight 1.0 -- explicitly NOT a side-by-side
/// layout, see the vice-android-porting skill's "UI layout rules").
///
/// Real SID playback is wired up via VsidService (lazily loads
/// libvicecore_vsid.so the first time a track is played -- see that file's
/// header for why it's lazy and why loading it alongside the already-loaded
/// game core is safe). Tapping a track plays it for real through ALSA;
/// tapping the play/pause pill actually pauses/resumes the vsid core.
///
/// Opening the tab starts the first available tune on its own ([_autoStart]);
/// a tap is only needed to choose a different one.
///
/// No graphic EQ (removed deliberately in an earlier pass) -- the "now
/// playing" indicator is a plain text/icon state driven by
/// vice_vsid_is_running() / a paused flag, not a fake animation.
class MusicScreen extends StatefulWidget {
  const MusicScreen({super.key});

  /// (title, artist, filename-within-the-music-folder). All 20 ship inside
  /// the app (see ViceNativePaths.extractBundledSidDir -- nothing is bundled
  /// now, the tunes that were there are commercial recordings), so
  /// the playlist works out of the box on every platform.
  /// The playlist lives in MusicLibrary now: the workbench starts tunes
  /// too, and two copies of the list is how the two screens end up
  /// disagreeing about what exists.
  static const List<(String, String, String)> playlist = MusicLibrary.playlist;


  @override
  State<MusicScreen> createState() => _MusicScreenState();
}

class _MusicScreenState extends State<MusicScreen> {
  final _vsid = getIt<VsidService>();

  bool _loading = true;

  /// Directories searched, in order, for each playlist filename. Normally
  /// [the user's Music/ folder if there is one, the bundled/extracted SID
  /// dir]; the bundled copy is always present so the Top-10 works out of
  /// the box on Android (where there is no user Music/ folder at all).
  List<String> _musicDirs = const [];
  /// The workbench-music switch, moved here from the Audio page. That page
  /// held exactly one control and it was about the tunes on THIS page, so it
  /// was a destination whose entire content belonged somewhere else.
  bool? _workbenchMusic;

  String? _nowPlayingTitle;
  String? _statusMessage;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _resolveMusicDir();
    getIt<AppPrefs>().getWorkbenchMusic().then((v) {
      if (mounted) setState(() => _workbenchMusic = v);
    });
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

  /// A user's own music folder -- a sibling `Music/` directory next to the
  /// configured Games folder (e.g. Games folder .../Vice/Games ->
  /// .../Vice/Music) -- still wins when it exists, so anyone who has
  /// curated their own copies keeps them. Below that come the SIDs imported
  /// through the normal importer, and finally the app's own SID folder.
  ///
  /// There is no bundled playlist any more: the twenty tunes that used to
  /// ship were commercial compositions and could not be redistributed, so
  /// the tab now plays what the user brings.
  Future<void> _resolveMusicDir() async {
    final dirs = <String>[];
    final gamesFolder = await getIt<AppPrefs>().getGamesFolderPath();
    if (gamesFolder != null) {
      final candidate = p.join(p.dirname(gamesFolder), 'Music');
      if (Directory(candidate).existsSync()) dirs.add(candidate);
    }
    // SIDs the user imported. They arrive through the same importer as
    // games (.sid is in kGameFileExtensions), so they land in the games
    // folder -- the Music tab has to look there or an imported tune is
    // invisible to the only screen that plays it.
    final importedDir =
        await getIt<StorageAccess>().importedDirPath(kGamesImportSubdir);
    if (importedDir != null && Directory(importedDir).existsSync()) {
      dirs.add(importedDir);
    }
    try {
      dirs.add(await ViceNativePaths.extractBundledSidDir());
    } catch (_) {
      // A missing SID folder just means there is nothing to fall back on;
      // any user folder found above still works.
    }
    if (!mounted) return;
    setState(() {
      _musicDirs = dirs;
      _loading = false;
    });
    await _autoStart();
  }

  /// Starts playing as soon as the tab is opened, instead of waiting for a
  /// tap.
  ///
  /// Opening a music player and getting silence reads as a broken player.
  /// Nothing on the grid says a tap is required, and on a fresh install most
  /// cards are greyed out anyway, so the one tune that *is* present can be
  /// anywhere among the twenty -- leaving the user to hunt for the one that
  /// makes a sound.
  ///
  /// Two things it must not do. It must not restart a tune that is already
  /// going: this widget is rebuilt from scratch every time the Music
  /// category is selected (see WorkbenchScreen's category switch), while the
  /// vsid core keeps playing across tab changes, so restarting here would
  /// jump back to bar one every time the user glanced at another tab. And it
  /// must not report an error when there is simply nothing to play -- the
  /// grid already shows every card as "not in your library", which says it
  /// better than a red status line would.
  ///
  /// That wording is deliberate. The cards are a catalogue of well-known
  /// tunes, not an offer: nothing here downloads anything, and these are
  /// commercial recordings whose composers hold the rights. "Not downloaded"
  /// read as though the app would fetch them given the chance.
  /// "20 tunes" was a claim about the catalogue, not about this device, so a
  /// player holding nothing still announced twenty of them. Says what is
  /// actually here.
  String _heading() {
    final total = MusicScreen.playlist.length;
    final have = MusicScreen.playlist
        .where((t) => _pathFor(t.$3) != null)
        .length;
    if (have == 0) return 'SID Workstation - no tunes in your library';
    if (have == total) return 'SID Workstation - $total tunes';
    return 'SID Workstation - $have of $total tunes';
  }

  Future<void> _autoStart() async {
    if (_vsid.currentPath != null) {
      // Already loaded from an earlier visit. Adopt it for the UI so the
      // status bar and the highlighted card match what is actually audible.
      final playing = _titleForPath(_vsid.currentPath!);
      if (playing != null && mounted) {
        setState(() => _nowPlayingTitle = playing);
      }
      return;
    }
    for (final (title, _, filename) in MusicScreen.playlist) {
      final path = _pathFor(filename);
      if (path != null) {
        await _tap(title, path);
        return;
      }
    }
  }

  /// The playlist title whose filename matches [path], if any -- used to
  /// re-attach the UI to a tune this widget did not itself start.
  String? _titleForPath(String path) {
    final name = p.basename(path);
    for (final (title, _, filename) in MusicScreen.playlist) {
      if (filename == name) return title;
    }
    return null;
  }

  String? _pathFor(String filename) {
    for (final dir in _musicDirs) {
      final path = p.join(dir, filename);
      if (File(path).existsSync()) return path;
    }
    return null;
  }

  Future<void> _tap(String title, String? path) async {
    if (path == null) {
      setState(() =>
          _statusMessage = '$title: not in your library -- import the .sid');
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
      color = ViceColors.accentCyan;
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

  /// Applies the change immediately as well as saving it. A music toggle
  /// that only takes effect next launch is a broken toggle: the whole point
  /// is that you flip it because you want silence *now*.
  Future<void> _setWorkbenchMusic(bool on) async {
    setState(() => _workbenchMusic = on);
    await getIt<AppPrefs>().setWorkbenchMusic(on);
    if (!on) {
      _vsid.pause();
      return;
    }
    if (_vsid.currentPath != null) {
      if (_vsid.isPaused) _vsid.togglePause();
      return;
    }
    final pick = MusicLibrary.firstAvailable(_musicDirs);
    if (pick == null) return;
    if (await _vsid.ensureLoaded()) _vsid.play(pick.$2);
  }

  Widget _workbenchMusicRow() {
    final on = _workbenchMusic;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: ViceColors.cardFill,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: ViceColors.cardStroke),
        ),
        // Stacked on a narrow screen, side by side otherwise.
        //
        // This blurb sits in the fixed part of the page, above the playlist's
        // Expanded. Beside the switch on a phone in portrait it was left
        // about 60pt to wrap 118 characters into -- a dozen-odd lines that
        // pushed the grid's share of the height below zero and overflowed the
        // page by 624px at 320pt. Full width it needs a third of that, and
        // the maxLines below is the hard stop either way.
        child: LayoutBuilder(
          builder: (context, constraints) {
            const blurb = Text(
              'Play a tune while you browse the workbench. Music always '
              'stops when a game launches, whatever this is set to.',
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: Colors.white70, fontSize: 12),
            );
            final toggle = Switch(
              value: on ?? true,
              activeThumbColor: ViceColors.accentCyan,
              onChanged: on == null ? null : _setWorkbenchMusic,
            );

            if (constraints.maxWidth < 360) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  blurb,
                  Align(alignment: Alignment.centerRight, child: toggle),
                ],
              );
            }
            return Row(
              children: [const Expanded(child: blurb), toggle],
            );
          },
        ),
      ),
    );
  }

  @override
  @override
  Widget build(BuildContext context) {
    // Slivers rather than Column+Expanded: the header is not a fixed height.
    // The blurb and the status line both wrap, and on a short narrow screen
    // they can want more than the whole viewport -- which left Expanded a
    // negative share and overflowed the page. SliverFillRemaining still hands
    // the playlist the rest of the viewport when there is a rest to hand it,
    // and the page simply scrolls when there is not.
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                child: Text(
                  _heading(),
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold),
                ),
              ),
              _workbenchMusicRow(),
              if (_loading)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child:
                      Text('Loading...', style: TextStyle(color: Colors.white38)),
                )
              else
                _statusBar(),
            ],
          ),
        ),
        // Playlist fills the rest of the page (weight 1.0, no side panel,
        // no EQ header eating vertical space).
        SliverFillRemaining(
          hasScrollBody: true,
          // Narrow cards, more columns: with 20 tunes the whole playlist has
          // to fit on one landscape screen without scrolling, so the cards
          // are sized from a ~150dp minimum width and a compact row height
          // rather than the old fixed 2-up 200dp/64dp cells.
          child: LayoutBuilder(builder: (context, constraints) {
            final columns = (constraints.maxWidth / 150).floor().clamp(2, 6);
            final rows = (MusicScreen.playlist.length / columns).ceil();
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
              itemCount: MusicScreen.playlist.length,
              itemBuilder: (context, i) {
                final (title, artist, filename) = MusicScreen.playlist[i];
                final path = _pathFor(filename);
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
                                ? ViceColors.accentCyan
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
                                  const Icon(Icons.graphic_eq, color: ViceColors.accentCyan, size: 14)
                                else if (paused)
                                  const Icon(Icons.pause, color: Colors.orangeAccent, size: 14)
                                // Deliberately NO icon for an absent tune. It
                                // used to be Icons.download_outlined, which
                                // said the opposite of what the card means:
                                // these are commercial recordings the app does
                                // not ship and will not fetch, and a download
                                // glyph on twenty named Hubbard and Galway
                                // titles reads as an offer to get them. The
                                // dimmed card and "(not in your library)"
                                // already carry it.
                              ],
                            ),
                            Text(
                              available ? artist : '$artist (not in your library)',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  color: available
                                      ? ViceColors.accentCyan
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
