// Spike.cpp -- can VirtualC64's MPL-licensed core replace VICE for this app?
//
// Not a benchmark and not a port. It answers the three questions that decide
// whether the migration in docs/CORE_ALTERNATIVES.md is worth starting, and
// it answers them the same way the VICE work was checked: by running the
// thing and looking at the pixels.
//
//   1. Does it boot with NO Commodore ROM, on the Open ROMs it embeds?
//   2. Does it run our own demo.prg -- the file the app ships?
//   3. Does it load a real .d64, which is the whole reason for preferring it
//      over floooh/chips?
//
// Writes a PPM per case so the frames can be compared against the ones the
// VICE harness already captured.
//
// usage: Spike <demo.prg> <game.d64> <outdir>

#include "VirtualC64.h"
#include <cstdio>
#include <cstring>
#include <string>
#include <filesystem>
#include <thread>
#include <chrono>

using namespace vc64;

static void writePPM(const std::string& path, const u32* tex,
                     isize w, isize h) {
    FILE* f = fopen(path.c_str(), "wb");
    if (!f) { printf("  cannot write %s\n", path.c_str()); return; }
    fprintf(f, "P6\n%ld %ld\n255\n", (long)w, (long)h);
    for (isize i = 0; i < w * h; i++) {
        u32 p = tex[i];
        // The texture is little-endian RGBA; we want RGB bytes.
        unsigned char rgb[3] = {
            (unsigned char)(p & 0xff),
            (unsigned char)((p >> 8) & 0xff),
            (unsigned char)((p >> 16) & 0xff)
        };
        fwrite(rgb, 1, 3, f);
    }
    fclose(f);
}

// How much of the screen is not the background colour. A booted machine with
// text on it scores high; a black or uniform screen scores ~0. Crude on
// purpose: the frame is written out to be looked at, and this is only here so
// a total failure reports itself rather than producing a file nobody opens.
static long litPixels(const u32* tex, isize w, isize h) {
    u32 bg = tex[0];
    long lit = 0;
    for (isize i = 0; i < w * h; i++) if (tex[i] != bg) lit++;
    return lit;
}

// Emulator::computeFrame() is private, so the core is driven the way an app
// drives it: its own thread, in warp mode, and we wait in wall-clock time.
// Warp means these waits are worth many times their length in emulated
// frames, which is why a second here is generous rather than marginal.
static void settle(double seconds) {
    std::this_thread::sleep_for(
        std::chrono::milliseconds((long)(seconds * 1000)));
}

static void snap(VirtualC64& c64, const std::string& path, const char* label) {
    isize nr = 0, w = 0, h = 0;
    c64.videoPort.lockTexture();
    const u32* tex = c64.videoPort.getTexture(&nr, &w, &h);
    long lit = litPixels(tex, w, h);
    writePPM(path, tex, w, h);
    c64.videoPort.unlockTexture();
    printf("  %-22s %ldx%ld  %ld non-background pixels -> %s\n",
           label, (long)w, (long)h, lit, path.c_str());
}

int main(int argc, char** argv) {
    if (argc < 4) {
        printf("usage: %s <demo.prg> <game.d64> <outdir>\n", argv[0]);
        return 2;
    }
    const std::string prg = argv[1], d64 = argv[2], out = argv[3];

    printf("VirtualC64 %s (build %s)\n\n",
           VirtualC64::version().c_str(), VirtualC64::build().c_str());

    // ---- 1. Boot on the Open ROMs alone -------------------------------
    printf("1. boot with no Commodore ROM\n");
    VirtualC64 c64;
    c64.c64.installOpenRoms();
    c64.launch();
    c64.warpOn(1);   // source 0 is reserved for the warpMode config itself
    c64.powerOn();
    c64.run();
    settle(2.0);                            // well past the ROM banner
    snap(c64, out + "/vc64_boot.ppm", "open roms boot");

    // ---- 2. Our own demo.prg ------------------------------------------
    printf("2. run the demo .prg the app ships\n");
    try {
        c64.c64.flash(prg);                 // straight into memory, no drive
        c64.keyboard.autoType(std::string("run\n"));
        settle(2.0);
        snap(c64, out + "/vc64_demo.ppm", "demo.prg");
    } catch (const std::exception& e) {
        printf("  FAILED: %s\n", e.what());
    }

    // ---- 3. A real .d64 through the emulated 1541 ---------------------
    printf("3. load a real .d64 through the 1541\n");
    try {
        VirtualC64 c2;
        c2.c64.installOpenRoms();
        // The Open ROMs do NOT include a 1541 DOS ROM -- the drive needs
        // Commodore's, exactly as it does under VICE. That is the finding,
        // not a workaround: changing cores does not make disk images work
        // without the user's own ROMs. Connecting the drive before the ROM
        // is installed throws ROM_DRIVE_MISSING, so the order matters.
        const char* driveRom =
            "/usr/share/vice/DRIVES/dos1541-325302-01+901229-05.bin";
        c2.c64.loadRom(std::filesystem::path(driveRom), RomType::VC1541);
        c2.set(Opt::DRV_CONNECT, true, 0);
        c2.launch();
        c2.warpOn(1);   // source 0 is reserved for the warpMode config itself
        c2.powerOn();
        c2.run();
        settle(2.0);
        c2.drive8.insert(d64, false);
        settle(0.5);
        // LOAD"*",8,1 then RUN, typed the way a user would.
        c2.keyboard.autoType(std::string("load\"*\",8,1\n"));
        settle(40.0);            // a real 1541 is slow, even under warp
        snap(c2, out + "/vc64_d64_loaded.ppm", "d64 loaded");
        c2.keyboard.autoType(std::string("run\n"));
        settle(6.0);
        snap(c2, out + "/vc64_d64.ppm", "d64 running");
    } catch (const std::exception& e) {
        printf("  FAILED: %s\n", e.what());
    }

    // ---- 4. Real Commodore ROMs, real .d64, actually run it ----------
    // The one that decides compatibility. Open ROMs load the file fine but
    // cannot RUN a commercial title -- their BASIC has no variables. With
    // Commodore's own ROMs there are no excuses left.
    printf("4. real Commodore ROMs: load and run the same .d64\n");
    try {
        const char* romdir = "/usr/share/vice/C64/";
        const char* drives = "/usr/share/vice/DRIVES/";
        VirtualC64 c3;
        c3.c64.loadRom(std::filesystem::path(std::string(romdir) + "kernal-901227-03.bin"), RomType::KERNAL);
        c3.c64.loadRom(std::filesystem::path(std::string(romdir) + "basic-901226-01.bin"), RomType::BASIC);
        c3.c64.loadRom(std::filesystem::path(std::string(romdir) + "chargen-901225-01.bin"), RomType::CHAR);
        c3.c64.loadRom(std::filesystem::path(std::string(drives) + "dos1541-325302-01+901229-05.bin"), RomType::VC1541);
        c3.set(Opt::DRV_CONNECT, true, 0);
        c3.launch();
        c3.warpOn(1);
        c3.powerOn();
        c3.run();
        settle(2.0);
        c3.drive8.insert(d64, false);
        settle(0.5);
        c3.keyboard.autoType(std::string("load\"*\",8,1\n"));
        settle(40.0);
        c3.keyboard.autoType(std::string("run\n"));
        settle(10.0);
        snap(c3, out + "/vc64_real_run.ppm", "real roms, running");
    } catch (const std::exception& e) {
        printf("  FAILED: %s\n", e.what());
    }

    printf("\ndone\n");
    return 0;
}
