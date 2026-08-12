import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../ffi/vice_bindings.dart';
import '../ffi/vice_core.dart';
import '../services/app_prefs.dart';
import '../services/gamepad_service.dart';
import '../theme/vice_theme.dart';
import '../data/custom_button.dart';
import '../widgets/assignable_action_button.dart';
import '../widgets/custom_key_button.dart';
import '../widgets/c64_keyboard_overlay.dart';
import '../widgets/dpad_view.dart';
import '../widgets/wobble_joystick.dart';
import '../widgets/framebuffer_view.dart';
import '../widgets/media_activity_overlay.dart';

/// The in-emulator screen: full-screen framebuffer, on-screen wobble
/// joystick + A/B action buttons, an optional full C64 keyboard overlay,
/// external-gamepad support, and a slide-out Quick Settings panel -- port
/// of ViceMenuPanel.java's Host interface (joypad/screen-size/bezel/CRT
/// toggles + reset + back-to-library + close), each row showing its own
/// current-state label like the Android version.
class EmulatorScreen extends StatefulWidget {
  final ViceCore core;
  final String mediaLabel;
  final VoidCallback onBackToLibrary;
  final bool leftHanded;
  final GamepadService? gamepad;

  /// When the on-screen pad is shown (auto / always / never). Persisted by
  /// the workbench via AppPrefs; changeable from here so the user can flip
  /// it mid-game, which is when they usually want to. This is the ONLY
  /// joypad-visibility control -- there used to be a second, local
  /// show/hide toggle alongside it, which read as a duplicate row.
  final OnScreenPadMode padMode;
  final ValueChanged<OnScreenPadMode>? onPadModeChanged;

  /// Extra user-added on-screen buttons, each bound to a C64 keyboard key
  /// (see AppPrefs.getCustomButtons). Additional to A/B, which stay fire.
  final List<CustomButton> customButtons;

  /// Persists a change made from the in-game menu, so a button added
  /// mid-game survives to the next launch instead of only lasting the
  /// session.
  final ValueChanged<List<CustomButton>>? onCustomButtonsChanged;

  /// Which C64 joystick port (1 or 2) every input source drives.
  final int joystickPort;
  final ValueChanged<int>? onJoystickPortChanged;

  const EmulatorScreen({
    super.key,
    required this.core,
    required this.mediaLabel,
    required this.onBackToLibrary,
    this.leftHanded = false,
    this.gamepad,
    this.padMode = OnScreenPadMode.auto,
    this.onPadModeChanged,
    this.customButtons = const [],
    this.onCustomButtonsChanged,
    this.joystickPort = 2,
    this.onJoystickPortChanged,
  });

  @override
  State<EmulatorScreen> createState() => _EmulatorScreenState();
}

class _EmulatorScreenState extends State<EmulatorScreen> {
  bool _settingsOpen = false;
  bool _keyboardVisible = false;

  // The full joystick mask is the OR of three independent sources that must
  // never stomp on each other: the on-screen wobble joystick (directions),
  // the on-screen A/B buttons (fire, when not remapped to a key), and an
  // external gamepad (see gamepad_service.dart). Each source reports only
  // its own bits; _updateJoystick() combines them into the single
  // vice_core_joystick() call the bridge expects -- which is also the one
  // place the chosen PORT is applied, so every source follows the setting
  // automatically.
  int _dirMask = 0;
  int _fireMask = 0;
  int _padMask = 0;

  StreamSubscription<int>? _padSub;

  /// Which directional control to draw, and where the user has dragged the
  /// two control clusters. Both are read once on entry: they are settings,
  /// not live state, and re-reading them per frame would hit prefs on every
  /// rebuild of a screen that rebuilds constantly.
  JoystickStyle _joystickStyle = JoystickStyle.wobble;
  Map<String, Offset> _controlPositions = const {};

  /// Layout-edit mode: controls stop driving the emulator and start moving
  /// under the finger instead. Deliberately not persisted -- it is a mode
  /// you are in for ten seconds, and coming back into a game already in it
  /// would be baffling.
  bool _editingLayout = false;

  @override
  void initState() {
    super.initState();
    _padSub = widget.gamepad?.maskChanges.listen((mask) {
      _padMask = mask;
      _updateJoystick();
    });
    _loadControlLayout();
  }

  Future<void> _loadControlLayout() async {
    final style = await AppPrefs.getJoystickStyle();
    final positions = await AppPrefs.getControlPositions();
    if (!mounted) return;
    setState(() {
      _joystickStyle = style;
      _controlPositions = positions;
    });
  }

