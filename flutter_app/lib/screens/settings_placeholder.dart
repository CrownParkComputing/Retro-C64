import 'package:flutter/material.dart';

/// Stand-in for the Paths / Video / Audio / Input / About tabs
/// (MainActivity.createPathsContent / createVideoContent / etc). Full
/// settings panels (folder pickers, bezel download, controller mapping,
/// IGDB config) are a deferred milestone -- this just proves each sidebar
/// destination routes somewhere and looks like part of the same app.
class SettingsPlaceholder extends StatelessWidget {
  final String title;
  final List<String> rows;

  const SettingsPlaceholder({super.key, required this.title, this.rows = const []});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text(title,
              style: const TextStyle(
                  color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
        ),
        for (final row in rows)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF191D22),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFF353B44)),
              ),
              child: Text(row, style: const TextStyle(color: Colors.white70)),
            ),
          ),
        if (rows.isEmpty)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('Deferred to a later milestone.',
                style: TextStyle(color: Colors.white38)),
          ),
      ],
    );
  }
}
