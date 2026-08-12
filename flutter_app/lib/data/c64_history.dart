// The content behind the History tab.
//
// Kept as data rather than baked into the widget so the screen stays a
// layout and the facts stay checkable in one place. Figures that are
// genuinely disputed say so instead of picking a number and sounding
// certain -- the units-sold total in particular has never been settled.

/// A dated entry in the machine's story.
class HistoryEvent {
  final String year;
  final String title;
  final String detail;
  const HistoryEvent(this.year, this.title, this.detail);
}

/// One of the all-time greats.
class NotableGame {
  final int rank;
  final String title;
  final String year;
  final String credit;
  final String why;
  const NotableGame(this.rank, this.title, this.year, this.credit, this.why);
}

/// A SID composer worth knowing.
class Composer {
  final String name;
  final String known;
  final String note;
  const Composer(this.name, this.known, this.note);
}

class C64History {
  C64History._();

  static const String intro =
      'The Commodore 64 went on sale in August 1982 at \$595 and stayed in '
      'production until Commodore collapsed in 1994 -- twelve years, which '
      'nothing else in home computing has matched. Estimates of how many '
      'were sold range from about 12.5 to 17 million; the true figure has '
      'never been settled, but either end makes it the best-selling single '
      'computer model ever built.';

  static const List<HistoryEvent> timeline = [
    HistoryEvent('1981', 'Two chips looking for a machine',
        'MOS Technology engineers designed the VIC-II video chip and the SID '
        'sound chip with no particular computer in mind. Commodore decided to '
        'build one around them, and had a prototype ready in a few months.'),
    HistoryEvent('Jan 1982', 'Shown at CES',
        'The 64 was announced at the Winter Consumer Electronics Show. Jack '
        'Tramiel ran Commodore on "computers for the masses, not the '
        'classes" -- and, unusually, Commodore owned its own chip foundry, so '
        'it could undercut everyone.'),
    HistoryEvent('Aug 1982', 'On sale at \$595',
        'Sold in department and toy shops rather than computer dealers, which '
        'is much of why it reached the volume it did. Price cuts followed '
        'fast; by 1983 it was under \$300 and the home-computer price war was '
        'on.'),
    HistoryEvent('1983', 'The 1541 arrives',
        'The disk drive that defined the platform, and its bottleneck: a '
        'whole computer in its own right with its own 6502, yet so slow that '
        'fast-loader software became an art form of its own.'),
    HistoryEvent('1984', 'Tramiel leaves',
        'Jack Tramiel walked out after a board dispute and bought Atari, '
        'setting up a rivalry between the two companies that ran for years.'),
    HistoryEvent('1985-89', 'The golden run',
        'European bedroom studios hit their stride. Budget labels put games '
        'out at a few pounds each, magazines printed type-in listings, and '
        'the demoscene grew out of crackers signing their work.'),
    HistoryEvent('1986', 'The 64C and GEOS',
        'A restyled case, and GEOS: a genuine windowing OS with a mouse '
        'pointer, word processor and desktop, running on a 1 MHz 8-bit '
        'machine with 64 KB.'),
    HistoryEvent('Apr 1994', 'Commodore goes under',
        'Commodore International filed for bankruptcy and production stopped. '
        'The scene did not: new games, demos and music are still released for '
        'the machine every year.'),
  ];

  /// Specs worth knowing, in the terms the emulator actually deals in.
  static const List<(String, String)> specs = [
    ('CPU', 'MOS 6510 at 0.985 MHz (PAL) / 1.023 MHz (NTSC)'),
    ('Memory', '64 KB RAM -- 38911 bytes free to BASIC, as the boot screen says'),
    ('Video', 'VIC-II: 320x200, 16 colours, 8 hardware sprites, smooth scrolling'),
    ('Sound', 'SID 6581 (later 8580): 3 voices, 4 waveforms, ring modulation, '
        'a real analogue filter'),
    ('Storage', '1541 floppy, Datasette tape, cartridges'),
    ('Library', 'Well over 10,000 commercial titles, and still counting'),
  ];

