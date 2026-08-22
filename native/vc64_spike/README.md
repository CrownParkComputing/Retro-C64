# VirtualC64 spike

Does the MPL-2.0 core in `docs/CORE_ALTERNATIVES.md` actually do the job?

`Spike.cpp` answers it by running the thing and looking at the pixels, the
same way the VICE work was checked. It is not a port and not a benchmark.

## Result: yes, on all four questions

| | Question | Result |
|---|---|---|
| 1 | Boots with no Commodore ROM? | **Yes** — on the MEGA65 Open ROMs it embeds itself |
| 2 | Runs `assets/demo/demo.prg`, the file the app ships? | **Yes** — same text as the VICE frame |
| 3 | Loads a real `.d64` through the emulated 1541? | **Yes** — `LOADING FROM $0801 TO $9158`, then `READY.` |
| 4 | Runs a commercial title with real ROMs? | **Yes** — 1942 boots to its high-score screen |

Frames in `evidence/`.

Case 3 ends in `?SYNTAX ERROR` if you then type RUN, which is not a fault:
the file loads, but Open ROMs' BASIC has no variables and cannot run a
commercial title. Case 4 is the same disk with Commodore's ROMs, and the
game runs.

## The finding that changes nothing but is worth knowing

**The Open ROMs do not include a 1541 DOS ROM.** Connecting a drive without
one throws `ROM_DRIVE_MISSING`. Disk images therefore still need Commodore's
drive ROM — exactly as they do under VICE. Changing cores does not buy a
disk demo; the demo is a `.prg` for a reason.

## Two upstream portability slips

Both hit on Linux/GCC, both one-liners:

1. `Peripherals/Joystick/Joystick.cpp` uses `INT_MAX` without including
   `<climits>`. GCC rejects it; Clang pulls it in transitively. Worth
   sending upstream.
2. `warpOn(0)` throws — source 0 is reserved for the warp-mode config
   itself. Use any other source id.

## Running it

VirtualC64 is not vendored here; this file is meant to be dropped into a
checkout of it.

```sh
git clone --depth 1 https://github.com/dirkwhoffmann/VirtualC64.git
cd VirtualC64/VCCore
cp /path/to/this/Spike.cpp .
sed -i '0,/#include/s//#include <climits>\n#include/' Peripherals/Joystick/Joystick.cpp
cat >> CMakeLists.txt <<'EOF'
add_executable(VC64Spike Spike.cpp vcdebug.cpp)
target_link_libraries(VC64Spike VCCore)
EOF
cmake -S . -B build -DCMAKE_BUILD_TYPE=Release && cmake --build build -j8
./build/VC64Spike <demo.prg> <game.d64> <outdir>
```

Cases 3 and 4 read Commodore ROMs from a local VICE install
(`/usr/share/vice/...`). Those are not ours and are not committed anywhere;
point the paths at your own set.

## What it does not answer

* SID. reSID is still in the build here. Replacing it with a permissive
  engine, and how much accuracy that costs, is untested.
* Speed on a phone. This ran warped on a desktop.
* C++20 under the Android NDK and on iOS.
* D71/D81. VirtualC64 is 1541-only, and the store listing promises them.
