import 'c64_keys.dart';

/// A joystick direction an on-screen button can be bound to.
///
/// Deliberately separate from ViceJoyBits (which lives in the FFI layer):
/// this is a persisted user choice, so it needs a stable name of its own
/// that does not move if the bridge's bit values ever change.
enum JoyDirection {
  up('Up'),
  down('Down'),
  left('Left'),
  right('Right');

  const JoyDirection(this.label);

  final String label;

  static JoyDirection? byName(String name) {
    for (final d in JoyDirection.values) {
      if (d.name == name) return d;
    }
    return null;
  }
}

/// One extra on-screen button the user added, bound to either a C64
/// keyboard key or a joystick direction.
///
/// Two bindings rather than one because games ask for both. A keyboard key
/// covers SPACE to start and RUN/STOP to abort; a direction covers the games
/// that want UP for jump, where reaching for the stick mid-run is worse than
/// a dedicated button sitting under your thumb.
///
/// Exactly one of [key] and [direction] is set. A/B stay fire buttons and
/// the joystick stays the joystick -- these are always additional.
class CustomButton {
  final C64Key? key;
  final JoyDirection? direction;

  const CustomButton.key(C64Key this.key) : direction = null;
  const CustomButton.direction(JoyDirection this.direction) : key = null;

  bool get isDirection => direction != null;

  String get label => key?.label ?? direction!.label;

  /// Stable identity for de-duplication. Prefixed per kind so a key and a
  /// direction can never collide.
  String get id => key != null ? 'key:${key!.id}' : 'dir:${direction!.name}';

  Map<String, dynamic> toJson() => key != null
      ? {'label': key!.label, 'row': key!.row, 'column': key!.column}
      : {'direction': direction!.name};

  /// Reads one persisted entry, returning null if it is unusable.
  ///
  /// Understands the older key-only format, which had no 'direction' field
  /// and stored row/column directly -- buttons added before directions
  /// existed keep working rather than silently vanishing on upgrade.
  static CustomButton? fromJson(Map<String, dynamic> entry) {
    final directionName = entry['direction'];
    if (directionName is String) {
      final direction = JoyDirection.byName(directionName);
      return direction == null ? null : CustomButton.direction(direction);
    }

    final row = entry['row'];
    final column = entry['column'];
    if (row is! int || column is! int) return null;
    final known = C64KeyCatalogue.find(row, column);
    return CustomButton.key(
      known ?? C64Key(entry['label'] as String? ?? '?', row, column),
    );
  }
}