  /// Twenty that keep turning up on best-of lists. Ordering is a matter of
  /// taste and always will be -- this is a starting argument, not a verdict.
  static const List<NotableGame> topGames = [
    NotableGame(1, 'The Last Ninja', '1987', 'System 3',
        'Isometric Ninja epic with a Ben Daglish and Anthony Lees soundtrack '
        'that people still hum.'),
    NotableGame(2, 'Turrican II', '1991', 'Factor 5 / Rainbow Arts',
        'Vast run-and-gun that pushed the hardware harder than almost '
        'anything, with a Chris Hulsbeck score to match.'),
    NotableGame(3, 'Elite', '1985', 'Braben & Bell / Firebird',
        'An entire galaxy in 64 KB. Trade, fight, dock, repeat -- open-world '
        'gaming a decade before the term existed.'),
    NotableGame(4, 'Impossible Mission', '1984', 'Epyx',
        '"Another visitor! Stay a while... stay FOREVER!" -- speech synthesis '
        'that genuinely startled people in 1984.'),
    NotableGame(5, 'Paradroid', '1985', 'Andrew Braybrook / Hewson',
        'Take over robots by winning a circuit-board mini-game. Still one of '
        'the most original ideas on any platform.'),
    NotableGame(6, 'Boulder Dash', '1984', 'First Star Software',
        'Dig, collect, do not get crushed. A puzzle game with real physics '
        'and perfect pacing.'),
    NotableGame(7, 'Maniac Mansion', '1987', 'Lucasfilm Games',
        'The birth of SCUMM and of the modern adventure game, squeezed onto '
        'the 64.'),
    NotableGame(8, 'Wizball', '1987', 'Sensible Software',
        'Restore colour to a grey world. Odd, brilliant, and carried by '
        'Martin Galway at the top of his game.'),
    NotableGame(9, 'International Karate +', '1987', 'Archer Maclean',
        'Three-way fighting with animation nobody else was managing, by a '
        'programmer known for wringing the machine dry.'),
    NotableGame(10, 'Armalyte', '1988', 'Cyberdyne / Thalamus',
        'The shoot-em-up the C64 is measured by: huge bosses, no slowdown.'),
    NotableGame(11, 'Uridium', '1986', 'Andrew Braybrook / Hewson',
        'Metallic super-tanker blasting at a scroll speed that had no '
        'business running on this hardware.'),
    NotableGame(12, 'Sanxion', '1986', 'Stavros Fasoulas / Thalamus',
        'Twin-screen shooter, and the loading music alone made Thalamus '
        'famous.'),
    NotableGame(13, 'Pirates!', '1987', 'Sid Meier / MicroProse',
        'Sailing, sword-fighting, trade and politics in one open-ended game '
        'that refused to pick a genre.'),
    NotableGame(14, 'M.U.L.E.', '1983', 'Ozark Softscape / EA',
        'Four-player economic strategy that is still studied for how well its '
        'auctions work.'),
    NotableGame(15, 'Archon', '1983', 'Free Fall / EA',
        'Chess where taking a piece drops you into an arcade duel.'),
    NotableGame(16, 'Creatures', '1990', 'Apex Computer Productions',
        'Cartoon platforming with technical tricks -- and humour -- that the '
        'machine was not supposed to have left in it.'),
    NotableGame(17, 'Delta', '1987', 'Stavros Fasoulas / Thalamus',
        'A shooter remembered as much for Rob Hubbard\'s score as for the '
        'game.'),
    NotableGame(18, 'Ghosts \'n Goblins', '1986', 'Elite Systems',
        'A brutal arcade conversion that people played anyway, and Mark '
        'Cooksey\'s version of the theme.'),
    NotableGame(19, 'Turbo Outrun', '1989', 'US Gold',
        'Not the best conversion ever made, but Jeroen Tel\'s soundtrack is '
        'one of the finest things the SID ever produced.'),
    NotableGame(20, 'Mayhem in Monsterland', '1993', 'Apex Computer Productions',
        'Released after the machine was supposedly dead, and still the '
        'brightest, fastest platformer on it.'),
  ];

  static const List<Composer> composers = [
    Composer('Rob Hubbard',
        'Monty on the Run, Commando, Sanxion, Delta, International Karate',
        'The name most associated with the SID. Wrote his own player routine '
        'and used the chip in ways its designer had not planned.'),
    Composer('Martin Galway',
        'Wizball, Parallax, Comic Bakery, Arkanoid, Rambo',
        'Chased sounds the hardware was not meant to make, including sampled '
        'drums squeezed out of a chip with no sample channel.'),
    Composer('Jeroen Tel',
        'Cybernoid II, Turbo Outrun, Myth, Supremacy',
        'Of Maniacs of Noise, and still touring these tunes live decades '
        'later.'),
    Composer('Ben Daglish',
        'The Last Ninja, Trap, Deflektor, Krakout',
        'Melodic, folk-tinged writing that stood apart from everyone else on '
        'the machine.'),
    Composer('Chris Hulsbeck',
        'Turrican, Turrican II, The Great Giana Sisters',
        'Went on to score games for thirty years; the Turrican themes still '
        'get orchestral performances.'),
    Composer('Matt Gray',
        'Last Ninja 2, Driller, Fire and Ice',
        'Returned to the scene decades later and successfully crowdfunded a '
        'remaster of his own back catalogue.'),
    Composer('Tim Follin',
        'Ghouls \'n Ghosts, Agent X II, Bionic Commando',
        'Wrote wildly ambitious multi-part pieces that sound like prog rock '
        'played by a chip.'),
    Composer('David Whittaker',
        'Lazy Jones, Glider Rider, Shadow of the Beast',
        'Astonishingly prolific -- hundreds of scores across the 8- and '
        '16-bit era.'),
  ];

  /// The things people find surprising.
  static const List<(String, String)> notable = [
    ('The SID was designed by a synth builder',
        'Bob Yannes wanted a real instrument, not a beeper, and gave it '
        'envelopes, ring modulation and a resonant analogue filter. He left '
        'to co-found Ensoniq and build actual synthesisers. No two SID chips '
        'sound quite alike, because the filter varies between them.'),
    ('The disk drive was a computer',
        'The 1541 had its own CPU and RAM and talked to the 64 over a serial '
        'line so slow that loading a game could take minutes. Fast loaders '
        'reprogrammed the drive on the fly to beat it -- some games shipped '
        'their own.'),
    ('The demoscene started here',
        'Crackers signing their work with an intro turned into a competitive '
        'art form: raster bars, sprites multiplexed far past the eight the '
        'hardware has, and graphics in the border that is not supposed to be '
        'drawable at all. It is still going.'),
    ('The music was archived',
        'The High Voltage SID Collection preserves more than 50,000 tunes '
        'from the machine -- one of the most complete archives of any '
        'platform\'s music, maintained by volunteers since the 1990s.'),
    ('It never really stopped',
        'New games, demos and hardware are still produced. Commodore stopped '
        'making the 64 in 1994; nobody told the people using it.'),
  ];
}
