// getting_started.dart — The paged guide the setup wizard teaches with,
// ported from Retro-Amiga. The generic widget is copied verbatim; the steps
// speak Commodore 64.
import 'dart:io';

import 'package:flutter/material.dart';

/// One page of the getting-started guide.
class GuideStep {
  const GuideStep({
    required this.title,
    required this.icon,
    required this.body,
  });

  final String title;
  final IconData icon;
  final List<Widget> body;
}

/// The paged guide: a title, a body, and Back/Next.
class GettingStartedGuide extends StatefulWidget {
  const GettingStartedGuide({
    super.key,
    required this.steps,
    this.onClose,
    this.onBack,
    this.closeLabel = 'Done',
  });

  final List<GuideStep> steps;

  /// Where the guide goes when it is finished or dismissed, or null when it
  /// IS the screen.
  final VoidCallback? onClose;

  /// Where Back goes from the FIRST page. Without it, backing out of page one
  /// runs onClose -- which in a wizard means the Back button carries you
  /// forwards to the next step, which is worse than doing nothing.
  final VoidCallback? onBack;

  /// What the last page's button says.
  final String closeLabel;

  @override
  State<GettingStartedGuide> createState() => _GettingStartedGuideState();
}

class _GettingStartedGuideState extends State<GettingStartedGuide> {
  final PageController _controller = PageController();
  int _at = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _go(int to) {
    if (to < 0) {
      final VoidCallback? back = widget.onBack;
      if (back != null) back();
      return;
    }
    if (to >= widget.steps.length) {
      final VoidCallback? close = widget.onClose;
      if (close == null) return _controller.jumpToPage(0);
      return close();
    }
    _controller.animateToPage(
      to,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.steps.isEmpty) return const SizedBox.shrink();
    final int at = _at.clamp(0, widget.steps.length - 1);
    final GuideStep step = widget.steps[at];
    final bool last = at == widget.steps.length - 1;

    return Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 12, 16, 0),
          child: Row(
            children: <Widget>[
              if (widget.onClose != null)
                IconButton(
                  icon: const Icon(Icons.close),
                  tooltip: 'Close the guide',
                  onPressed: widget.onClose,
                )
              else
                const SizedBox(width: 12),
              Icon(step.icon, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  step.title,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              Text(
                '${at + 1} of ${widget.steps.length}',
                style: Theme.of(context).textTheme.labelSmall,
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: (at + 1) / widget.steps.length,
              minHeight: 4,
            ),
          ),
        ),
        Expanded(
          child: PageView.builder(
            controller: _controller,
            itemCount: widget.steps.length,
            onPageChanged: (int i) => setState(() => _at = i),
            itemBuilder: (BuildContext context, int i) => ListView(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
              children: widget.steps[i].body,
            ),
          ),
        ),
        const Divider(height: 20),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
          child: Row(
            children: <Widget>[
              OutlinedButton(
                onPressed: (at == 0 && widget.onBack == null)
                    ? null
                    : () => _go(at - 1),
                child: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Text('Back'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: () => _go(at + 1),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(last ? widget.closeLabel : 'Next'),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// The teaching pages, written for someone who has never run an emulator.
class GettingStartedSteps {
  const GettingStartedSteps._();

  static Widget _p(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Text(text, style: const TextStyle(height: 1.45)),
      );

  static Widget _point(IconData icon, String title, String body) => Card(
        margin: const EdgeInsets.only(bottom: 10),
        child: ListTile(
          leading: Icon(icon),
          title: Text(title),
          subtitle: Text(body),
          isThreeLine: body.length > 60,
        ),
      );

  /// "What is this thing and what do I need?"
  static GuideStep whatYouNeed() => GuideStep(
        title: 'What a C64 needs',
        icon: Icons.help_outline,
        body: <Widget>[
          _p(
            'This app is a Commodore 64 — a computer from 1982 — running '
            'inside your device, via VICE. Like the real machine, it needs '
            'two things: the chips that make it a C64, and something to run.',
          ),
          _point(
            Icons.memory,
            'ROMs',
            'The machine\'s built-in software (KERNAL, BASIC, character '
                'set, and the 1541 drive ROM for disks). Free replacements '
                'are built in — the MEGA65 team\'s Open ROMs — so the C64 '
                'boots right now; Commodore\'s own ROMs run more software '
                'and are picked up automatically if you supply them.',
          ),
          _point(
            Icons.videogame_asset_outlined,
            'Games and programs',
            'Usually .d64 (a disk), .t64/.tap (a tape), .prg (a program) '
                'or .crt (a cartridge). Often inside a .zip, which is fine.',
          ),
          if (Platform.isIOS)
            _point(
              Icons.speed,
              'One thing iOS cannot do',
              'Apple does not allow an app to generate code while it runs, '
                  'so no emulator on the App Store has a JIT. Everything here '
                  'is set up to run as well as it can without one.',
            ),
        ],
      );

  /// "I finished setup -- now what?"
  static GuideStep firstGame() => GuideStep(
        title: 'Playing your first game',
        icon: Icons.sports_esports_outlined,
        body: <Widget>[
          _p('From the Games shelf, tap a title. Disks, tapes, cartridges '
              'and .prg files all autostart -- no LOAD"*",8,1 needed '
              '(though the keyboard is right there if you want the '
              'nostalgia).'),
          _point(
            Icons.menu,
            'The corner button',
            'While playing, the button in the top-left corner opens the '
                'pause menu: resume, save your place, swap disks, screen '
                'shape, or leave.',
          ),
          _point(
            Icons.videogame_asset_outlined,
            'The tool rail',
            'Down the right edge while playing: the C64 keyboard, the '
                'on-screen pad, the joystick port swap, and moving the '
                'controls. "Nothing moves" almost always means the wrong '
                'port -- tap P1/P2.',
          ),
          _point(
            Icons.save_outlined,
            'Your place is kept',
            'Save and exit keeps your place, and the last five sessions '
                'are kept automatically either way. The Resume screen '
                'lists them with pictures.',
          ),
        ],
      );

  /// The platform's own answer to "where do I put my files?".
  static GuideStep whereFilesGo() {
    if (Platform.isIOS) {
      return GuideStep(
        title: 'Where to put your files',
        icon: Icons.folder_special_outlined,
        body: <Widget>[
          _p(
            'On iPhone and iPad an app may only see its own folder. That is '
            'Apple\'s rule for every app, not something this one chose.',
          ),
          _point(
            Icons.looks_one_outlined,
            'Open the Files app',
            'It is on your home screen — the blue folder.',
          ),
          _point(
            Icons.looks_two_outlined,
            'Tap "On My iPhone" or "On My iPad"',
            'Then open the folder named Retro-64. The app creates it on '
                'first run.',
          ),
          _point(
            Icons.looks_3_outlined,
            'Put your files in it',
            'Put your .d64, .tap, .prg and .zip files in it. '
                'Long-press a file anywhere in Files, choose Copy, then '
                'paste it here.',
          ),
          _p('Then come back and tap Rescan.'),
        ],
      );
    }
    if (Platform.isAndroid) {
      return GuideStep(
        title: 'Where to put your files',
        icon: Icons.folder_special_outlined,
        body: <Widget>[
          _p(
            'On Android you keep your collection wherever you like — '
            'including an SD card — and simply show the app where it is. '
            'Nothing is copied and nothing is moved: the app reads your '
            'disks and tapes where they already are.',
          ),
          _point(
            Icons.folder_open,
            'Choose the folder',
            'Pick the folder your games live in, or the '
                'folder above them. Everything inside it is included.',
          ),
          _point(
            Icons.rule_folder_outlined,
            'The "All files access" question',
            'The app reads your games in place rather than copying them — '
                'and Android requires the All files access permission for '
                'that. The wizard opens the system page; switch it on for '
                'Retro-64 and come back. If you would rather not grant it, '
                'a single folder can be granted through the system picker '
                'in Paths instead.',
          ),
          _point(
            Icons.sd_card_outlined,
            'SD cards and USB drives',
            'They work exactly the same way — with the permission granted, '
                'the folder picker can use them like any other folder.',
          ),
        ],
      );
    }
    return GuideStep(
      title: 'Where to put your files',
      icon: Icons.folder_special_outlined,
      body: <Widget>[
        _p(
          'Choose the folder your games live in — anywhere '
          'on disk works, and everything inside the folder is included.',
        ),
      ],
    );
  }
}
