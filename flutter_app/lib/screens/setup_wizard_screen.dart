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
// goNext(): STEP_APP can't advance without an app folder, and STEP_GAMES
// can't Finish without a games folder. On iOS both steps are always
// satisfied -- there is nothing to pick for app storage, and gating Finish
// on an import made the wizard a dead end for anyone whose files weren't
// on the device yet (see _canAdvance).
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

import '../services/app_prefs.dart';
import '../services/permissions_service.dart';
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

enum _WizardStep { welcome, app, games }

class SetupWizardScreen extends StatefulWidget {
  final VoidCallback onComplete;

  const SetupWizardScreen({super.key, required this.onComplete});

  @override
  State<SetupWizardScreen> createState() => _SetupWizardScreenState();
}

class _SetupWizardScreenState extends State<SetupWizardScreen> {
  final _storage = StorageAccess.instance;
  _WizardStep _step = _WizardStep.welcome;

  String? _appFolderPath;
  String? _gamesFolderPath;
  List<ImportedFile> _importedGameFiles = const [];
  bool _busy = false;

  // Set when the user cancels a picker dialog (folder or files) without
  // choosing anything -- the console shows a "tap to retry" line instead
  // of auto-reopening the dialog in a loop.
  bool _appPickCancelled = false;
  bool _gamesPickCancelled = false;

  // One-shot guard so a step only auto-prompts once per VISIT, not once per
  // typing-complete event. Picking a folder appends a "? /path" answer line
  // to _consoleText(), which the console then types out too -- without this
  // guard that second burst of typing also finishes and re-fires
  // _handleTypingComplete, reopening the dialog again immediately after a
  // successful pick (a real, confirmed bug: "asking then select then
  // prompting again to select"). Reset whenever the step changes so
  // revisiting a step (e.g. Back) still auto-prompts exactly once, per the
  // "if you go back and it asks the question again it should prompt again"
  // requirement.
  bool _promptedThisVisit = false;

  bool get _isFolderScan => _storage.kind == StorageStrategyKind.folderScan;

  @override
  void initState() {
    super.initState();
    _restorePreviousSelection();
  }

  Future<void> _restorePreviousSelection() async {
    final app = await AppPrefs.getAppFolderPath();
    final games = await AppPrefs.getGamesFolderPath();
    List<ImportedFile> imported = const [];
    if (!_isFolderScan) {
      imported = await _storage.listImported(kGamesImportSubdir);
    }
    if (!mounted) return;
    setState(() {
      _appFolderPath = app;
      _gamesFolderPath = games;
      _importedGameFiles = imported;
    });
  }

  bool _canAdvance() {
    switch (_step) {
      case _WizardStep.welcome:
        return true;
      case _WizardStep.app:
        // Folder-scan platforms need a chosen app folder before advancing,
        // same gate as SetupWizardActivity.canAdvance()'s STEP_APP case.
        // iOS has nothing to pick here -- the sandbox always exists.
        return _isFolderScan ? _appFolderPath != null : true;
      case _WizardStep.games:
        // Folder-scan platforms must choose a folder -- an empty one is
        // fine, and picking one always succeeds, so this is a gate the
        // user can always get through.
        //
        // File-import platforms must NOT be gated on having imported
        // something. Someone opening the app for the first time may have
        // no C64 files on the device yet, and getting them there means
        // leaving for the Files app -- so requiring an import here locked
        // them inside the wizard with no way forward. Importing is
        // available from the Paths tab afterwards, and the bundled SID
        // tunes work with nothing imported at all.
        return _isFolderScan ? _gamesFolderPath != null : true;
    }
  }

  void _showStep(_WizardStep step) {
    setState(() {
      _step = step;
      _promptedThisVisit = false;
    });
  }

  Future<void> _goNext() async {
    if (!_canAdvance()) return;
    if (_step == _WizardStep.games) {
      await _finishSetup();
      return;
    }
    _showStep(_WizardStep.values[_step.index + 1]);
  }

  void _goBack() {
    if (_step.index == 0) return;
    _showStep(_WizardStep.values[_step.index - 1]);
  }