  /// Default spot for a cluster, as a fraction of the play area, used until
  /// the user drags it somewhere else. Mirrors with the left-handed setting,
  /// which is the whole point of that setting.
  Offset _defaultPosition(String id) {
    final stickOnLeft = !widget.leftHanded;
    final onLeft = (id == kControlIdStick) == stickOnLeft;
    return Offset(onLeft ? 0.13 : 0.87, 0.76);
  }

  Offset _positionFor(String id) =>
      _controlPositions[id] ?? _defaultPosition(id);

  void _moveControl(String id, Offset fraction) {
    setState(() {
      _controlPositions = {..._controlPositions, id: fraction};
    });
  }

  Future<void> _commitControlPosition(String id) async {
    final pos = _controlPositions[id];
    if (pos != null) await AppPrefs.setControlPosition(id, pos);
  }

  Future<void> _resetControlLayout() async {
    await AppPrefs.clearControlPositions();
    if (!mounted) return;
    setState(() => _controlPositions = const {});
  }

  @override
  void dispose() {
    _padSub?.cancel();
    super.dispose();
  }

  @override
  void didUpdateWidget(EmulatorScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The port changed under us (from Input Settings, say). Release the old
    // port so a held direction can't stay latched on a port nothing drives.
    if (oldWidget.joystickPort != widget.joystickPort) {
      widget.core.joystick(oldWidget.joystickPort, 0);
      _updateJoystick();
    }
  }

  String get _keyboardLabel => _keyboardVisible ? 'Keyboard shown' : 'Keyboard hidden';
  String get _portLabel => widget.joystickPort == 1
      ? 'Port 1 (some games)'
      : 'Port 2 (most games)';
  String get _padModeLabel =>
      '${widget.padMode.label} -- ${widget.padMode.description}';

  String get _customButtonsLabel {
    final count = widget.customButtons.length;
    if (count == 0) return 'Add a key or direction button';
    final names = widget.customButtons.map((b) => b.label).join(', ');
    return count == 1 ? '1 added: $names' : '$count added: $names';
  }

  /// Adds a button from inside the game. Closes the panel first: the picker
  /// is a modal, and leaving a full-height panel open behind it means
  /// dismissing two things to get back to play.
  Future<void> _addCustomButton() async {
    setState(() => _settingsOpen = false);
    final binding = await showC64KeyPicker(context);
    if (binding == null) return;
    widget.onCustomButtonsChanged
        ?.call([...widget.customButtons, binding]);
  }

  void _updateJoystick() =>
      widget.core.joystick(widget.joystickPort, _dirMask | _fireMask | _padMask);

  void _joystickDirections(bool up, bool down, bool left, bool right) {
    int mask = 0;
    if (up) mask |= ViceJoyBits.up;
    if (down) mask |= ViceJoyBits.down;
    if (left) mask |= ViceJoyBits.left;
    if (right) mask |= ViceJoyBits.right;
    _dirMask = mask;
    _updateJoystick();
  }

  void _setFireBit(int bit, bool down) {
    _fireMask = down ? (_fireMask | bit) : (_fireMask & ~bit);
    _updateJoystick();
  }

  /// A user-added direction button going down/up. It joins the same mask as
  /// A/B rather than the stick's: both are on-screen buttons, and keeping
  /// them separate from _dirMask means holding this button and pushing the
  /// stick combine (as they would on real hardware) instead of the last one
  /// to move overwriting the other.
  void _setDirectionButtonBit(JoyDirection direction, bool down) {
    _setFireBit(
      switch (direction) {
        JoyDirection.up => ViceJoyBits.up,
        JoyDirection.down => ViceJoyBits.down,
        JoyDirection.left => ViceJoyBits.left,
        JoyDirection.right => ViceJoyBits.right,
      },
      down,
    );
  }

