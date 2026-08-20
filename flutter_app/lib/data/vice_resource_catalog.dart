/// The options worth putting a proper control on, out of the several hundred
/// resources VICE has.
///
/// Everything the machine knows is browsable on the Core screen's "All
/// resources" list -- that comes from the core itself and cannot go stale.
/// This catalogue is the opposite trade: a hand-written label, an
/// explanation, and the legal values for the settings people actually reach
/// for, because `SidModel=1` is not a user interface.
///
/// A name that the running machine does not have is skipped, not an error:
/// the same catalogue has to survive a VICE upgrade and a different machine
/// model without the screen breaking.
library;

enum ViceResourceKind { toggle, choice }

class ViceResourceChoice {
  final int value;
  final String label;

  const ViceResourceChoice(this.value, this.label);
}

class ViceResourceOption {
  /// VICE's own resource name. `%d` is substituted with the drive number
  /// (8), matching resources_set_int_sprintf's convention in the bridge.
  final String name;
  final String label;
  final String description;
  final ViceResourceKind kind;

  /// For [ViceResourceKind.choice]; the value order is the display order.
  final List<ViceResourceChoice> choices;

  const ViceResourceOption.toggle({
    required this.name,
    required this.label,
    required this.description,
  })  : kind = ViceResourceKind.toggle,
        choices = const [];

  const ViceResourceOption.choice({
    required this.name,
    required this.label,
    required this.description,
    required this.choices,
  }) : kind = ViceResourceKind.choice;
}

class ViceResourceSection {
  final String title;
  final List<ViceResourceOption> options;

  const ViceResourceSection(this.title, this.options);
}

const List<ViceResourceSection> kViceCommonResources = [
  ViceResourceSection('Speed', [
    ViceResourceOption.toggle(
      name: 'WarpMode',
      label: 'Warp mode',
      description: 'Runs the machine as fast as the device can, with no '
          'sound. Turn it on to skip a slow load, off to play.',
    ),
    ViceResourceOption.toggle(
      name: 'AutostartWarp',
      label: 'Warp through loading',
      description: 'Warps automatically while a disk or tape autostarts, '
          'then drops back to normal speed. This is what turns a 90-second '
          '1541 load into a few seconds.',
    ),
    ViceResourceOption.choice(
      name: 'Speed',
      label: 'Emulation speed',
      description: 'Percent of real machine speed. 0 is unlimited.',
      choices: [
        ViceResourceChoice(0, 'Unlimited'),
        ViceResourceChoice(50, '50%'),
        ViceResourceChoice(100, '100% (real speed)'),
        ViceResourceChoice(200, '200%'),
      ],
    ),
  ]),
  ViceResourceSection('Drives', [
    ViceResourceOption.toggle(
      name: 'Drive8TrueEmulation',
      label: 'True drive emulation (drive 8)',
      description: 'Emulates the 1541\'s own CPU. Needed by fastloaders and '
          'copy-protected disks; much slower to load without warp.',
    ),
    ViceResourceOption.choice(
      name: 'Drive8Type',
      label: 'Drive 8 type',
      description: 'Which drive is attached as device 8. NONE means device 8 '
          'does not exist, which is what ?DEVICE NOT PRESENT is telling you.',
      choices: [
        ViceResourceChoice(0, 'None'),
        ViceResourceChoice(1541, '1541'),
        ViceResourceChoice(1542, '1541-II'),
        ViceResourceChoice(1570, '1570'),
        ViceResourceChoice(1571, '1571'),
        ViceResourceChoice(1581, '1581'),
      ],
    ),
    ViceResourceOption.toggle(
      name: 'DriveSoundEmulation',
      label: 'Drive sounds',
      description: 'The 1541\'s stepper and motor, as heard through the TV.',
    ),
    ViceResourceOption.choice(
      name: 'AutostartPrgMode',
      label: 'PRG autostart',
      description: 'How a .prg is handed to the machine.',
      choices: [
        ViceResourceChoice(0, 'Virtual filesystem'),
        ViceResourceChoice(1, 'Inject into RAM'),
        ViceResourceChoice(2, 'Copy to a disk image'),
      ],
    ),
  ]),
  ViceResourceSection('Machine', [
    ViceResourceOption.choice(
      name: 'MachineVideoStandard',
      label: 'Video standard',
      description: 'PAL is the European machine (50Hz), NTSC the American '
          '(60Hz). Games written for one often run wrong on the other.',
      choices: [
        ViceResourceChoice(1, 'PAL-G'),
        ViceResourceChoice(2, 'NTSC-M'),
        ViceResourceChoice(3, 'Old NTSC-M'),
        ViceResourceChoice(4, 'PAL-N (Drean)'),
      ],
    ),
    ViceResourceOption.choice(
      name: 'SidModel',
      label: 'SID model',
      description: 'The 6581 is the original filter-heavy chip; the 8580 is '
          'the later, cleaner one. Music written for one sounds wrong on the '
          'other.',
      choices: [
        ViceResourceChoice(0, '6581'),
        ViceResourceChoice(1, '8580'),
        ViceResourceChoice(2, '6581 (ReSID-fp)'),
        ViceResourceChoice(3, '8580 (ReSID-fp)'),
      ],
    ),
    ViceResourceOption.toggle(
      name: 'SidFilters',
      label: 'SID filters',
      description: 'Emulates the analog filter. Off is louder and flatter.',
    ),
  ]),
  ViceResourceSection('Video', [
    ViceResourceOption.choice(
      name: 'VICIIFilter',
      label: 'VIC-II filter',
      description: 'The core\'s own picture filter, separate from the render '
          'options on the Video page.',
      choices: [
        ViceResourceChoice(0, 'None'),
        ViceResourceChoice(1, 'CRT emulation'),
        ViceResourceChoice(2, 'Scale2x'),
      ],
    ),
    ViceResourceOption.toggle(
      name: 'VICIIDoubleSize',
      label: 'Double size',
      description: 'Renders at 2x internally before the picture is scaled.',
    ),
    ViceResourceOption.toggle(
      name: 'VICIIVSPBug',
      label: 'VSP bug',
      description: 'Emulates the VSP fault that certain demos rely on -- and '
          'that killed real machines.',
    ),
  ]),
];
