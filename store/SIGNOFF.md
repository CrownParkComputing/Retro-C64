# Submission signoff — evidence

What has been proved, how, and what is still only provable on the Mac.
Written 2026-08-22 against Flutter 3.47.1.

## The claim the store listing now makes

> Setup offers a demo that runs straight away, using a free, open-source ROM
> set built into the app.

Everything below exists to make that claim checkable rather than asserted.

## Proved here (Linux, headless, reproducible)

| # | Claim | How it was proved |
|---|---|---|
| 1 | The bundled Open ROMs boot a real C64 | `x64sc` with only those three ROMs reaches `OPEN ROMS GENERIC BUILD … READY.` |
| 2 | The demo runs with **no Commodore ROM present** | `vice_openroms_demo_test <romdir> demo.prg out.ppm inject` against a directory holding only the Open ROMs — no `DRIVES`, no 1541 ROM. Frame captured and read. |
| 3 | The same demo runs on a **real** ROM set | same test, real ROM dir, VFS mode. Frame captured. |
| 4 | Real titles still start the way they always did | Raid over Moscow autostarts under the virtual-filesystem path; it does **not** under injection, which is why the mode follows the ROMs. |
| 5 | The demo ROMs install under names the core opens | `test/services/demo_roms_service_test.dart` — the filenames are VICE's own defaults, not descriptive ones. |
| 6 | The demo lands where the library actually scans | same test file: installed into a scanned root, `LibraryScanner` lists it as playable `prg`. |
| 7 | Nothing regressed | `flutter test` — 201 pass. Three failures are compile errors in tests belonging to the in-flight workbench refactor, not this work. |

Re-run 2 and 3 with:

    cd native/vice_core/linux
    cmake --build build --target vice_openroms_demo_test
    ./build/vice_openroms_demo_test <openroms-dir> flutter_app/assets/demo/demo.prg out.ppm inject

## Still to prove on the Mac (device only)

- [ ] First run on a clean install: setup → **See it working** → **Go to games**
      → **Retro-C64 Demo** → C64 boots and runs it. **This is the exact path
      the review notes give Apple, so it has to be walked once on a real
      device before submitting.**
- [ ] The same from an app that is already set up: **Paths → App Store /
      Play Store compliance → Use free ROMs**, then the demo in Games — and
      **Restore my ROMs** puts a real set back. Worth walking with real ROMs
      installed, because that is the case where a bug would destroy them.
- [ ] The same on a device with a real ROM set imported: demo still runs, and
      a normal `.d64` still loads (this is what the autostart-mode switch
      changes, and the two paths are mutually exclusive).
- [ ] About > **Licences and source** renders and its links open.
- [ ] Screenshots for the listing. The demo gives a screenshot that needs no
      copyrighted game on screen — worth using for at least one slot.

## Store fields changed this round

- `store/review-notes.txt` — now leads with the one-minute demo path. Previously
  it told the reviewer to go and find ROMs, which is the worst possible first
  instruction to give someone evaluating an emulator.
- `store/metadata/version/1.0.0/en-GB.json` — description and promotional text.
  Removed *"Without those files the emulator will not boot. Please make sure you
  can supply them before buying or installing"*: it is no longer true, and it was
  the most discouraging sentence on the page.
- `store/metadata.md` — the prose source of truth, kept in step.

Apply with the `asc` commands at the top of `store/metadata.md`. The JSON is
what is actually applied; the prose file is documentation.

## Read before submitting

`docs/LICENCE_COMPLIANCE.md`. The app is a GPL combined work with VICE
(GPL v2 or later) and the repo declares no licence at all. Neither will be
caught by App Review, and the first is a complaint-driven takedown risk that
predates this work and needs a decision on the record.

The bundled Open ROMs are **LGPL v3**, not GPL — checked against upstream
rather than assumed, after an earlier draft here got it wrong. As a ROM image
the user can replace at run time, which is the app's central feature, the
LGPL's condition is met by the design. They are not the problem; VICE is.