  @override
  Widget build(BuildContext context) {
    final gamepadConnected = widget.gamepad?.connected;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // FramebufferView applies every video setting itself (aspect,
          // CRT, bezel, rotation) straight from VideoSettings.instance --
          // the emulator screen deliberately holds no display state of its
          // own any more. It used to keep local stretch/bezel/CRT booleans
          // that only relabelled Quick Settings rows while the render path
          // ignored them; those settings now live on the Video settings
          // screen, where they actually take effect.
          Positioned.fill(child: Center(child: FramebufferView(core: widget.core))),
          // Loading feedback (datasette counter / drive track) in the
          // letterbox band, with the Retro Recompilation logo there when
          // nothing is loading. Ignores pointer events so it can never sit
          // between the user and the on-screen controls below it.
          Positioned.fill(
            child: IgnorePointer(
              child: MediaActivityOverlay(core: widget.core),
            ),
          ),
          // On-screen virtual controls hide automatically while a real
          // gamepad is connected (see gamepad_service.dart) -- a sensible
          // default, but only a DEFAULT: on a handheld like the Retroid
          // Flip2 the built-in pad is always "connected", so auto-hide alone
          // meant the touch controls could never be shown at all. The
          // padMode setting (Auto/Always/Never) decides instead -- one
          // control, settable from Input settings or Quick Settings
          // mid-game. See AppPrefs.getOnScreenPadMode.
          //
          // Positioned.fill is load-bearing, not decoration: a Stack whose
          // children are ALL positioned takes constraints.biggest, but a
          // single non-positioned child makes it shrink-wrap that child
          // instead. This builder returns SizedBox.shrink() whenever the
          // controls are hidden (which is exactly what happens on a handheld
          // with a built-in gamepad), and as an unpositioned child that
          // collapsed the whole emulator Stack -- and with it the
          // framebuffer, the media label and the menu button -- to 0x0, i.e.
          // a black screen. Positioned keeps it out of the sizing decision,
          // so NEITHER branch of the visibility test can resize the Stack.
          Positioned.fill(
            child: ValueListenableBuilder<bool>(
              valueListenable: gamepadConnected ?? const _AlwaysFalse(),
              builder: (context, padConnected, _) {
                if (!widget.padMode
                    .visibleWith(controllerConnected: padConnected)) {
                  return const SizedBox.shrink();
                }
                // LayoutBuilder, because positions are stored as a fraction
                // of the play area and can only become pixels once that area
                // has a size (see AppPrefs.getControlPositions for why they
                // are fractions).
                return LayoutBuilder(builder: (context, constraints) {
                  final area = constraints.biggest;
                  return Stack(
                    children: [
                      _MovableControl(
                        id: kControlIdStick,
                        area: area,
                        fraction: _positionFor(kControlIdStick),
                        editing: _editingLayout,
                        label: 'Joystick',
                        onMoved: (f) => _moveControl(kControlIdStick, f),
                        onMoveEnd: () =>
                            _commitControlPosition(kControlIdStick),
                        child: switch (_joystickStyle) {
                          JoystickStyle.wobble =>
                            WobbleJoystick(onDirections: _joystickDirections),
                          JoystickStyle.dpad =>
                            DpadView(onDirections: _joystickDirections),
                        },
                      ),
                      _MovableControl(
                        id: kControlIdButtons,
                        area: area,
                        fraction: _positionFor(kControlIdButtons),
                        editing: _editingLayout,
                        label: 'Buttons',
                        onMoved: (f) => _moveControl(kControlIdButtons, f),
                        onMoveEnd: () =>
                            _commitControlPosition(kControlIdButtons),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            // User-added key buttons sit above the fire
                            // buttons rather than replacing them.
                            for (final binding in widget.customButtons) ...[
                              CustomKeyButton(
                                binding: binding,
                                core: widget.core,
                                onDirectionChanged: _setDirectionButtonBit,
                              ),
                              const SizedBox(height: 8),
                            ],
                            ActionButton(
                              label: 'A',
                              onFireBitChanged: (down) =>
                                  _setFireBit(ViceJoyBits.fire1, down),
                            ),
                            const SizedBox(height: 10),
                            ActionButton(
                              label: 'B',
                              onFireBitChanged: (down) =>
                                  _setFireBit(ViceJoyBits.fire2, down),
                            ),
                          ],
                        ),
                      ),
                    ],
                  );
                });
              },
            ),
          ),
          Positioned(
            top: 8,
            left: 0,
            right: 0,
            child: Center(
              child: Text(
                widget.mediaLabel,
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ),
          ),
          // Says what mode you are in and how to leave it. Without this the
          // controls just stop working and grow a border, which reads as a
          // bug rather than a mode.
          if (_editingLayout)
            Positioned(
              left: 0,
              right: 0,
              top: 34,
              child: Center(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.7),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.tealAccent, width: 1),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'Drag the controls where you want them',
                        style: TextStyle(
                            color: Colors.tealAccent,
                            fontSize: 12,
                            fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(width: 12),
                      GestureDetector(
                        onTap: _resetControlLayout,
                        child: const Text(
                          'RESET',
                          style: TextStyle(
                              color: Colors.orangeAccent,
                              fontSize: 12,
                              fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          if (_keyboardVisible)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: C64KeyboardOverlay(
                core: widget.core,
                onClose: () => setState(() => _keyboardVisible = false),
              ),
            ),
          // Keyboard and on-screen-pad toggles live here permanently rather
          // than inside Quick Settings. Both are things you reach for mid-game
          // -- a game wants the keyboard for its own menus, then wants it gone
          // again -- and burying a twice-a-minute action two taps deep in a
          // panel that covers the screen was the wrong trade.
          Positioned(
            right: 16,
            top: 16,
            child: Column(
              children: [
                FloatingActionButton.small(
                  heroTag: 'settingsFab',
                  backgroundColor: const Color(0xFF24292E),
                  onPressed: () => setState(() => _settingsOpen = !_settingsOpen),
                  child: const Icon(Icons.menu, color: Colors.white),
                ),
                const SizedBox(height: 10),
                FloatingActionButton.small(
                  heroTag: 'keyboardFab',
                  // Lit while the keyboard is up, so the button doubles as
                  // the indicator of its own state.
                  backgroundColor: _keyboardVisible
                      ? const Color(0xFF4040E0)
                      : const Color(0xFF24292E),
                  tooltip: _keyboardLabel,
                  onPressed: () =>
                      setState(() => _keyboardVisible = !_keyboardVisible),
                  child: const Icon(Icons.keyboard, color: Colors.white),
                ),
                const SizedBox(height: 10),
                FloatingActionButton.small(
                  heroTag: 'padFab',
                  backgroundColor: const Color(0xFF24292E),
                  tooltip: _padModeLabel,
                  onPressed: () =>
                      widget.onPadModeChanged?.call(widget.padMode.next),
                  child: const Icon(Icons.videogame_asset, color: Colors.white),
                ),
                const SizedBox(height: 10),
                // Layout editing lives out here beside the pad toggle, not
                // in Input Settings: you can only judge where a control
                // should go while looking at the game it has to sit on top
                // of, so the edit has to be reachable from in here.
                FloatingActionButton.small(
                  heroTag: 'layoutFab',
                  backgroundColor: _editingLayout
                      ? const Color(0xFF008080)
                      : const Color(0xFF24292E),
                  tooltip: _editingLayout
                      ? 'Finish moving controls'
                      : 'Move the on-screen controls',
                  onPressed: () =>
                      setState(() => _editingLayout = !_editingLayout),
                  child: Icon(_editingLayout ? Icons.check : Icons.open_with,
                      color: Colors.white),
                ),
              ],
            ),
          ),
          if (_settingsOpen)
            Positioned(
              top: 0,
              bottom: 0,
              right: 0,
              width: ViceMetrics.quickSettingsPanelWidth(
                  MediaQuery.of(context).size.width),
              child: _QuickSettingsPanel(
                portLabel: _portLabel,
                customButtonsLabel: _customButtonsLabel,
                onAddButton: _addCustomButton,
                onSwapPort: () => widget.onJoystickPortChanged
                    ?.call(widget.joystickPort == 1 ? 2 : 1),
                onReset: () {
                  widget.core.stop();
                  widget.core.start(mediaType: ViceMedia.none);
                },
                onGameLibrary: () {
                  setState(() => _settingsOpen = false);
                  widget.onBackToLibrary();
                },
                onClose: () => setState(() => _settingsOpen = false),
              ),
            ),
        ],
      ),
    );
  }
}

