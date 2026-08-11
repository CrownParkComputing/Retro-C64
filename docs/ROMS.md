# C64 ROMs

The app does **not** ship Commodore's ROMs. `kernal`, `basic` and `chargen`
are third-party copyrighted images, and bundling them in a store build is the
usual reason an emulator submission is rejected. Users supply their own, the
same way VICE itself works on the desktop.

## What a user needs

| ROM | Size | Required | Without it |
|-----|------|----------|------------|
| KERNAL | 8192 | yes | the machine will not start |
| BASIC | 8192 | yes | the machine will not start |
| Character generator | 4096 | yes | the machine will not start |
| 1541 disk drive | 16384 | no | every `.d64` fails with `?DEVICE NOT PRESENT` |

Any VICE ROM set has all four. They are imported from **Paths → C64 ROMs →
Import ROMs...**, which accepts a folder, loose files, or (most usefully) a
zip — ROM sets are essentially always distributed zipped.

## Why importing is not just a copy

VICE opens ROMs *by name*: `C64_KERNAL_REV3_NAME` in the VICE source is
literally `"kernal-901227-03.bin"`, and the machine looks for that filename
in its data directory. A user's file might be called `kernal.bin`, so
`lib/services/rom_store.dart` matches each candidate by filename prefix
**and exact byte size**, then copies it under the canonical name into
`C64/` or `DRIVES/`.

The size check is not paranoia: a name-only match would happily install a
truncated download as the KERNAL, and the result is a machine that boots to
garbage with nothing on screen explaining why.

## What the app does without them

`ViceNativePaths.resolveRomDir()` returns null, the core is left
uninitialised rather than pointed at nothing, the Game Library shows a red
banner, and the Paths tab reports exactly which ROMs are absent. Importing
them initialises the core in place — no restart.

On a dev checkout `resolveRomDir()` also falls back to the test fixtures in
`native/vice_core/linux/test/testdata/`, so `flutter run -d linux` still
boots without importing anything. That path cannot exist in a packaged
build, so it never stands in for a real user's ROMs on a device.

## Note on the bundled SID tunes

`assets/sids/` still ships 20 SID files, which are also third-party
copyrighted works (Hubbard, Galway et al). They are what makes the Music tab
work out of the box. If the same reasoning that removed the ROMs should
apply to them, the same treatment works: drop the asset declaration and let
the Music tab list only what the user imports — it already does that for
everything beyond the bundled twenty.