  Future<void> _pickAppFolder() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _appPickCancelled = false;
    });
    final result = await _storage.pickFolder(dialogTitle: 'Select App Folder');
    if (result != null) {
      await AppPrefs.setAppFolderPath(result.path);
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (result != null) {
        _appFolderPath = result.path;
      } else {
        _appPickCancelled = true;
      }
    });
  }

  Future<void> _pickGamesFolder() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _gamesPickCancelled = false;
    });
    // Ask for shared-storage access BEFORE the folder picker: without it
    // (Android 11+) the picked folder can be listed but none of its files
    // can be opened, which is exactly the "games appear but launch blank"
    // failure. No-op on platforms where the concept doesn't apply.
    if (!await PermissionsService.hasStorageAccess()) {
      await PermissionsService.requestStorageAccess();
    }
    final result =
        await _storage.pickFolder(dialogTitle: 'Select Games Folder');
    if (result != null) {
      await AppPrefs.setGamesFolderPath(result.path);
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (result != null) {
        _gamesFolderPath = result.path;
      } else {
        _gamesPickCancelled = true;
      }
    });
  }

  Future<void> _importGameFiles() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _gamesPickCancelled = false;
    });
    final imported =
        await _storage.pickAndImportFiles(destinationSubdir: kGamesImportSubdir);
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (imported.isNotEmpty) {
        // Merge rather than replace -- the user may import in multiple
        // passes (SIDs first, then disks, say).
        final byPath = {for (final f in _importedGameFiles) f.path: f};
        for (final f in imported) {
          byPath[f.path] = f;
        }
        _importedGameFiles = byPath.values.toList();
      } else {
        _gamesPickCancelled = true;
      }
    });
  }

  Future<void> _finishSetup() async {
    await AppPrefs.setSetupCompleted(true);
    if (!mounted) return;
    widget.onComplete();
  }

  /// Full BASIC-program text for the current step. The console types this
  /// out character-by-character; when it changes (e.g. an answer line gets
  /// appended once a folder is picked), the console keeps typing forward
  /// from wherever it already was rather than restarting.
  String _consoleText() {
    switch (_step) {
      case _WizardStep.welcome:
        return '**** COMMODORE 64 BASIC V2 ****\n\n'
            '64K RAM SYSTEM  38911 BASIC BYTES FREE\n\n'
            '10 PRINT "WELCOME TO VICE MULTIPLATFORM"\n'
            '20 PRINT "LETS SET UP YOUR C64 LIBRARY"\n'
            '30 PRINT "RUNNING ON ${_platformLabel()}"\n'
            'READY.';
      case _WizardStep.app:
        if (_isFolderScan) {
          final base = '10 PRINT "WHERE SHOULD I STORE APP DATA?"\n'
              '20 REM BEZELS, ARTWORK, EXPORTS\n'
              '30 INPUT A\$';
          if (_appFolderPath != null) return '$base\n? $_appFolderPath';
          if (_appPickCancelled) return '$base\n? (CANCELLED - TAP TO RETRY)';
          return base;
        }
        return '10 PRINT "APP STORAGE ON ${_platformLabel()}"\n'
            '20 PRINT "IS AUTOMATIC. NOTHING TO PICK."\n'
            '30 REM SANDBOX DOCUMENTS FOLDER\n'
            '? OK';
      case _WizardStep.games:
        if (_isFolderScan) {
          final base = '10 PRINT "WHERE ARE YOUR GAMES?"\n'
              '20 REM D64/T64/CRT/PRG/SID SCANNED\n'
              '30 INPUT A\$';
          if (_gamesFolderPath != null) return '$base\n? $_gamesFolderPath';
          if (_gamesPickCancelled) {
            return '$base\n? (CANCELLED - TAP TO RETRY)';
          }
          return base;
        }
        final base = '10 PRINT "IMPORT YOUR GAMES AND SIDS"\n'
            '20 REM COPIED INTO APP STORAGE\n'
            '30 INPUT A\$';
        if (_importedGameFiles.isNotEmpty) {
          return '$base\n? ${_importedGameFiles.length} FILE(S) IMPORTED';
        }
        if (_gamesPickCancelled) {
          return '$base\n? (NOTHING IMPORTED - TAP TO RETRY, '
              'OR FINISH AND IMPORT LATER)';
        }
        return base;
    }
  }

  /// Fires once the current step's console text has finished typing --
  /// this is the "INPUT A$ blocks for input" beat, so a folder/file
  /// question opens the real OS picker right here, automatically. This
  /// fires once per VISIT to the step (see [_promptedThisVisit]), including
  /// navigating Back to a step that already has an answer -- a real
  /// `INPUT A$` prompts again each time it runs, it doesn't silently keep
  /// the old answer, so going back and having the question retyped means
  /// it's asking again, not just redisplaying history. It must NOT also
  /// fire again once an answer is picked and its "? /path" line gets typed
  /// out below the question -- that's a second typing-complete on the same
  /// visit, not a new visit, and re-opening the dialog right after a
  /// successful pick is a real bug (confirmed live: "asking then select
  /// then prompting again to select").
  void _handleTypingComplete() {
    if (!mounted || _busy || _promptedThisVisit) return;
    if (_step == _WizardStep.welcome) return;
    if (_step == _WizardStep.app && !_isFolderScan) return;
    _promptedThisVisit = true;
    switch (_step) {
      case _WizardStep.welcome:
        break;
      case _WizardStep.app:
        _pickAppFolder();
      case _WizardStep.games:
        _isFolderScan ? _pickGamesFolder() : _importGameFiles();
    }
  }

  /// Tap-to-retry/tap-to-correct -- re-invokes whichever picker this step
  /// uses, whether the previous attempt was cancelled OR already answered.
  /// Without the "already answered" case a folder choice could never be
  /// changed once made (Back just shows the same stale answer with no way
  /// to redo it), which is the whole point of a tappable BASIC-style
  /// prompt: tap the answer line to retype it.
  void _retryPick() {
    switch (_step) {
      case _WizardStep.welcome:
        return;
      case _WizardStep.app:
        _pickAppFolder();
      case _WizardStep.games:
        _isFolderScan ? _pickGamesFolder() : _importGameFiles();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _borderBlue,
      body: SafeArea(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _retryPick,
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
                        // A fresh key per step forces a clean restart of
                        // the typing animation instead of trying to diff
                        // against a completely different step's text.
                        key: ValueKey(_step),
                        text: _consoleText(),
                        onComplete: _handleTypingComplete,
                      ),
                    ),
                  ),
                  _footer(),
                ],
              ),
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
              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
          : Text(label),
    );
  }

  Widget _footer() {
    final canAdvance = _canAdvance();
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          if (_step != _WizardStep.welcome) ...[
            _button('Back', _goBack),
            const SizedBox(width: 8),
          ],
          Opacity(
            opacity: canAdvance ? 1.0 : 0.45,
            child: _button(
              _step == _WizardStep.games ? 'Finish' : 'Next',
              canAdvance ? _goNext : null,
            ),
          ),
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
  final VoidCallback? onComplete;

  const _TypedConsole({
    super.key,
    required this.text,
    this.onComplete,
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
    widget.onComplete?.call();
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
