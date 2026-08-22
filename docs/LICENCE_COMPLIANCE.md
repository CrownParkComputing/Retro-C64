# Licence compliance, and the App Store

Written 2026-08-22, after bundling the Open ROMs. Read this before the next
submission: one item here is a genuine takedown risk and two are gaps that
are cheap to close.

## What the app is built from

| Component | Licence | Where |
|---|---|---|
| VICE 3.10 (the whole emulated machine) | **GPL v2 or later** | linked as `libvicecore.so` |
| reSID (SID emulation, inside VICE) | GPL v2 or later | inside the above |
| Open ROMs — BASIC, KERNAL, charset | **GPL v3** | `assets/vice/OPENROMS/`, in every build |
| Retro-C64 itself (Flutter app + bridge) | **none declared** | this repo |

The app links VICE directly, so the shipped binary is a combined work and
the GPL applies to the whole of it, not only to the core.

## Gap 1 — the repo declares no licence

`github.com/CrownParkComputing/Retro-C64` is public with no LICENSE file.
Public is not the same as licensed: with nothing declared the default is
all rights reserved, which is not a state a GPL-derived work can be
distributed in. Add a `LICENSE` (GPL v2 or later, to match VICE) at the
repo root.

Closed in the app itself: About > "Licences and source" now names each
licence and links to the source, which is what GPL v2 §3 and v3 §6 require
of anyone distributing binaries.

## Gap 2 — the source offer must match what was shipped

The GPL wants the complete corresponding source for **the binary you
distributed**. This repo does not vendor VICE: `linux/CMakeLists.txt` points
at a checkout outside the tree (`~/AndroidStudioProjects/VICE-source/
vice-3.10`). If that checkout has any local modification, the published
source no longer corresponds to the shipped binary.

Cheapest fix: confirm the VICE tree is unmodified upstream 3.10, record its
exact version and checksum in the repo, and keep the bridge and build
scripts in-tree (they already are). If it has been patched, the patches have
to be published.

## The real risk — GPL and the App Store

This is the item to make a deliberate decision about rather than discover.

Apple's App Store terms impose conditions on everyone who receives an app:
a limited number of devices, no redistribution, DRM. Both GPL v2 §6 and
GPL v3 §10 forbid imposing any further restriction on the rights the licence
grants. The Free Software Foundation's position is that the two cannot be
satisfied at once, and this is not theoretical — VLC (GPL v2) was removed
from the App Store in 2011 after a copyright holder complained, and only
returned once it had been relicensed.

Two things follow:

* **App Review does not check licences.** No submission has ever been
  rejected for this. The risk is a complaint afterwards, from any one of the
  copyright holders, and the outcome is removal rather than a warning.
* **Bundling the Open ROMs raises the exposure.** VICE is GPL v2 and has
  been shipping in this app already. The Open ROMs are GPL **v3**, which adds
  the Installation Information requirement that iOS code signing cannot
  satisfy — the harder of the two conflicts. They are compiled into every
  build as assets, whether or not the user ever taps "See it working".

### Options, worst to best

1. **Ship as-is.** Accepts the risk knowingly. It is the status quo for the
   GPL v2 core; the change is that a v3 component now rides along.
2. **Drop the Open ROMs from the iOS build only.** Keeps the demo on
   Android, Linux and macOS-outside-the-store, and returns iOS to
   "bring your own ROMs" — which is the listing text we have just spent
   effort removing.
3. **Download the Open ROMs on first use instead of bundling them.** Apple
   then never distributes the GPL v3 files; the app fetches them from the
   MEGA65 project. Removes the v3 exposure entirely. Costs a network call on
   an app that currently, and usefully, claims to make none, and the demo
   stops working offline.
4. **Ask the MEGA65 open-roms authors for written permission** to distribute
   their ROMs through the App Store — an "additional permission" under
   GPL v3 §7. This is a normal request, the FSF publishes wording for it, the
   project is small and reachable, and a yes costs nothing and settles it
   permanently.

**Recommendation: 4, and start it now** — it is a single email and it is the
only option that keeps the demo, keeps the app offline, and removes the
sharpest edge. Ship on option 1 in the meantime if the timing demands it,
with the decision recorded here rather than left implicit.

None of this touches the Commodore ROMs, which the app has always been right
about: they are not distributed, and the user supplies their own.
