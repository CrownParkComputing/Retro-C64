// Mirrors LauncherLayoutHelper.Category (MainActivity's sidebar), same
// order, same labels (including the emoji -- they're part of the app's
// look, not decoration to drop).
//
// The four media-format entries (Disks/Tapes/Carts/PRG) used to live here
// as sidebar destinations too. They are NOT destinations any more: they're
// filters over one library, so they render as a row of tabs across the top
// of the library view instead (see MediaTab below / library_grid.dart).
// Music deliberately stays a sidebar destination -- it's the SID
// Workstation, not a media filter over the games library.
/// Icon and title are separate fields (rather than one "🎮 Games" string)
/// so the sidebar can put the icons in a fixed-width column and left-align
/// every title against each other -- emoji advance widths differ per glyph,
/// so a single concatenated string makes the titles start at slightly
/// different x positions.
/// Declaration order IS rail order, and [group] is the band it sits in:
///
///   0  where you go        Games, Resume
///   1  how it is set up    Paths, Video, Input, Core
///   2  everything else     Music, History, About  (pinned to the bottom)
///
/// Nine flat entries read as a list to be searched; three bands read as a
/// place to look. The bottom band is pinned so About stays where About
/// always is rather than drifting with the length of the band above it.
enum WorkbenchCategory {
  games('🎮', 'Games', 0),
  resume('🚀', 'Resume', 0),
  paths('📂', 'Paths', 1),
  video('📺', 'Video', 1),
  input('🕹️', 'Input', 1),
  core('⚙️', 'Core', 1),
  music('🎵', 'Music', 2),
  history('📜', 'History', 2),
  about('ℹ️', 'About', 2);

  final String icon;
  final String title;
  final int group;
  const WorkbenchCategory(this.icon, this.title, this.group);

  String get label => '$icon $title';
}

/// The media-format filter each library-ish category applies, mirroring
/// MainActivity.showLauncherCategory's activeFormatFilter assignment.
enum MediaFormatFilter { none, disk, tape, cartridge, prg }

/// The horizontal tabs across the top of the games library. `all` is the
/// unfiltered view the "Games" sidebar entry used to provide on its own.
enum MediaTab {
  all('All', MediaFormatFilter.none, 'Game Library'),
  disks('💾 Disks', MediaFormatFilter.disk, 'Disk Images'),
  tapes('📼 Tapes', MediaFormatFilter.tape, 'Tape Images'),
  carts('🕹️ Carts', MediaFormatFilter.cartridge, 'Cartridges'),
  programs('⌨️ PRG', MediaFormatFilter.prg, 'Programs');

  final String label;
  final MediaFormatFilter filter;
  final String title;
  const MediaTab(this.label, this.filter, this.title);
}

bool isLibraryCategory(WorkbenchCategory cat) =>
    cat == WorkbenchCategory.games;
