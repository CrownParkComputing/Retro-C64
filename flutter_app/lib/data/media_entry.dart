import 'category.dart';

/// A single scanned media file. IGDB box-art lookup (entry.igdbGame in the
/// Android app) is deferred -- placeholder tiles show the extension label
/// instead, same fallback the Android app itself uses while a lookup is
/// pending or unavailable.
class MediaEntry {
  final String displayName;
  final String path;
  final MediaFormatFilter mediaType;

  const MediaEntry({
    required this.displayName,
    required this.path,
    required this.mediaType,
  });

  String get extensionLabel {
    final dot = displayName.lastIndexOf('.');
    if (dot < 0 || dot == displayName.length - 1) return '?';
    return displayName.substring(dot + 1).toUpperCase();
  }

  String get baseName {
    final dot = displayName.lastIndexOf('.');
    return dot > 0 ? displayName.substring(0, dot) : displayName;
  }

  static MediaFormatFilter filterForExtension(String ext) {
    switch (ext.toLowerCase()) {
      case 'd64':
      case 'd71':
      case 'd81':
      case 'g64':
        return MediaFormatFilter.disk;
      case 'tap':
      case 't64':
        return MediaFormatFilter.tape;
      case 'crt':
        return MediaFormatFilter.cartridge;
      case 'prg':
      case 'p00':
        return MediaFormatFilter.prg;
      default:
        return MediaFormatFilter.none;
    }
  }
}
