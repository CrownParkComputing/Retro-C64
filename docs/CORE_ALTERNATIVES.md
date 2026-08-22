# Replacing VICE: what the options actually are

Research done 2026-08-22, prompted by `LICENCE_COMPLIANCE.md`: VICE is
GPL v2 or later, and GPL and the App Store are a known conflict. This asks
what could take its place. Everything below was checked against the source,
not recalled — where something was built and run, it says so.

## Summary

There is a good answer, and it is not a rewrite. **VirtualC64's core is
dual-licensed GPL-3.0-or-later OR MPL-2.0**, per file, with SPDX tags. Taking
the MPL option removes the whole problem: MPL 2.0 is file-level copyleft with
no "no further restrictions" clause and no anti-Tivoization, and ships on the
App Store routinely (Firefox for iOS is MPL).

It has the thing a permissive C64 core normally lacks: **real 1541
emulation**, with D64 and G64. It also already embeds the MEGA65 Open ROMs as
a hex dump — the same out-of-the-box story we just built, for free.

**It builds, and the spike passed on all four questions.** See
`native/vc64_spike/` for the code, the frames and how to re-run it:

| | Question | Result |
|---|---|---|
| 1 | Boots with no Commodore ROM? | **Yes** — on the Open ROMs it embeds |
| 2 | Runs `assets/demo/demo.prg`? | **Yes** — same text as the VICE frame |
| 3 | Loads a real `.d64` through the 1541? | **Yes** — `LOADING FROM $0801 TO $9158`, `READY.` |
| 4 | Runs a commercial title on real ROMs? | **Yes** — 1942 reaches its high-score screen |

That is the compatibility question answered with evidence rather than
reputation: real drive emulation, a real disk image, a real game.

**A finding worth knowing:** the Open ROMs include no 1541 DOS ROM, so disk
images still need Commodore's drive ROM — exactly as under VICE. Changing
cores does not buy a disk-based demo.

Two upstream portability slips, both one-liners on Linux/GCC:
`Joystick.cpp` uses `INT_MAX` without including `<climits>`, and `warpOn(0)`
throws because source 0 is reserved for the warp config itself.

## The candidates

| Core | Licence | Disk (D64) | SID | Verdict |
|---|---|---|---|---|
| **VICE 3.10** (current) | GPL-2.0-or-later | yes, the reference | reSID | the problem |
| **VirtualC64 `VCCore`** | **GPL-3.0-or-later OR MPL-2.0** | **yes, real 1541** | reSID (GPL) — swappable | **recommended** |
| floooh/chips `systems/c64.h` | Zlib | **no** — `c1541_insert_disc` is a `// FIXME` stub | m6581.h, zlib, from tedplay/Unlicense | excellent, but no disk |
| kondrak/rust64 | MIT | no | partial | a study project |
| libsidplayfp | GPL-2.0 | n/a | n/a | same problem |
| MAME | mixed, GPL-2.0 overall | yes | yes | same problem, much heavier |
| ovalcode/c64_flutter | **none declared** | no | none | see below |

## On `ovalcode/c64_flutter`

Worth looking at, and it is not a foundation.

**It has no licence.** Public on GitHub with no LICENSE file means all rights
reserved — the identical trap this repo is in. Building on it needs the
author's written permission first, so it cannot be a way *out* of a licensing
problem.

**It is early.** Sixteen Dart files, about 60 KB: `cpu.dart` (26 KB),
`vicii.dart` (7.9 KB), `cia1.dart`, `tape.dart`. No SID at all, so no sound.
No second CIA, no disk, no cartridge, no save states. A 7.9 KB VIC-II is a
scanline renderer, not the cycle-exact chip that sprite and border tricks
need. The README is still the unedited `flutter create` template.

Against what Retro-C64 already ships — D64/D71/D81/G64, TAP/T64, CRT,
PRG/P00, SID music, save states — it is a fraction, and the missing part is
the hard part.

## On rewriting the emulator in Dart

The licence problem is a licence problem. Changing language does not solve
it and adds two large risks:

**Accuracy.** A C64 that runs commercial software has to survive fastloaders,
VSP, sprite and border tricks, and 1541 GCR timing. VICE has thirty years of
those edge cases; VirtualC64 has fifteen. That is the asset being discarded,
and it is worth far more than the code.

**Performance.** Roughly a million CPU cycles a second, VIC-II work on every
one of them, and SID at 44.1 kHz. Dart AOT can do a lot, but this is exactly
the tight bit-twiddling loop where it is furthest from C, and the target
includes older phones. It would also break the pattern the whole Retro-*
family is built on — one native core behind an FFI bridge — for no licensing
gain.

If a Dart core is wanted, it is a separate project for its own sake, not the
answer to this question.

## What switching to VirtualC64 would actually cost

Not small, and worth costing honestly before committing:

1. **reSID has to go.** It is GPL-2.0-or-later, and despite the `SIDBase`
   name the `SID` class holds a concrete `ReSID resid` member — it is not a
   virtual backend. Swapping in chips' `m6581.h` (zlib, derived from tedplay
   under the Unlicense, no reSID heritage) means editing MPL files, which the
   MPL permits so long as those files' modifications are published. Expect a
   SID accuracy regression; the Music tab is a listed feature.
2. **D71 and D81 disappear.** VirtualC64 is 1541-only. The store listing
   currently promises D71 and D81, so either the listing changes or those
   users lose something.
3. **The Core Settings screen is VICE-shaped.** It is driven by VICE's
   resource table (`resources_get_int` and friends). VirtualC64 has its own
   configuration API, so that screen is a rewrite, not a re-point.
4. **A new bridge.** `vice_bridge.c` becomes a C++ shim over `VirtualC64.h`.
   The existing `ViceCore` FFI interface is close in shape — start, media,
   framebuffer, keys, joystick, snapshots — so the Dart side above it largely
   survives.
5. **C++20 on the NDK and on iOS** needs proving before anything else.

## Is it worth doing at all?

Two datapoints on how the risk behaves in practice:

* **Delta** is AGPL-3.0 and is on the App Store. Its author holds the
  copyright, so he can grant whatever additional permission he likes. That is
  the position we are *not* in.
* **RetroArch** is GPL-3.0, has hundreds of contributors, cannot realistically
  relicense, and is not on the iOS App Store.

Retro-C64 with VICE is in RetroArch's position. The risk is not rejection at
review — App Review does not read licences — it is a complaint from any one
copyright holder, at any time, with removal as the outcome. VLC is the
precedent.

## Recommendation

1. **Spike it.** Build `VC64Headless` (done — it works), then drive it from
   the existing test harness: boot with Open ROMs, run `assets/demo/demo.prg`,
   load a real `.d64`, and compare against the VICE frames already captured.
   That answers the compatibility question with evidence rather than
   reputation, and costs a day.
2. **Only then decide.** If the spike holds up, the migration is a known
   quantity: MPL core, zlib SID, new bridge, settings screen rewritten.
3. **Meanwhile add a LICENSE to this repo** and keep shipping. That gap is
   real today and takes five minutes; the core swap is weeks.