/// A [ValueListenable] stand-in for when no [GamepadService] was supplied
/// (keeps the ValueListenableBuilder above unconditional instead of
/// branching the whole overlay tree).
class _AlwaysFalse implements ValueListenable<bool> {
  const _AlwaysFalse();
  @override
  bool get value => false;
  @override
  void addListener(VoidCallback listener) {}
  @override
  void removeListener(VoidCallback listener) {}
}

/// One on-screen control cluster, placed by fraction and draggable while
/// [editing].
///
/// The child is positioned by its CENTRE, not its top-left corner, so that
/// nothing here needs to know how big the child is -- the button column
/// grows and shrinks as the user adds custom buttons, and measuring it would
/// mean a post-layout pass and a frame of the control in the wrong place.
///
/// While editing, an [AbsorbPointer] sits between the drag handler and the
/// control: without it a drag across the stick would also be a drag of the
/// stick, so setting up the layout would fire the joystick into whatever
/// game is paused behind the editor.
class _MovableControl extends StatelessWidget {
  const _MovableControl({
    required this.id,
    required this.area,
    required this.fraction,
    required this.editing,
    required this.label,
    required this.onMoved,
    required this.onMoveEnd,
    required this.child,
  });

  final String id;
  final Size area;
  final Offset fraction;
  final bool editing;
  final String label;
  final ValueChanged<Offset> onMoved;
  final VoidCallback onMoveEnd;
  final Widget child;

