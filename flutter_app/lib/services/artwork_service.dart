import 'dart:io';

import 'package:archive/archive.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import '../ffi/vice_native_paths.dart';

/// The images a game pack contains, once extracted.
///
/// Any of these can be null: a pack only carries what the media set actually
/// had for that title, and a game with no 3D box render still gets its wheel
/// logo and screenshot.
class GameArtwork {
  /// 3D box render -- the default tile in the games grid.
  final File? box3d;

  /// Transparent logo, for headers and the screensaver.
  final File? wheel;

  /// Title screen grab.
  final File? title;

  /// In-game screenshot.
  final File? thumb;

  const GameArtwork({this.box3d, this.wheel, this.title, this.thumb});

  bool get isEmpty =>
      box3d == null && wheel == null && title == null && thumb == null;

  /// Everything present, in the order the detail view should show it.
  List<({String label, File file})> get all => [
        if (box3d != null) (label: 'Box', file: box3d!),
        if (thumb != null) (label: 'Screenshot', file: thumb!),
        if (title != null) (label: 'Title screen', file: title!),
        if (wheel != null) (label: 'Logo', file: wheel!),
      ];
}

/// Fetches and caches per-game artwork packs.
///
/// One zip per title, named by slug (see tools/build-art-packs.sh), holding a
/// handful of WebP images. A pack is downloaded once, extracted into the
/// app's support directory and read from disk forever after -- the grid must
/// not hit the network to draw itself.
///
/// Everything here fails soft. Artwork is decoration: no host configured, no
/// network, a 404 for an obscure title, a corrupt zip -- all of them mean
/// "no picture", never an error in the user's way.
class ArtworkService {
  ArtworkService._();

  /// Where the packs are served from. Set to your own host; until then the
  /// grid simply keeps its placeholder tiles.
  ///
  /// Expected layout: `<base>/<slug>.zip`, e.g. `<base>/outrun.zip`.
  static String? baseUrl;

  /// Titles already looked for and not found, so a missing pack costs one
  /// request per session rather than one per rebuild of the grid.
  static final Set<String> _misses = <String>{};

  /// In-flight and completed lookups, keyed by slug. Without this a grid of
  /// twenty tiles building at once would start twenty identical downloads.
  static final Map<String, Future<GameArtwork?>> _inFlight = {};

  /// Lowercase, letters and digits only.
  ///
  /// Both sides derive this independently -- the pack builder from the media
  /// set's display title ("Out Run"), the app from its own filename
  /// ("outrun.prg") -- and they meet at "outrun" without either needing a
  /// lookup table.
  static String slugFor(String displayName) {
    final withoutExtension = p.basenameWithoutExtension(displayName);
    return withoutExtension.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
  }

  static Future<Directory> _cacheDir() async {
    final dir = Directory(p.join(await ViceNativePaths.supportDirPath(), 'artwork'));
    if (!dir.existsSync()) await dir.create(recursive: true);
    return dir;
  }

  /// Artwork for [displayName], from cache if present, else downloaded.
  ///
  /// Returns null when there is nothing to show.
  static Future<GameArtwork?> artworkFor(String displayName) {
    final slug = slugFor(displayName);
    if (slug.isEmpty || _misses.contains(slug)) return Future.value(null);
    return _inFlight.putIfAbsent(slug, () => _resolve(slug));
  }

  static Future<GameArtwork?> _resolve(String slug) async {
    try {
      final dir = Directory(p.join((await _cacheDir()).path, slug));
      if (dir.existsSync()) {
        final cached = _read(dir);
        if (!cached.isEmpty) return cached;
      }

      final base = baseUrl;
      if (base == null || base.isEmpty) {
        _misses.add(slug);
        return null;
      }

      final uri = Uri.parse('${base.replaceAll(RegExp(r'/+$'), '')}/$slug.zip');
      final response = await http.get(uri).timeout(const Duration(seconds: 20));
      if (response.statusCode != 200 || response.bodyBytes.isEmpty) {
        _misses.add(slug);
        return null;
      }

      await dir.create(recursive: true);
      for (final entry in ZipDecoder().decodeBytes(response.bodyBytes)) {
        if (!entry.isFile) continue;
        // Flatten and sanitise: a pack is a flat set of images, and a name
        // with a path in it has no business escaping this directory.
        final name = p.basename(entry.name);
        if (name.isEmpty || name.startsWith('.')) continue;
        await File(p.join(dir.path, name)).writeAsBytes(
          entry.content as List<int>,
          flush: true,
        );
      }

      final artwork = _read(dir);
      if (artwork.isEmpty) {
        _misses.add(slug);
        return null;
      }
      return artwork;
    } catch (_) {
      // Offline, DNS failure, corrupt zip, unwritable directory -- all the
      // same outcome as far as the grid is concerned.
      _misses.add(slug);
      return null;
    }
  }

  static GameArtwork _read(Directory dir) {
    File? pick(String name) {
      final file = File(p.join(dir.path, '$name.webp'));
      return file.existsSync() ? file : null;
    }

    return GameArtwork(
      box3d: pick('box3d'),
      wheel: pick('wheel'),
      title: pick('title'),
      thumb: pick('thumb'),
    );
  }

  /// Forgets negative results, so a newly-configured host is retried without
  /// restarting the app.
  static void clearMisses() {
    _misses.clear();
    _inFlight.clear();
  }
}
