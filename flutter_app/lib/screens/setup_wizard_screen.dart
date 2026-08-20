// Flutter port of SetupWizardActivity.java's 3-step wizard (STEP_WELCOME,
// STEP_APP, STEP_GAMES with Next/Back/Finish), adapted per the storage
// realities of each platform via StorageAccess:
//
//   - Linux / Android (StorageStrategyKind.folderScan): pick a folder,
//     same shape as the Android original's SAF tree picker.
//   - iOS (StorageStrategyKind.fileImport): no folder access is possible at
//     all, so the "App Folder" step is automatic (the sandbox Documents
//     directory always exists, nothing to choose) and the "Games Folder"
//     step becomes a multi-file import that copies each picked file into
//     the sandbox.
//
// Validation-before-advance mirrors the Android version's canAdvance()/
// goNext(): STEP_APP can't advance without an app folder (or, on iOS,
// it's always satisfied), STEP_GAMES can't Finish without at least one
// game/media file available.
//
// Presentation: the WHOLE wizard (Welcome and the App/Games questions
// alike) is a single plain C64 screen with BASIC-program text typed out
// character-by-character -- no raster bars, no logo animation, no scrolling
// ticker. That's the workbench's idle-timeout screensaver's job
// (C64Background / WorkbenchScreen's _scheduleIdle) and must never appear
// here. When a question needs a folder or files, the real OS picker opens
// automatically right as the "INPUT A$" line finishes typing, same beat as
// BASIC's own INPUT statement blocking for input.
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../data/category.dart';
import '../data/media_entry.dart';
import '../services/app_prefs.dart';
import '../services/startup_import.dart';
import '../services/storage_access.dart';

const String kGamesImportSubdir = 'games';

// The C64's own boot-screen colours -- the wizard is meant to read as "the
// real BASIC screen", not a styled reskin.
const Color _borderBlue = Color(0xFF4040E0);
const Color _screenBlue = Color(0xFF6060FF);
const Color _textColor = Color(0xFFC7C7FF);
const TextStyle _consoleStyle = TextStyle(
  fontFamily: 'monospace',
  fontWeight: FontWeight.bold,
  fontSize: 16,
  height: 1.6,
  color: _textColor,
);

/// The current OS, in the all-caps shout the rest of the console text uses
/// -- answers the "what will iOS do with SID/games from Downloads"
/// question right on screen, not just in code comments.
String _platformLabel() {
  if (Platform.isLinux) return 'LINUX';
  if (Platform.isAndroid) return 'ANDROID';
  if (Platform.isIOS) return 'IOS';
  if (Platform.isMacOS) return 'MACOS';
  if (Platform.isWindows) return 'WINDOWS';
  return Platform.operatingSystem.toUpperCase();
}

class SetupWizardScreen extends StatefulWidget {
  final VoidCallback onComplete;

  const SetupWizardScreen({super.key, required this.onComplete});

  @override
  State<SetupWizardScreen> createState() => _SetupWizardScreenState();
}

/// One screen: say hello, take stock of what C64 media is already reachable,
/// and name what was found.
///
/// This replaced a three-step wizard (welcome -> app folder -> games folder).
/// Two things were wrong with it on iOS. The app-folder step asked a question
/// that has no answer in a sandbox ("APP STORAGE IS AUTOMATIC. NOTHING TO
/// PICK."), and every question step fired the OS picker automatically the
/// instant its `INPUT A$` line finished typing -- so the app opened straight
/// into a full-screen document browser before the user had seen anything.
///
/// A note on "import from Downloads": an iOS app cannot read On My iPad ->
/// Downloads. That folder belongs to the Files app and the sandbox forbids
/// reaching into it, so no amount of scanning will find it. What this screen
/// scans is everywhere the app genuinely can read -- its own container,
/// including anything dropped into "Retro-C64" in the Files app,
/// opened into the app from elsewhere (Documents/Inbox), or pushed over USB.
/// Downloads is reachable only through the picker, which is what
/// "Import from Files..." opens.
class _SetupWizardScreenState extends State<SetupWizardScreen> {
  final _storage = StorageAccess.instance;

  bool _busy = false;
  bool _scanned = false;
  String? _gamesFolderPath;
  List<ImportedFile> _found = const [];

