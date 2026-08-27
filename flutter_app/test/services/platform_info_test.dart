import 'dart:io';

import 'package:flutter/widgets.dart';
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

  test('an iPhone is not told to look under On My iPad', () {
    // Apple names the Files-app folder after the device, so instructions that
    // say iPad on a phone point at a heading that is not on screen. Every
    // iPhone, the Pro Max included, is under the 600dp tablet threshold.
    expect(isTabletSized(const Size(440, 956)), isFalse); // iPhone 17 Pro Max
    expect(isTabletSized(const Size(402, 874)), isFalse); // iPhone 17
    expect(isTabletSized(const Size(1032, 1376)), isTrue); // iPad Pro 13"
    expect(isTabletSized(const Size(744, 1133)), isTrue); // iPad mini
  });

  test('the threshold reads the shortest side, not the width', () {
    // A landscape iPad is still an iPad; a phone rotated is still a phone.
    expect(isTabletSized(const Size(956, 440)), isFalse);
    expect(isTabletSized(const Size(1376, 1032)), isTrue);
  });
}
