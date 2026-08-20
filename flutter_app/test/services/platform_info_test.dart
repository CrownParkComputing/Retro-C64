import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:retro_c64/services/platform_info.dart';

void main() {
  test('names the OS this copy is actually running on', () {
    // Whatever host runs the suite, the answer must be that host -- the
    // point of this function is that nothing anywhere hardcodes a platform
    // name (the screensaver scroller used to say "VICE ANDROID" on Linux).
    const expected = {
      'linux': 'Linux',
      'android': 'Android',
      'ios': 'iOS',
      'macos': 'macOS',
      'windows': 'Windows',
    };
    expect(platformName(),
        expected[Platform.operatingSystem] ?? 'this platform');
  });

  test('always returns something printable', () {
    expect(platformName(), isNotEmpty);
    expect(platformName(), isNot(contains('multiplatform')));
  });
}