  bool get _isFolderScan => _storage.kind == StorageStrategyKind.folderScan;

  @override
  void initState() {
    super.initState();
    _scanOnStartup();
  }

  /// Pulls in whatever is already reachable, without prompting. On the
  /// file-import platforms that means sweeping the container and copying
  /// anything new into the games folder; on folder-scan platforms it means
  /// re-listing the folder already configured, if there is one.
  Future<void> _scanOnStartup() async {
    setState(() => _busy = true);
    try {
      if (_isFolderScan) {
        final games = await AppPrefs.getGamesFolderPath();
        final files = games == null
            ? const <ImportedFile>[]
            : await _storage.scanFolder(games);
        if (!mounted) return;
        setState(() {
          _gamesFolderPath = games;
          _found = files;
        });
      } else {
        final pending = await _storage.listImportable(
          destinationSubdir: kGamesImportSubdir,
        );
        if (pending.isNotEmpty) {
          await _storage.importFiles(pending,
              destinationSubdir: kGamesImportSubdir);
        }
        final files = await _storage.listImported(kGamesImportSubdir);
        if (!mounted) return;
        setState(() => _found = files);
      }
    } catch (_) {
      // A failed scan is not fatal -- the screen just reports nothing found
      // and the user can still reach the picker.
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _scanned = true;
        });
      }
    }
  }

  Future<void> _importMore() async {
    if (_busy) return;
    if (_isFolderScan) {
      setState(() => _busy = true);
      final result =
          await _storage.pickFolder(dialogTitle: 'Select Games Folder');
      if (result != null) {
        await AppPrefs.setGamesFolderPath(result.path);
      }
      if (!mounted) return;
      setState(() => _busy = false);
      await _scanOnStartup();
      return;
    }

    // iOS has no picker any more: the app's folder in Files is the one door,
    // and everything dropped there imports itself. "Import more" is therefore
    // a rescan - run the startup import again and re-read the shelf.
    setState(() => _busy = true);
    await StartupImport.run();
    if (!mounted) return;
    setState(() => _busy = false);
    await _scanOnStartup();
  }

  Future<void> _finishSetup() async {
    await AppPrefs.setSetupCompleted(true);
    if (!mounted) return;
    widget.onComplete();
  }

  /// Groups what was found by media type, so the console can say
  /// "3 DISK, 2 TAPE" rather than just a bare count.
  Map<MediaFormatFilter, int> _countsByType() {
    final counts = <MediaFormatFilter, int>{};
    for (final file in _found) {
      final dot = file.displayName.lastIndexOf('.');
      final ext =
          dot < 0 ? '' : file.displayName.substring(dot + 1).toLowerCase();
      final type = ext == 'sid'
          ? MediaFormatFilter.none
          : MediaEntry.filterForExtension(ext);
      counts[type] = (counts[type] ?? 0) + 1;
    }
    return counts;
  }

  String _typeLabel(MediaFormatFilter type, int count) {
    final name = switch (type) {
      MediaFormatFilter.disk => 'DISK',
      MediaFormatFilter.tape => 'TAPE',
      MediaFormatFilter.cartridge => 'CART',
      MediaFormatFilter.prg => 'PRG',
      MediaFormatFilter.none => 'SID',
    };
    return '$count $name';
  }

  String _consoleText() {
    final buffer = StringBuffer()
      ..writeln('**** COMMODORE 64 BASIC V2 ****')
      ..writeln()
      ..writeln('64K RAM SYSTEM  38911 BASIC BYTES FREE')
      ..writeln()
      ..writeln('10 PRINT "WELCOME TO RETRO-C64 EMULATOR"')
      ..writeln('20 PRINT "RUNNING ON ${_platformLabel()}"')
      ..writeln('30 LOAD "\$",8');

    if (!_scanned) {
      buffer.write('\nSEARCHING...');
      return buffer.toString();
    }

    if (_found.isEmpty) {
      buffer
        ..writeln()
        ..writeln('SEARCHING FOR PROGRAMS')
        ..writeln('READY.')
        ..writeln()
        ..write(_isFolderScan
            ? '? NO GAMES FOLDER SET - CHOOSE ONE'
            : '? NOTHING FOUND - PUT ZIPS IN THIS APP\'S FOLDER\n'
                '  (FILES > ON MY IPAD > RETRO-C64), THEN SCAN');
      return buffer.toString();
    }

    final counts = _countsByType();
    final summary = counts.entries
        .map((e) => _typeLabel(e.key, e.value))
        .join(', ');

    buffer
      ..writeln()
      ..writeln('SEARCHING FOR PROGRAMS')
      ..writeln('FOUND ${_found.length} FILE(S): $summary');
    if (_gamesFolderPath != null) {
      buffer.writeln('IN $_gamesFolderPath');
    }
    buffer.writeln();

    // Name them, newest-looking first is unhelpful here -- alphabetical is
    // what a directory listing would give.
    final names = _found.map((f) => f.displayName).toList()..sort();
    for (final name in names.take(12)) {
      buffer.writeln('  "${name.toUpperCase()}"');
    }
    if (names.length > 12) {
      buffer.writeln('  ... AND ${names.length - 12} MORE');
    }
    buffer.write('READY.');
    return buffer.toString();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _borderBlue,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Container(
            width: double.infinity,
            color: _screenBlue,
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    child: _TypedConsole(
                      key: ValueKey(_consoleText().length),
                      text: _consoleText(),
                    ),
                  ),
                ),
                _footer(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _button(String label, VoidCallback? onPressed) {
    return ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: _borderBlue,
        foregroundColor: Colors.white,
        side: const BorderSide(color: _textColor),
        minimumSize: const Size(76, 38),
        textStyle: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      ),
      child: _busy
          ? const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: Colors.white))
          : Text(label),
    );
  }

  Widget _footer() {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          _button(_isFolderScan ? 'Choose folder' : 'Scan',
              _busy ? null : _importMore),
          const SizedBox(width: 8),
          _button('Start', _busy ? null : _finishSetup),
        ],
      ),
    );
  }
}

