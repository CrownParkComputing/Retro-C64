// The History tab's content.
//
// Content, not logic -- but content that claims to be a top TWENTY and a
// timeline in order, and both of those are the kind of thing that quietly
// stops being true when someone edits the list.
import 'package:flutter_test/flutter_test.dart';
import 'package:retro_c64/data/c64_history.dart';

void main() {
  test('the top twenty has twenty entries, ranked 1..20 with no gaps', () {
    expect(C64History.topGames, hasLength(20));
    expect(
      C64History.topGames.map((g) => g.rank).toList(),
      List<int>.generate(20, (i) => i + 1),
    );
  });

  test('no game is listed twice', () {
    final titles = C64History.topGames.map((g) => g.title.toLowerCase());
    expect(titles.toSet(), hasLength(C64History.topGames.length));
  });

  test('every entry actually says something', () {
    for (final g in C64History.topGames) {
      expect(g.title.trim(), isNotEmpty, reason: 'rank ${g.rank}');
      expect(g.credit.trim(), isNotEmpty, reason: g.title);
      // A one-liner that does not explain why it is on the list is filler.
      expect(g.why.length, greaterThan(30), reason: g.title);
    }
  });

  test('composers are named with both credits and a note', () {
    expect(C64History.composers.length, greaterThanOrEqualTo(6));
    for (final c in C64History.composers) {
      expect(c.name.trim(), isNotEmpty);
      expect(c.known.trim(), isNotEmpty, reason: c.name);
      expect(c.note.trim(), isNotEmpty, reason: c.name);
    }
    // The two names most associated with the machine.
    final names = C64History.composers.map((c) => c.name).toList();
    expect(names, contains('Rob Hubbard'));
    expect(names, contains('Martin Galway'));
  });

  test('the timeline runs forwards', () {
    int yearOf(String s) =>
        int.parse(RegExp(r'\d{4}').firstMatch(s)!.group(0)!);
    final years = C64History.timeline.map((e) => yearOf(e.year)).toList();
    for (var i = 1; i < years.length; i++) {
      expect(years[i], greaterThanOrEqualTo(years[i - 1]),
          reason: 'out of order at "${C64History.timeline[i].year}"');
    }
    // The two dates that bracket the machine's commercial life.
    expect(years.first, lessThanOrEqualTo(1982));
    expect(years.last, 1994);
  });

  test('the disputed sales figure is presented as disputed', () {
    // The unit total has never been settled; stating one number as fact
    // would be the easiest thing here to get wrong.
    expect(C64History.intro.toLowerCase(), contains('never been settled'));
  });

  test('specs and notable sections are populated', () {
    expect(C64History.specs.length, greaterThanOrEqualTo(5));
    expect(C64History.notable.length, greaterThanOrEqualTo(4));
    for (final (title, body) in C64History.notable) {
      expect(title.trim(), isNotEmpty);
      expect(body.length, greaterThan(40), reason: title);
    }
  });
}
