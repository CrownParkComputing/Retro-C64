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
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/category.dart';
import '../services/app_prefs.dart';
import '../services/demo_roms_service.dart';
import '../view_models/workbench_view_model.dart';
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


  bool get _isFolderScan => _storage.kind == StorageStrategyKind.folderScan;

  @override
  void initState() {
    super.initState();
    // Nothing is scanned here, on purpose.
    //
    // This screen asks one question -- your own ROMs and games, or the free
    // ones -- and searching the user's folders before they have answered it
    // is work done on a guess. It also made the screen report on a library
    // that has nothing to do with the choice: someone taking Store
    // Compliance never needed the scan, and someone taking Start gets the
    // library listed the moment they reach the workbench, which is where it
    // belongs.
    //
    // Files dropped into the app's own folder are still imported at launch.
    // That is StartupImport in main(), and it is not this screen's job.
  }

  Future<void> _finishSetup() async {
    // Start means "use my own ROMs and games", so it also leaves compliance
    // mode. Without this the flag survived, the next launch quietly booted
    // the free ROMs again, and the user would be looking at a library that
    // is not theirs having just asked for the opposite.
    final wasDemo = await AppPrefs.getDemoRomMode();
    if (wasDemo) await AppPrefs.setDemoRomMode(false);
    await AppPrefs.setSetupCompleted(true);
    if (!mounted) return;
    if (wasDemo) {
      final vm = context.read<WorkbenchViewModel>();
      await vm.refreshDemoMode();
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Back on your own ROMs'),
          content: const Text(
            'Close the app completely and open it again. The emulator picks '
            'its ROMs as it starts, so the change takes effect on the next '
            'launch. Nothing of yours was altered while compliance mode was '
            'on.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      if (!mounted) return;
    }
    widget.onComplete();
  }





  String _consoleText() {
    final buffer = StringBuffer()
      ..writeln('    **** RETRO-C64 BASIC V2 ****')
      ..writeln()
      ..writeln('64K RAM SYSTEM  38911 BASIC BYTES FREE')
      ..writeln()
      ..writeln('READY.')
      ..writeln()
      ..writeln('AN EMULATOR FOR THE COMMODORE 64.')
      ..writeln('IT SHIPS NO GAMES AND NO')
      ..writeln('COMMODORE ROMS.')
      ..writeln()
      ..writeln('PRESS "START" TO USE YOUR OWN')
      ..writeln('ROMS AND GAMES.')
      ..writeln(_isFolderScan
          ? 'POINT THE APP AT YOUR FOLDER FROM\nPATHS IN THE SIDEBAR.'
          : 'DROP YOUR FILES INTO THIS APP\'S\nFOLDER (FILES > ON MY IPAD >\nRETRO-C64).')
      ..writeln()
      ..writeln('OR PRESS "STORE COMPLIANCE" TO RUN')
      ..writeln('ON FREE, OPEN SOURCE ROMS -')
      ..write('IT NEEDS NOTHING FROM YOU.');
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

  /// The store-compliance route: switches the machine to the free Open ROMs
  /// and starts the demo on them.
  ///
  /// Named for what it is FOR rather than for what it does mechanically. It
  /// is the thing a store reviewer is pointed at, and it has to be
  /// recognisable as that on a screen they have never seen before -- the
  /// sidebar entry it matches is called Compliance for the same reason.
  ///
  /// The whole point is that the user sees a C64 WORKING before being asked
  /// for anything. A first run used to end at a request for three Commodore
  /// ROM files, which is a poor way to meet a program and gives an App
  /// Review reviewer -- who has no ROMs and no C64 to dump them from --
  /// nothing at all to look at.
  ///
  /// Doable here, and only here, without a restart. The emulator loads its
  /// ROMs when the machine first powers on and cannot be handed a different
  /// set afterwards, so the compliance page has to ask for a restart. During
  /// setup no machine has started yet, so pointing the core at the demo's
  /// own ROM directory now simply decides what it will boot from.
  Future<void> _storeCompliance() async {
    setState(() => _busy = true);
    try {
      await DemoRomsService.prepareDemoEnvironment();
      final demoDir = await DemoRomsService.demoRomDir();
      // Remembered as well as applied, so the choice survives the next
      // launch rather than silently reverting to a ROM set they do not have.
      await AppPrefs.setDemoRomMode(true);

      // No copy goes into the user's own library: in this mode Games
      // lists the demo folder itself, so a second copy among their files
      // would just be litter.

      if (!mounted) return;
      final vm = context.read<WorkbenchViewModel>();
      // So the rail comes up in demo shape straight away rather than at the
      // next launch.
      await vm.refreshDemoMode();
      vm.core.init(demoDir.path);
      // The free ROMs have none of the KERNAL hooks VICE's usual .prg
      // autostart patches, so that path fails on them with
      // "?DEVICE NOT PRESENT". Injection needs no KERNAL at all.
      vm.core.setPrgInject(true);

      // Lands on the compliance page, which says which file to open and
      // how. Nothing is started for the user: they open the demo from the
      // library the same way they would open a tape or a disk, which is
      // also the only version of this that shows them how to open anything
      // else.
      vm.setCategory(WorkbenchCategory.compliance);
      widget.onComplete();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not switch to the free ROMs: $e')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
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
          // FIRST, and deliberately: the only button that needs nothing from
          // the user. Everything else on this screen asks for something.
          _button('Store Compliance', _busy ? null : _storeCompliance),
          const SizedBox(width: 8),
          // Choosing a folder is NOT on this screen any more. Two buttons
          // that both need something from the user, next to one that does
          // not, made the first decision look like three. Picking a folder
          // belongs where the folder is described -- Paths -- and Start goes
          // there anyway when nothing has been found.
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
