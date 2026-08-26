// A log the user can actually send you.
//
// Two separate problems this solves, and they need different machinery.
//
// The Dart side can log to memory easily enough. The NATIVE core cannot: the
// bridge writes with printf/LOGI, which on Android lands in logcat (fine, adb
// reads it) but on iOS goes to stdout -- and stdout is not os_log, so it
// reaches nothing. Capturing 14,000 lines of device log while a disk image
// failed produced no VICE output at all, which is why "?DEVICE NOT PRESENT"
// could not be diagnosed on an iPad. So stdout and stderr are redirected, at
// the file-descriptor level, into a file the app can read back.
//
// The log lives in DOCUMENTS, not application-support, and that is the point:
// on iOS the app declares UIFileSharingEnabled, so Documents shows up in the
// Files app. A user can therefore reach the file and mail it. A log the user
// cannot get at is not a bug report.
import 'dart:async';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:path/path.dart' as p;

import 'package:retro_c64/ffi/vice_native_paths.dart';

typedef _OpenNative = Int32 Function(Pointer<Utf8>, Int32, Int32);
typedef _OpenDart = int Function(Pointer<Utf8>, int, int);
typedef _Dup2Native = Int32 Function(Int32, Int32);
typedef _Dup2Dart = int Function(int, int);
typedef _SetvbufNative = Int32 Function(Pointer<Void>, Pointer<Utf8>, Int32, IntPtr);
typedef _SetvbufDart = int Function(Pointer<Void>, Pointer<Utf8>, int, int);

class AppLog {
  AppLog._();

  /// Lines logged from Dart this session. Bounded: a log that grows without
  /// limit is a memory leak in a process that can run for hours.
  static final List<String> _lines = <String>[];
  static const int _maxLines = 2000;

  static String? _filePath;
  static bool _nativeRedirected = false;

  /// Where the log file lives, once [init] has run.
  static String? get filePath => _filePath;

  static bool get nativeCaptureActive => _nativeRedirected;

  /// Sets up the log file and starts capturing native output.
  ///
  /// Safe to call more than once and safe to fail: logging is diagnostics,
  /// and an app that will not start because its logger did not is a worse
  /// bug than the one being diagnosed.
  static Future<void> init() async {
    try {
      final dir = Platform.isIOS
          ? await ViceNativePaths.iosDocumentsDirPath()
          : await ViceNativePaths.supportDirPath();
      final path = p.join(dir, 'c64retro-log.txt');
      final file = File(path);
      // Start each run from empty. A log that spans sessions buries the run
      // the user is actually reporting, and rotation is more machinery than
      // this needs.
      await file.writeAsString(
        '=== Retro-64 log -- ${DateTime.now().toIso8601String()} ===\n'
        'platform: ${Platform.operatingSystem} '
        '${Platform.operatingSystemVersion}\n',
      );
      _filePath = path;
      _redirectNativeOutput(path);
    } catch (e) {
      // Keep the in-memory log; only the file and native capture are lost.
      _append('AppLog.init failed: $e');
    }
    log('log started; native capture: '
        '${_nativeRedirected ? "on" : "off"}; file: ${_filePath ?? "none"}');
  }

  /// Points the process's stdout and stderr at the log file.
  ///
  /// Done with dup2 on the file descriptors rather than freopen, because that
  /// catches everything writing to fd 1/2 -- the VICE core's own printf and
  /// log_message included -- without the core having to cooperate or be
  /// rebuilt.
  ///
  /// stdout is then made unbuffered. Redirected to a file it would otherwise
  /// be fully buffered, so the interesting output of a crash sits in a 4 KB
  /// buffer that is never flushed, which is indistinguishable from no output
  /// at all -- exactly the failure this whole file exists to fix.
  static void _redirectNativeOutput(String path) {
    try {
      final libc = DynamicLibrary.process();
      final open = libc.lookupFunction<_OpenNative, _OpenDart>('open');
      final dup2 = libc.lookupFunction<_Dup2Native, _Dup2Dart>('dup2');

      // O_WRONLY | O_CREAT | O_APPEND, same values on Darwin and Linux.
      const flags = 0x0001 | 0x0200 | 0x0008;
      final cPath = path.toNativeUtf8();
      final fd = open(cPath, flags, 0x1A4 /* 0644 */);
      calloc.free(cPath);
      if (fd < 0) return;

      dup2(fd, 1);
      dup2(fd, 2);
      _nativeRedirected = true;

      // The FILE* for stdout is spelled differently per libc; try both rather
      // than guess the platform.
      for (final symbol in ['__stdoutp', 'stdout']) {
        try {
          final ptr = libc.lookup<Pointer<Void>>(symbol);
          final setvbuf =
              libc.lookupFunction<_SetvbufNative, _SetvbufDart>('setvbuf');
          setvbuf(ptr.value, nullptr, 2 /* _IONBF */, 0);
          break;
        } catch (_) {
          // Not this name; try the next.
        }
      }
    } catch (e) {
      _append('native capture unavailable: $e');
    }
  }

  /// Records a line, to memory and to the file.
  static void log(String message) {
    final stamp = DateTime.now().toIso8601String().substring(11, 23);
    final line = '$stamp  $message';
    _append(line);
    final path = _filePath;
    if (path == null) return;
    try {
      // Async, deliberately: this ran a synchronous append on the UI thread
      // for every single log line, and the log file can live on an SD card --
      // one busy moment on the card and every logged event became a UI stall
      // (the Retro-Saturn log learned this first). Ordering is preserved by
      // the future chain; a log write must never block the frame it is
      // reporting on.
      _pendingWrite = _pendingWrite.then(
        (_) => File(path).writeAsString('$line\n', mode: FileMode.append),
      );
    } catch (_) {
      // A log write must never take the app down.
    }
  }

  /// Serialises the async file appends so lines land in order.
  static Future<void> _pendingWrite = Future<void>.value();

  static void _append(String line) {
    _lines.add(line);
    if (_lines.length > _maxLines) {
      _lines.removeRange(0, _lines.length - _maxLines);
    }
  }

  /// Everything worth showing: the Dart lines this session, plus whatever the
  /// native side wrote into the same file.
  ///
  /// Reads the file rather than returning [_lines], because the native output
  /// is the half that matters and it only exists on disk.
  static Future<String> read() async {
    final path = _filePath;
    if (path == null) return _lines.join('\n');
    try {
      final text = await File(path).readAsString();
      return text.isEmpty ? _lines.join('\n') : text;
    } catch (e) {
      return '${_lines.join('\n')}\n(could not read $path: $e)';
    }
  }

  /// Empties the log, keeping a header so a fresh report says when it started.
  static Future<void> clear() async {
    _lines.clear();
    final path = _filePath;
    if (path == null) return;
    try {
      await File(path).writeAsString(
          '=== cleared ${DateTime.now().toIso8601String()} ===\n');
    } catch (_) {}
  }
}
