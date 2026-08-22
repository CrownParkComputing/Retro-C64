# Licence compliance, and the App Store

Written 2026-08-22, after bundling the Open ROMs; corrected the same day when
the Open ROMs licence turned out to be the LESSER GPL rather than the GPL.
Read this before the next submission: one item is a genuine takedown risk and
two are gaps that are cheap to close.

## What the app is built from

| Component | Licence | Where |
|---|---|---|
| VICE 3.10 (the whole emulated machine) | **GPL v2 or later** | linked as `libvicecore.so` |
| reSID (SID emulation, inside VICE) | GPL v2 or later | inside the above |
| Open ROMs — BASIC, KERNAL, charset | **LGPL v3 or later** | `assets/vice/OPENROMS/`, in every build |
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
* **The Open ROMs are the LESSER GPL, and that matters.** An earlier draft
  of this document called them GPL v3 and built a whole recommendation on it.
  They are LGPL v3 or later. The upstream repository carries both COPYING
  (GPL v3) and COPYING.LESSER, because the LGPL is written as an additional
  permission on top of the GPL — so reading only COPYING, which is what
  happened, gets the licence wrong.

  The practical difference is large. The LGPL's condition is that the user be
  able to replace the covered part with their own version. Here the covered
  part is a ROM image the emulator loads from a directory at run time, and
  replacing it with a different ROM is not merely possible but the app's
  central feature — the ROM import exists for exactly that. That condition is
  satisfied by the design rather than by a workaround, which is not something
  that can be said of GPL v3 §6 Installation Information on a signed iOS
  binary.

  So the Open ROMs are a much smaller exposure than the emulator they run on.

### What to do

**About the Open ROMs: nothing.** LGPL v3, a run-time-replaceable data file,
both licence texts shipped, copyright holders named in About and in
`assets/vice/OPENROMS/README.txt`. That is the LGPL satisfied. The earlier
recommendation here — write to the MEGA65 authors for a distribution
exception — was a response to a licence they do not use. It is worth doing
only as a courtesy, not as a blocker.

**About VICE: make a deliberate decision.** `CORE_ALTERNATIVES.md` researches
the replacement question and finds a real answer — VirtualC64's core is
dual-licensed GPL-3 *or* MPL-2, has genuine 1541 emulation, and builds and
runs here. That does not make the swap free; read the costs there.
 GPL v2 is the real exposure and it
predates all of this work. The options are the familiar ones — ship and accept
the risk, or seek an exception from the copyright holders, who for a project
of VICE's age and size are many. Shipping is the status quo and this document
exists so that it is a choice on the record rather than an oversight.

**Close the two gaps above regardless.** They are cheap, they are required by
both licences, and the licence file is a five-minute job.

None of this touches the Commodore ROMs, which the app has always been right
about: they are not distributed, and the user supplies their own.
