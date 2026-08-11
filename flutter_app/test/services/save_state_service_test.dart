// The resume list's bookkeeping. No native core is involved: the entries
// are plain data, and what matters is that an entry never claims to be
// resumable when the snapshot behind it is not there.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:vice_multiplatform/data/category.dart';
import 'package:vice_multiplatform/services/save_state_service.dart';

void main() {
  late Directory temp;

  setUp(() => temp = Directory.systemTemp.createTempSync('vice_savestate'));
  tearDown(() => temp.deleteSync(recursive: true));

  SaveStateEntry entry({
    String title = 'Boulder Dash.d64',
    String? snapshotPath,
    String? unsupportedReason,
    String? thumbnailPath,
    DateTime? savedAt,
  }) =>
      SaveStateEntry(
        title: title,
        mediaPath: '/games/$title',
        mediaType: MediaFormatFilter.disk,
        snapshotPath: snapshotPath,
        thumbnailPath: thumbnailPath,
        unsupportedReason: unsupportedReason,
        savedAt: savedAt ?? DateTime(2026, 8, 10, 12, 30),
      );

  group('canResume', () {
    test('is true only when the snapshot file is really on disk', () {
      final snapshot = File(p.join(temp.path, 'bd.vsf'))
        ..writeAsBytesSync([1, 2, 3]);
      expect(entry(snapshotPath: snapshot.path).canResume, isTrue);
    });

    test('is false when there never was a snapshot', () {
      // T64 tapes: VICE cannot snapshot them, so the row says RESTART.
      expect(
        entry(unsupportedReason: 'This title cannot be saved mid-game.')
            .canResume,
        isFalse,
      );
    });

    test('is false when the snapshot has been deleted underneath us', () {
      // The index is written once; the file can vanish at any time after.
      // Trusting the index here is how the UI ends up promising a resume it
      // cannot deliver.
      final path = p.join(temp.path, 'gone.vsf');
      expect(entry(snapshotPath: path).canResume, isFalse);
    });
  });

  group('index serialisation', () {
    test('round-trips every field', () {
      final original = entry(
        snapshotPath: '/state/bd.vsf',
        thumbnailPath: '/state/bd.png',
        savedAt: DateTime(2026, 1, 2, 3, 4, 5),
      );
      final restored =
          SaveStateEntry.fromJson(jsonDecode(jsonEncode(original.toJson())));

      expect(restored, isNotNull);
      expect(restored!.title, original.title);
      expect(restored.mediaPath, original.mediaPath);
      expect(restored.mediaType, MediaFormatFilter.disk);
      expect(restored.snapshotPath, '/state/bd.vsf');
      expect(restored.thumbnailPath, '/state/bd.png');
      expect(restored.savedAt, original.savedAt);
      expect(restored.unsupportedReason, isNull);
    });

    test('keeps the reason a restart-only entry exists', () {
      final original =
          entry(unsupportedReason: 'Tape images cannot be snapshotted.');
      final restored =
          SaveStateEntry.fromJson(jsonDecode(jsonEncode(original.toJson())))!;
      expect(restored.snapshotPath, isNull);
      expect(restored.unsupportedReason, 'Tape images cannot be snapshotted.');
      expect(restored.canResume, isFalse);
    });

    test('media type is stored by name, so reordering the enum is safe', () {
      expect(entry().toJson()['mediaType'], 'disk');
      final restored = SaveStateEntry.fromJson({
        'title': 'X',
        'mediaPath': '/x',
        'mediaType': 'tape',
        'savedAt': DateTime(2026).toIso8601String(),
      });
      expect(restored!.mediaType, MediaFormatFilter.tape);
    });

    test('an unreadable row is dropped rather than crashing the workbench',
        () {
      expect(SaveStateEntry.fromJson({'title': 'X'}), isNull);
      expect(
          SaveStateEntry.fromJson(
              {'title': 'X', 'mediaPath': '/x', 'savedAt': 'not a date'}),
          isNull);
      expect(
          SaveStateEntry.fromJson(
              {'title': 42, 'mediaPath': '/x', 'savedAt': '2026-01-01'}),
          isNull);
    });

    test('an unknown media type degrades to none instead of throwing', () {
      final restored = SaveStateEntry.fromJson({
        'title': 'X',
        'mediaPath': '/x',
        'mediaType': 'floppy-of-the-future',
        'savedAt': DateTime(2026).toIso8601String(),
      });
      expect(restored!.mediaType, MediaFormatFilter.none);
    });
  });

  test('the list is capped, so snapshots cannot grow without bound', () {
    // A C64 snapshot is a few hundred KB; the cap is what stops the state
    // directory growing for ever.
    expect(SaveStateService.maxEntries, greaterThan(0));
    expect(SaveStateService.maxEntries, lessThanOrEqualTo(10));
  });
}
