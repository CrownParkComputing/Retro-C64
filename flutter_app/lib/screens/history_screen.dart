import 'package:flutter/material.dart';

import 'package:retro_c64/data/c64_history.dart';
import 'package:retro_c64/theme/vice_theme.dart';

/// The History tab: what the machine was, the twenty games people keep
/// arguing about, who wrote the music, and the parts that surprise people.
///
/// The content lives in C64History; this file is only how it looks.
class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // Tabbed rather than one long scroll: five unrelated things -- specs, a
    // timeline, a top twenty, the composers, the trivia -- read as five
    // things, and hunting for the composers by scrolling past twenty games
    // is not reading, it is searching.
    return DefaultTabController(
      length: 5,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 14, 16, 2),
            child: Text('The Commodore 64',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.bold)),
          ),
          const TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            labelColor: ViceColors.accentCyan,
            unselectedLabelColor: Colors.white54,
            indicatorColor: ViceColors.accentCyan,
            dividerColor: Color(0xFF353B44),
            labelStyle: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
            tabs: [
              Tab(text: 'The machine'),
              Tab(text: 'How it happened'),
              Tab(text: 'Twenty greats'),
              Tab(text: 'Composers'),
              Tab(text: 'Worth knowing'),
            ],
          ),
          const Expanded(
            child: TabBarView(
              children: [
                _MachineTab(),
                _TimelineTab(),
                _TopGamesTab(),
                _ComposersTab(),
                _NotableTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

const _pad = EdgeInsets.fromLTRB(16, 14, 16, 24);

class _MachineTab extends StatelessWidget {
  const _MachineTab();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: _pad,
      children: [
        Text(
          C64History.intro,
          style: TextStyle(
              color: Colors.white.withValues(alpha: 0.85),
              fontSize: 13,
              height: 1.5),
        ),
        const SizedBox(height: 16),
        const _SectionHeader('SPECIFICATION'),
        _Panel(
          child: Column(
            children: [
              for (final (label, value) in C64History.specs)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 78,
                        child: Text(label,
                            style: const TextStyle(
                                color: ViceColors.accentCyan,
                                fontSize: 11,
                                fontWeight: FontWeight.bold)),
                      ),
                      Expanded(
                        child: Text(value,
                            style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 12,
                                height: 1.35)),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _TimelineTab extends StatelessWidget {
  const _TimelineTab();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: _pad,
      children: [
        for (final e in C64History.timeline)
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 72,
                  child: Text(e.year,
                      style: const TextStyle(
                          color: ViceColors.accentCyan,
                          fontSize: 12,
                          fontWeight: FontWeight.bold)),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(e.title,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.bold)),
                      const SizedBox(height: 2),
                      Text(e.detail,
                          style: const TextStyle(
                              color: Colors.white60,
                              fontSize: 12,
                              height: 1.4)),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _TopGamesTab extends StatelessWidget {
  const _TopGamesTab();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: _pad,
      children: [
        const Padding(
          padding: EdgeInsets.only(bottom: 12),
          child: Text(
            'Ordering is a matter of taste and always will be. Treat this as '
            'a starting argument.',
            style: TextStyle(color: Colors.white38, fontSize: 11),
          ),
        ),
        for (final g in C64History.topGames)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 32,
                  child: Text('${g.rank}',
                      style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.30),
                          fontSize: 17,
                          fontWeight: FontWeight.bold)),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Flexible(
                            child: Text(g.title,
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold)),
                          ),
                          const SizedBox(width: 6),
                          Text('${g.year}  ${g.credit}',
                              style: const TextStyle(
                                  color: ViceColors.accentCyan, fontSize: 10)),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(g.why,
                          style: const TextStyle(
                              color: Colors.white60,
                              fontSize: 12,
                              height: 1.4)),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _ComposersTab extends StatelessWidget {
  const _ComposersTab();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: _pad,
      children: [
        const Padding(
          padding: EdgeInsets.only(bottom: 12),
          child: Text(
            'On this machine the musicians were famous in their own right -- '
            'people bought games for the loading music.',
            style: TextStyle(color: Colors.white38, fontSize: 11),
          ),
        ),
        for (final c in C64History.composers)
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(c.name,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.bold)),
                const SizedBox(height: 2),
                Text(c.known,
                    style: const TextStyle(
                        color: ViceColors.accentCyan, fontSize: 11)),
                const SizedBox(height: 2),
                Text(c.note,
                    style: const TextStyle(
                        color: Colors.white60, fontSize: 12, height: 1.4)),
              ],
            ),
          ),
      ],
    );
  }
}

class _NotableTab extends StatelessWidget {
  const _NotableTab();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: _pad,
      children: [
        for (final (title, body) in C64History.notable)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _Panel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text(body,
                      style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                          height: 1.45)),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.label);
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Text(label,
              style: const TextStyle(
                  color: ViceColors.accentCyan,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.4)),
          const SizedBox(width: 10),
          const Expanded(child: Divider(color: Color(0xFF353B44), height: 1)),
        ],
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: ViceColors.cardFill,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF353B44)),
      ),
      child: child,
    );
  }
}