  /// Keeps a control from being dragged so far that its centre leaves the
  /// screen and it can never be grabbed again.
  static const _minFraction = 0.06;
  static const _maxFraction = 0.94;

  @override
  Widget build(BuildContext context) {
    final positioned = Positioned(
      left: fraction.dx * area.width,
      top: fraction.dy * area.height,
      child: FractionalTranslation(
        translation: const Offset(-0.5, -0.5),
        child: editing
            ? GestureDetector(
                behavior: HitTestBehavior.opaque,
                onPanUpdate: (d) {
                  if (area.width == 0 || area.height == 0) return;
                  onMoved(Offset(
                    (fraction.dx + d.delta.dx / area.width)
                        .clamp(_minFraction, _maxFraction),
                    (fraction.dy + d.delta.dy / area.height)
                        .clamp(_minFraction, _maxFraction),
                  ));
                },
                onPanEnd: (_) => onMoveEnd(),
                child: _editChrome(child),
              )
            : child,
      ),
    );
    return positioned;
  }

  Widget _editChrome(Widget inner) {
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.tealAccent, width: 2),
        borderRadius: BorderRadius.circular(12),
        color: Colors.black.withValues(alpha: 0.35),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.open_with, size: 14, color: Colors.tealAccent),
              const SizedBox(width: 4),
              Text(label,
                  style: const TextStyle(
                      color: Colors.tealAccent,
                      fontSize: 11,
                      fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 4),
          AbsorbPointer(child: inner),
        ],
      ),
    );
  }
}

class _QuickSettingsPanel extends StatelessWidget {
  final String portLabel, customButtonsLabel;
  final VoidCallback onSwapPort,
      onAddButton,
      onReset,
      onGameLibrary,
      onClose;

  const _QuickSettingsPanel({
    required this.portLabel,
    required this.customButtonsLabel,
    required this.onSwapPort,
    required this.onAddButton,
    required this.onReset,
    required this.onGameLibrary,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF0B0D10),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              const Expanded(
                child: Text('Quick Settings',
                    style: TextStyle(color: Colors.white, fontSize: 18)),
              ),
              IconButton(
                icon: const Icon(Icons.close, color: Colors.white),
                onPressed: onClose,
              ),
            ],
          ),
          // Deliberately short. This panel is for things you only discover
          // you need ONCE THE GAME IS RUNNING; set-once display preferences
          // (screen size, bezel, CRT) are not that, and now live on the
          // Video settings screen -- which is also the only place they ever
          // did anything, since the rows here drove local booleans the
          // render path never read.
          //
          // Port swap goes first: "nothing moves" is the first thing you
          // notice on a game that reads the other port, and this is the fix.
          _Card(icon: '🔀', title: 'Joystick Port', subtitle: portLabel, onTap: onSwapPort),
          // No keyboard or on-screen-pad row here. Both have a permanent
          // button in the corner of the game, lit to show their own state,
          // and a panel row that does the same thing is not a shortcut --
          // it is a second place to look, a second thing to keep in sync,
          // and a second answer to "where is the keyboard toggle?". The
          // buttons win because they are one tap from play; this panel is
          // three.
          // Adding a button belongs here as much as in Input settings: which
          // key or direction a game wants is something you find out by
          // playing it, and going out to Settings means leaving the game.
          _Card(
            icon: '➕',
            title: 'Add Button',
            subtitle: customButtonsLabel,
            onTap: onAddButton,
          ),
          _Card(icon: '↺', title: 'Reset C64', subtitle: 'Reset the running core', onTap: onReset),
          _Card(icon: '▦', title: 'Workbench', subtitle: 'Leave the game (it pauses and is saved)', onTap: onGameLibrary),
        ],
      ),
    );
  }
}

class _Card extends StatelessWidget {
  final String icon, title, subtitle;
  final VoidCallback onTap;
  const _Card({required this.icon, required this.title, required this.subtitle, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFF22272E),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFF3D4652)),
            ),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: const Color(0xFF303844),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFF596474)),
                  ),
                  child: Text(icon, style: const TextStyle(fontSize: 22)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          maxLines: 1,
                          style: const TextStyle(color: Colors.white, fontSize: 14)),
                      Text(subtitle,
                          maxLines: 2,
                          style: const TextStyle(color: ViceColors.accentTeal, fontSize: 11)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
