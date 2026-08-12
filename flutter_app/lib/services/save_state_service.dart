// Save states: the last few titles the user played, each with a real VICE
// machine snapshot so they resume at the exact cycle they were left at.
//
// The snapshot itself is written by the native core (see
// vice_core_save_snapshot in native/vice_core/bridge/vice_bridge.c, which
// hands the request to the core's own thread -- VICE machine state must
// never be touched from the Flutter thread). Everything in this file is the
// bookkeeping around that: where the files live, the index that maps them
// back to a title, the 5-entry cap, and the PNG thumbnail.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

import 'package:path/path.dart' as p;

import '../data/category.dart';
import '../ffi/vice_bindings.dart';
import '../ffi/vice_core.dart';
import '../ffi/vice_native_paths.dart';

/// One resumable session.
class SaveStateEntry {
  /// Display name of the title, e.g. "1942.D64".
  final String title;

  /// The original media file, kept so a session whose snapshot has gone bad
  /// can still be relaunched from scratch rather than just failing.
  final String mediaPath;

  /// Index into [MediaFormatFilter], stored as a name so the file stays
  /// readable and survives enum reordering.
  final MediaFormatFilter mediaType;

  /// Absolute path to the .vsf snapshot, or null if this title could not be
  /// snapshotted at all (see [unsupportedReason]). A null here is the whole
  /// reason the type is nullable: the alternative was writing a snapshot we
  /// knew would not restore, which is how the resume list ends up promising
  /// something it cannot deliver.
  final String? snapshotPath;

  /// Absolute path to the PNG thumbnail, or null if none was captured.
  final String? thumbnailPath;

  /// Why no snapshot exists, in words fit to show the user. Null when there
  /// is a snapshot.
  final String? unsupportedReason;

  /// When the session was saved.
  final DateTime savedAt;

  const SaveStateEntry({
    required this.title,
    required this.mediaPath,
    required this.mediaType,
    required this.savedAt,
    this.snapshotPath,
    this.thumbnailPath,
    this.unsupportedReason,
  });

  bool get snapshotExists {
    final path = snapshotPath;
    return path != null && File(path).existsSync();
  }

  /// True only when tapping this really does put the user back where they
  /// were. When false the UI must say "Restart", not "Resume".
  bool get canResume => snapshotExists;

  Map<String, dynamic> toJson() => {
        'title': title,
        'mediaPath': mediaPath,
        'mediaType': mediaType.name,
        'snapshotPath': snapshotPath,
        'thumbnailPath': thumbnailPath,
        'unsupportedReason': unsupportedReason,
        'savedAt': savedAt.toIso8601String(),
      };

  static SaveStateEntry? fromJson(Map<String, dynamic> json) {
    final title = json['title'];
    final mediaPath = json['mediaPath'];
    final savedAt = DateTime.tryParse(json['savedAt'] as String? ?? '');
    if (title is! String || mediaPath is! String || savedAt == null) {
      return null;
    }
    return SaveStateEntry(
      title: title,
      mediaPath: mediaPath,
      mediaType: MediaFormatFilter.values.firstWhere(
        (v) => v.name == json['mediaType'],
        orElse: () => MediaFormatFilter.none,
      ),
      snapshotPath: json['snapshotPath'] as String?,
      thumbnailPath: json['thumbnailPath'] as String?,
      unsupportedReason: json['unsupportedReason'] as String?,
      savedAt: savedAt,
    );
  }
}

class SaveStateService {
  SaveStateService._();

  /// How many sessions are kept. Older ones are evicted, snapshot and
  /// thumbnail files included -- a C64 snapshot is ~200KB-800KB, so an
  /// uncapped list would quietly grow without bound.
  static const int maxEntries = 5;

  static const String _indexFileName = 'index.json';

  static Directory? _dir;

  static Future<Directory> _stateDir() async {
    final cached = _dir;
    if (cached != null) return cached;
    // ViceNativePaths, not path_provider directly: its Apple implementation
    // fails to load in this build, and going through it here meant every
    // save silently failed on iOS.
    final support = await ViceNativePaths.supportDirPath();
    final dir = Directory(p.join(support, 'savestates'));
    if (!dir.existsSync()) {
      await dir.create(recursive: true);
    }
    _dir = dir;
    return dir;
  }

  static Future<File> _indexFile() async =>
      File(p.join((await _stateDir()).path, _indexFileName));

  /// All saved sessions, newest first.
  ///
  /// Entries with no usable snapshot are KEPT, not dropped: the user still
  /// played the title and still wants it in this list. They come back with
  /// [SaveStateEntry.canResume] false, and the screen labels them "Restart"
  /// so nothing is promised that cannot be delivered. Dropping them was the
  /// older behaviour and it made a title the emulator genuinely cannot
  /// snapshot simply vanish, with no explanation anywhere.
  static Future<List<SaveStateEntry>> list() async {
    final file = await _indexFile();
    if (!file.existsSync()) return const [];
    try {
      final raw = jsonDecode(await file.readAsString());
      if (raw is! List) return const [];
      final entries = raw
          .whereType<Map<String, dynamic>>()
          .map(SaveStateEntry.fromJson)
          .whereType<SaveStateEntry>()
          .toList()
        ..sort((a, b) => b.savedAt.compareTo(a.savedAt));
      return entries;
    } catch (_) {
      // A corrupt index is not worth crashing the workbench over; the user
      // loses their resume list, which is recoverable by playing again.
      return const [];
    }
  }

