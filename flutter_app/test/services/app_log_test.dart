// The log a user sends in a bug report.
//
// Not tested here: the stdout/stderr redirect, which is real FFI against the
// process's own file descriptors -- doing that inside the test runner would
// swallow the runner's own output. Its behaviour is asserted on device
// instead, via the "native capture: on/off" line the log writes about itself.

import 'package:flutter_test/flutter_test.dart';
import 'package:vice_multiplatform/services/app_log.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('logging works before init, and loses nothing', () async {
    // init() needs a platform directory it cannot get in a test process, so
    // this is also the "init failed" path: the app must still be loggable,
    // because a logger that only works when everything works is no use.
    AppLog.log('before any init');
    final text = await AppLog.read();
    expect(text, contains('before any init'));
  });

  test('lines are timestamped so events can be ordered', () async {
    AppLog.log('ordered event');
    final text = await AppLog.read();
    final line =
        text.split('\n').firstWhere((l) => l.contains('ordered event'));
    // HH:MM:SS.mmm
    expect(RegExp(r'^\d{2}:\d{2}:\d{2}\.\d{3}\s').hasMatch(line), isTrue,
        reason: 'expected a leading timestamp, got: $line');
  });

  test('the in-memory log is bounded', () async {
    for (var i = 0; i < 2500; i++) {
      AppLog.log('filler $i');
    }
    final text = await AppLog.read();
    final lines = text.split('\n');
    // Bounded at 2000; a log that grows forever is a leak in a process that
    // runs for hours.
    expect(lines.length, lessThanOrEqualTo(2100));
    // And it keeps the NEWEST, which is the half a bug report needs.
    expect(text, contains('filler 2499'));
    expect(text, isNot(contains('filler 0\n')));
  });

  test('clear empties it', () async {
    AppLog.log('will be cleared');
    await AppLog.clear();
    final text = await AppLog.read();
    expect(text, isNot(contains('will be cleared')));
  });
}
