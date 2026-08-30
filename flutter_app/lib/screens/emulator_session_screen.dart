import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:retro_c64/data/category.dart';
import 'package:retro_c64/services/save_state_service.dart';
import 'package:retro_c64/services/service_locator.dart';
import 'package:retro_c64/services/video_settings.dart';
import 'package:retro_c64/screens/emulator_screen.dart';
import 'package:retro_c64/widgets/session_tool_rail.dart';
import 'package:retro_c64/theme/vice_theme.dart';
import 'package:retro_c64/view_models/workbench_view_model.dart';

/// How a session ended, from the workbench's point of view.
///
/// [paused] keeps the machine warm behind the workbench: the core is paused
/// and the current entry stays current, so the Resume screen offers it back.
/// [closed] is the same snapshot-then-stop, but the entry is let go.
enum SessionExit { paused, closed }

/// The emulator's own screen -- the family pattern shared with Retro-Amiga
/// and Retro-Saturn. Launching pushes this route fullscreen; everything a
/// player needs mid-game lives here, and both ways out land back on the
/// workbench in exactly one place.
///
/// A corner handle opens the pause menu (machine paused, picture dimmed):
/// Resume, Save and exit, Close. The right-hand rail carries the in-game
/// tools that used to sit on the workbench status bar -- keyboard, on-screen
/// pad mode, joystick port, layout editing -- as labelled buttons, since an
/// unlabelled circle two rooms from its effect was the single most common
/// review complaint across the family.
class EmulatorSessionScreen extends StatefulWidget {
  final WorkbenchViewModel vm;

  const EmulatorSessionScreen({super.key, required this.vm});

  @override
  State<EmulatorSessionScreen> createState() => _EmulatorSessionScreenState();
}

class _EmulatorSessionScreenState extends State<EmulatorSessionScreen> {
  /// The pause menu: machine stopped, picture dimmed, choices pinned up.
  bool _menuOpen = false;

  /// Whether the corner handle and rail are on screen. They hide a few
  /// seconds after the last touch: a 4:3 machine on a widescreen handheld
  /// has no width to lend to furniture that is only occasionally wanted.
  bool _controlsVisible = true;
  Timer? _controlsTimer;

  WorkbenchViewModel get vm => widget.vm;

  @override
  void initState() {
    super.initState();
    // The session owns the whole screen: hide the system bars for the
    // duration and give them back on the way out. Sticky, because an edge
    // swipe on a handheld is easy to do by accident mid-game.
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _findSiblingDisks();
    _restartControlsTimer();
  }