  static Future<void> _writeIndex(List<SaveStateEntry> entries) async {
    final file = await _indexFile();
    await file.writeAsString(
      jsonEncode(entries.map((e) => e.toJson()).toList()),
      flush: true,
    );
  }

  /// Captures the running core's state for a title.
  ///
  /// Returns the new entry, which may be a *restart-only* entry
  /// ([SaveStateEntry.canResume] false) when the core could not produce a
  /// snapshot that would restore. Returns null only when there is nothing to
  /// record at all, i.e. the core is not running.
  ///
  /// A failed snapshot deliberately still produces an entry. The user played
  /// the title and expects to find it in Resume; what changes is that the
  /// entry says Restart and carries the reason, instead of the title silently
  /// disappearing from the list (old behaviour) or -- worse -- appearing with
  /// a snapshot that resumes into a corrupt machine.
  ///
  /// One snapshot per title: re-playing a game replaces its previous save
  /// rather than filling the 5 slots with the same name.
  static Future<SaveStateEntry?> capture({
    required ViceCore core,
    required String title,
    required String mediaPath,
    required MediaFormatFilter mediaType,
  }) async {
    if (!core.isRunning) return null;

    final dir = await _stateDir();
    final slug = _slug(title);
    final snapshotPath = p.join(dir.path, '$slug.vsf');

    // Thumbnail first: it reads the framebuffer, which is cheap and must
    // reflect the same moment the snapshot captures.
    final thumbnailPath = await _writeThumbnail(core, p.join(dir.path, '$slug.png'));

    final result = core.saveSnapshot(snapshotPath);
    String? unsupportedReason;
    if (result != 0) {
      unsupportedReason = switch (result) {
        ViceSnapshotResult.unsupportedMedia =>
          'This title\'s media cannot be saved mid-game by the emulator core, '
              'so there is no state to return to.',
        ViceSnapshotResult.timeout =>
          'The emulator core did not respond in time while saving.',
        _ => 'The emulator core could not write a save state (error $result).',
      };
      // Any earlier .vsf for this title is now stale -- it belongs to a
      // different session than the thumbnail beside it. Leaving it would let
      // a later Resume drop the user into a machine state they never asked
      // for, which is the exact class of lie this change exists to remove.
      final stale = File(snapshotPath);
      if (stale.existsSync()) {
        try {
          await stale.delete();
        } catch (_) {
          // Best effort; canResume rechecks existence at list() time anyway.
        }
      }
    }

    final entry = SaveStateEntry(
      title: title,
      mediaPath: mediaPath,
      mediaType: mediaType,
      snapshotPath: unsupportedReason == null ? snapshotPath : null,
      thumbnailPath: thumbnailPath,
      unsupportedReason: unsupportedReason,
      savedAt: DateTime.now(),
    );

    final existing = await list();
    final kept = <SaveStateEntry>[
      entry,
      ...existing.where((e) => _slug(e.title) != slug),
    ];
    final evicted = kept.skip(maxEntries).toList();
    final retained = kept.take(maxEntries).toList();
    for (final old in evicted) {
      await _deleteFiles(old);
    }
    await _writeIndex(retained);
    return entry;
  }

  /// Removes a session and its files.
  static Future<void> remove(SaveStateEntry entry) async {
    await _deleteFiles(entry);
    // Keyed on the title slug, not on snapshotPath: a restart-only entry has
    // no snapshotPath, and matching null against null would have deleted
    // every such entry at once.
    final slug = _slug(entry.title);
    final remaining =
        (await list()).where((e) => _slug(e.title) != slug).toList();
    await _writeIndex(remaining);
  }

  static Future<void> _deleteFiles(SaveStateEntry entry) async {
    for (final path in [entry.snapshotPath, entry.thumbnailPath]) {
      if (path == null) continue;
      final file = File(path);
      if (file.existsSync()) {
        try {
          await file.delete();
        } catch (_) {
          // Best effort -- a leftover file costs disk, not correctness.
        }
      }
    }
  }

  /// Forgets the cached state directory so a test can point the service at
  /// a fresh temp directory. Not used by the app.
  @visibleForTesting
  static void resetForTests() => _dir = null;

  /// Encodes the current framebuffer as a PNG next to the snapshot.
  /// Returns the path, or null if there was no frame to capture or the
  /// encode failed -- the resume list falls back to an icon in that case.
  static Future<String?> _writeThumbnail(
      ViceCore core, String outPath) async {
    try {
      final frame = core.getFramebuffer();
      if (frame == null) return null;
      final bytes = Uint8List.view(
        frame.argbAsRgba.buffer,
        frame.argbAsRgba.offsetInBytes,
        frame.argbAsRgba.lengthInBytes,
      );
      final image = await _decode(bytes, frame.width, frame.height);
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      if (png == null) return null;
      await File(outPath).writeAsBytes(png.buffer.asUint8List(), flush: true);
      return outPath;
    } catch (_) {
      return null;
    }
  }

  static Future<ui.Image> _decode(Uint8List bytes, int width, int height) {
    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      bytes,
      width,
      height,
      ui.PixelFormat.rgba8888,
      completer.complete,
    );
    return completer.future;
  }

  /// Filesystem-safe stable name for a title, so the same game always
  /// overwrites its own slot.
  static String _slug(String title) {
    final cleaned = title.replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '_');
    return cleaned.isEmpty ? 'untitled' : cleaned;
  }
}
