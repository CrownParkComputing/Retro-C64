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
enum WorkbenchCategory {
  resume('🚀', 'Resume'),
  games('🎮', 'Games'),
  music('🎵', 'Music'),
  paths('📂', 'Paths'),
  video('📺', 'Video'),
  audio('🔊', 'Audio'),
  input('🕹️', 'Input'),
  about('ℹ️', 'About');

  final String icon;
  final String title;
  const WorkbenchCategory(this.icon, this.title);

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
