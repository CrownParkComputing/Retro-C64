import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vice_multiplatform/services/storage_access.dart';

void main() {
  test('Downloads is a search path on the desktop/Android platforms', () {
    final paths = defaultMediaSearchPaths();

    if (Platform.isIOS) {
      // The sandbox cannot read the Files app's Downloads, so offering a
      // path here would be a lie the scanner then fails to honour.
      expect(paths, isEmpty);
      return;
    }

    expect(paths, isNotEmpty,
        reason: 'every non-iOS platform has a Downloads directory worth '
            'looking in before asking the user to pick a folder');
    expect(
      paths.every((p) => p.toLowerCase().contains('download')),
      isTrue,
      reason: 'search paths are Downloads locations, not arbitrary dirs',
    );
  });

  test('firstExistingMediaSearchPath only ever returns a real directory', () {
    final found = firstExistingMediaSearchPath();
    if (found != null) {
      expect(Directory(found).existsSync(), isTrue);
    }
  });
}