/// Types [text] out character-by-character (same beat as the C64's own
/// screen output), with a blinking cursor block. If [text] changes to a
/// longer string that starts with what's already been typed, typing simply
/// continues from where it left off instead of restarting -- this is how a
/// picked folder path appears to get "typed in" right after the OS dialog
/// closes. Calls [onComplete] once when the full current text has finished
/// typing (and again if a longer text later builds on it and also
/// finishes).
class _TypedConsole extends StatefulWidget {
  final String text;

  const _TypedConsole({
    super.key,
    required this.text,
  });

  @override
  State<_TypedConsole> createState() => _TypedConsoleState();
}

class _TypedConsoleState extends State<_TypedConsole> {
  int _typedLen = 0;
  String? _completedFor;
  Timer? _typeTimer;
  Timer? _blinkTimer;
  bool _cursorOn = true;

  @override
  void initState() {
    super.initState();
    _blinkTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (mounted) setState(() => _cursorOn = !_cursorOn);
    });
    _startTyping();
  }

  @override
  void didUpdateWidget(covariant _TypedConsole old) {
    super.didUpdateWidget(old);
    if (widget.text == old.text) return;
    // If the new text is just the old text with more appended, keep the
    // already-typed prefix and continue from there; otherwise it's a
    // genuinely different message, so start over.
    if (!widget.text.startsWith(old.text) || _typedLen > old.text.length) {
      _typedLen = widget.text.startsWith(old.text) ? _typedLen : 0;
    }
    _typedLen = _typedLen.clamp(0, widget.text.length);
    _startTyping();
  }

  void _startTyping() {
    _typeTimer?.cancel();
    if (_typedLen >= widget.text.length) {
      _fireCompleteIfNeeded();
      return;
    }
    _typeTimer = Timer.periodic(const Duration(milliseconds: 22), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_typedLen >= widget.text.length) {
        timer.cancel();
        _fireCompleteIfNeeded();
        return;
      }
      setState(() => _typedLen++);
    });
  }

  void _fireCompleteIfNeeded() {
    if (_completedFor == widget.text) return;
    _completedFor = widget.text;
  }

  @override
  void dispose() {
    _typeTimer?.cancel();
    _blinkTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final shown = widget.text.substring(0, _typedLen);
    final cursor = _cursorOn ? '█' : ' ';
    return Text('$shown$cursor', style: _consoleStyle);
  }
}