  @override
  void dispose() {
    _controlsTimer?.cancel();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  /// Other disks of the SAME game: multi-disk sets ship as "Title (Disk
  /// 1 Side A)", "Title (Disk 2)"...; strip the marker and everything in
  /// the folder sharing the stem is this game's set.
  List<String> _siblingDisks = const [];

  static final RegExp _diskMarker = RegExp(
      r'[\(\[]?\s*(disk|disc|side)\s*[a-z0-9]+[\)\]]?',
      caseSensitive: false);

  static String _diskStem(String path) {
    final base = path.split('/').last;
    final dot = base.lastIndexOf('.');
    final name = dot > 0 ? base.substring(0, dot) : base;
    return name
        .replaceAll(_diskMarker, '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim()
        .toLowerCase();
  }

  void _findSiblingDisks() {
    final entry = vm.currentEntry;
    if (entry == null) return;
    if (entry.mediaType != MediaFormatFilter.disk) return;
    if (!_diskMarker.hasMatch(entry.path.split('/').last)) return;
    final stem = _diskStem(entry.path);
    try {
      final disks = <String>[];
      for (final f in Directory(entry.path).parent.listSync(followLinks: false)) {
        if (f is! File) continue;
        final lower = f.path.toLowerCase();
        if (!lower.endsWith('.d64') &&
            !lower.endsWith('.g64') &&
            !lower.endsWith('.d71') &&
            !lower.endsWith('.d81')) {
          continue;
        }
        if (_diskStem(f.path) == stem) disks.add(f.path);
      }
      disks.sort();
      if (disks.length > 1 && mounted) {
        setState(() => _siblingDisks = disks);
      }
    } on FileSystemException {
      // A folder that cannot be listed just means no swap entry.
    }
  }

  /// The pause menu's Swap disk: attach another image to drive 8 -- the
  /// running program keeps going, exactly like flipping the real disk.
  Future<void> _swapDisk() async {
    final String? chosen = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: const Color(0xFF11161B),
      builder: (BuildContext context) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const ListTile(title: Text('Swap disk')),
              const Divider(height: 1),
              for (final d in _siblingDisks)
                ListTile(
                  leading: Icon(d == vm.currentEntry?.path
                      ? Icons.album
                      : Icons.album_outlined),
                  title: Text(d.split('/').last,
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  onTap: () => Navigator.pop(context, d),
                ),
            ],
          ),
        ),
      ),
    );
    if (chosen == null || !mounted) return;
    final rc = vm.core.attachDisk(chosen);
    if (rc != 0 && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not attach that disk (error $rc).')),
      );
    }
  }

  /// Save state without leaving: the same rolling capture Save-and-exit
  /// makes, but the game carries on and the Resume screen lists it.
  Future<void> _saveStateInPlace() async {
    final entry = vm.currentEntry;
    if (entry == null) return;
    try {
      await SaveStateService.capture(
        core: vm.core,
        title: entry.displayName,
        mediaPath: entry.path,
        mediaType: entry.mediaType,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Saved — the Resume screen lists it.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save: $e')),
      );
    }
  }

  void _restartControlsTimer() {
    _controlsTimer?.cancel();
    _controlsTimer = Timer(const Duration(seconds: 6), () {
      if (mounted && !_menuOpen) setState(() => _controlsVisible = false);
    });
  }

  void _wakeControls() {
    if (!_controlsVisible) setState(() => _controlsVisible = true);
    _restartControlsTimer();
  }

  void _setMenu(bool open) {
    setState(() {
      _menuOpen = open;
      _controlsVisible = true;
    });
    // The menu freezes the machine for real -- audio included -- rather
    // than dimming a game that plays on underneath.
    vm.core.setPaused(open);
    if (!open) _restartControlsTimer();
  }

  /// Save and exit: snapshot, silence, and hand the workbench a session it
  /// can offer back on the Resume screen.
  Future<void> _saveAndExit() async {
    await vm.endSession();
    if (!mounted) return;
    Navigator.of(context).pop(SessionExit.paused);
  }

  /// Close: the same snapshot (the rolling saves keep the last sessions
  /// either way), but the workbench forgets the entry.
  Future<void> _close() async {
    await vm.endSession();
    if (!mounted) return;
    Navigator.of(context).pop(SessionExit.closed);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_close());
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          children: [
            // The machine. EmulatorScreen still draws the framebuffer, the
            // on-screen controls and the soft keyboard; the session chrome
            // lives out here on top of it.
            Positioned.fill(
              child: Listener(
                behavior: HitTestBehavior.translucent,
                onPointerDown: (_) => _wakeControls(),
                child: EmulatorScreen(
                  core: vm.core,
                  mediaLabel: vm.emulatorLabel,
                  onBackToLibrary: () => unawaited(_saveAndExit()),
                  leftHanded: vm.leftHanded,
                  gamepad: vm.gamepad,
                  padMode: vm.padMode,
                  onPadModeChanged: vm.setPadMode,
                  customButtons: vm.customButtons,
                  onCustomButtonsChanged: vm.setCustomButtons,
                  joystickPort: vm.joystickPort,
                  onJoystickPortChanged: vm.setJoystickPort,
                  ui: vm.emulatorUi,
                ),
              ),
            ),
            if (_menuOpen) ...[
              // Dim the frozen picture. Tapping the picture resumes --
              // the cheapest way back into the game is the game itself.
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => _setMenu(false),
                  child: Container(color: const Color(0xB3000000)),
                ),
              ),
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _ResumeButton(onTap: () => _setMenu(false)),
                    const SizedBox(height: 28),
                    // Occasional actions live HERE, not on the rail: the
                    // rail keeps only the tools touched mid-play.
                    _MenuChoice(
                      icon: Icons.save_outlined,
                      label: 'Save state',
                      detail: 'Keep your place and stay in the game '
                          '(listed on the Resume screen)',
                      onTap: () {
                        // Resume first: the capture reads a running core.
                        _setMenu(false);
                        unawaited(_saveStateInPlace());
                      },
                    ),
                    if (_siblingDisks.length > 1) ...[
                      const SizedBox(height: 12),
                      _MenuChoice(
                        icon: Icons.album,
                        label: 'Swap disk',
                        detail:
                            'Put another disk of this game in the drive',
                        onTap: () {
                          _setMenu(false);
                          unawaited(_swapDisk());
                        },
                      ),
                    ],
                    const SizedBox(height: 12),
                    _MenuChoice(
                      icon: Icons.aspect_ratio,
                      label: 'Screen shape: '
                          '${getIt<VideoSettings>().aspect.label}',
                      detail: 'Tap for the next mode',
                      onTap: () {
                        final settings = getIt<VideoSettings>();
                        final modes = AspectMode.values;
                        settings.setAspect(modes[
                            (settings.aspect.index + 1) % modes.length]);
                        setState(() {});
                      },
                    ),
                    const SizedBox(height: 12),
                    _MenuChoice(
                      icon: Icons.bookmark_add_outlined,
                      label: 'Save and exit',
                      detail: 'Snapshot this session and return to the workbench',
                      onTap: () => unawaited(_saveAndExit()),
                    ),
                    const SizedBox(height: 12),
                    _MenuChoice(
                      icon: Icons.close,
                      label: 'Close',
                      detail: 'End the session and return to the workbench',
                      onTap: () => unawaited(_close()),
                    ),
                  ],
                ),
              ),
            ],
            // The in-game tool rail, down the right edge where the thumb
            // already is. Hidden while the menu is up -- the menu IS the
            // controls then.
            if (!_menuOpen)
              Positioned(
                right: 4,
                top: 0,
                bottom: 0,
                child: AnimatedOpacity(
                  opacity: _controlsVisible ? 1 : 0,
                  duration: const Duration(milliseconds: 200),
                  child: IgnorePointer(
                    ignoring: !_controlsVisible,
                    child: Center(
                      child: SessionToolRail(
                        ui: vm.emulatorUi,
                        padMode: vm.padMode,
                        onPadModeChanged: vm.setPadMode,
                        joystickPort: vm.joystickPort,
                        onJoystickPortChanged: vm.setJoystickPort,
                        onWake: _wakeControls,
                        listenable: vm,
                      ),
                    ),
                  ),
                ),
              ),
            // The corner handle: the one control that is always reachable.
            // ☰ opens the pause menu; while the menu is up it reads ▶ and
            // resumes, so the same corner always undoes itself.
            Positioned(
              left: 4,
              top: 4,
              child: AnimatedOpacity(
                opacity: (_controlsVisible || _menuOpen) ? 1 : 0.25,
                duration: const Duration(milliseconds: 200),
                child: Material(
                  color: const Color(0x66000000),
                  shape: const CircleBorder(),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: () {
                      _wakeControls();
                      _setMenu(!_menuOpen);
                    },
                    child: SizedBox(
                      width: 40,
                      height: 40,
                      child: Icon(
                        _menuOpen ? Icons.play_arrow : Icons.menu,
                        color: Colors.white,
                        size: 22,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

}

/// The big centred resume control on the pause menu.
class _ResumeButton extends StatelessWidget {
  final VoidCallback onTap;

  const _ResumeButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: ViceColors.accentCyan,
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: const SizedBox(
          width: 72,
          height: 72,
          child: Icon(Icons.play_arrow, color: Colors.black, size: 44),
        ),
      ),
    );
  }
}

/// A pause-menu row: icon, name, and a line saying what it will do.
class _MenuChoice extends StatelessWidget {
  final IconData icon;
  final String label;
  final String detail;
  final VoidCallback onTap;

  const _MenuChoice({
    required this.icon,
    required this.label,
    required this.detail,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xE0181C20),
      borderRadius: BorderRadius.circular(10),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          width: 320,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Icon(icon, color: Colors.white, size: 22),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w600)),
                    Text(detail,
                        style: const TextStyle(
                            color: Colors.white54, fontSize: 11)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
