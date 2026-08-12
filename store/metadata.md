# App Store product page

Draft copy for App Store Connect. Field limits are Apple's; the counts in
brackets are what the text below actually uses.

App ID 6800389617 -- `com.vicemultiplatform.app`

## Name (30 max)

    C64-Retro Emulator                                    [18]

## Subtitle (30 max)

    Commodore 64, on your iPad                            [26]

## Promotional text (170 max, editable without a new build)

    A full Commodore 64 in your hands: load disk images, tapes, cartridges
    and SID music, with save states and a library that organises itself.
                                                          [138]

## Description (4000 max)

    C64-Retro Emulator brings the Commodore 64 to iPad, built on VICE, the
    emulator that has been the reference for C64 accuracy for over thirty
    years.

    LOAD WHAT YOU ALREADY HAVE
    Disk images (D64, D71, D81, G64), tapes (TAP, T64), cartridges (CRT),
    programs (PRG, P00) and SID music. Drop files in through the Files app
    or open them in from anywhere on your device -- zipped downloads work
    as they are, no unpacking required.

    A LIBRARY THAT ORGANISES ITSELF
    Everything you import is catalogued automatically, with artwork support
    and a history of what you have been playing.

    SAVE STATES
    Stop anywhere and pick it up later, exactly where you left it.

    BUILT-IN CONTROLS
    On-screen joystick and keyboard laid out for touch, with full support
    for MFi and Bluetooth controllers.

    IMPORTANT: ROMS ARE NOT INCLUDED
    Like every C64 emulator, this app needs the Commodore ROM files
    (kernal, basic, chargen) to start, plus the 1541 drive ROM for disk
    images. Those are Commodore's copyright and cannot be distributed with
    the app, so you supply your own -- dump them from a C64 you own, use a
    licensed set such as C64 Forever, or copy them from an existing VICE
    installation. The app scans for them and files them in the right place
    automatically; a zipped ROM set works without unpacking.

    Without those files the emulator will not boot. Please make sure you
    can supply them before buying or installing.

## Keywords (100 max, comma separated, no spaces after commas)

    c64,commodore,retro,emulator,vice,8bit,sid,d64,disk,tape,cartridge,classic,vintage,computer
                                                          [91]

## URLs

- **Support URL** (required): https://github.com/CrownParkComputing/ViceMultiplatform
- **Marketing URL** (optional): leave blank
- **Privacy Policy URL** (required): NEEDS CREATING -- see below

## Category

- Primary: **Games > Simulation**
- Secondary: **Utilities**

Apple permits retro game console emulators (App Review Guideline 4.7).
The app emulates hardware only and ships no games, which is the condition.

## Age rating

4+. No objectionable content of its own. Note that the questionnaire asks
about user-generated content -- this app loads local files the user
supplies and has no sharing, chat, or user-to-user features.

## App privacy

**Data Not Collected.** No analytics, no accounts, no tracking, no network
calls except the optional artwork host the user configures themselves,
which is off unless they set it.

## Copyright

    2026 Crown Park Computing

---

# Blockers before this page can be submitted

## 1. Privacy policy URL -- required, does not exist

Every app needs one, even collecting nothing. Cheapest route: add
`PRIVACY.md` to the repo and enable GitHub Pages, or link the file
directly. Text can be three lines: the app collects nothing, stores
everything locally, and makes no network requests except an
artwork host the user opts into.

## 2. Screenshots -- thin, and none show the emulator running

Only two exist (library, history) and neither shows a C64 screen. The
product page's job is to show the thing working; a reviewer also sees
these. Shoot at least one running a game, then:

    tools/make-store-screenshots.py

## 3. iPhone screenshots -- required while the app claims iPhone support

`UIDeviceFamily` is `[1, 2]`, so App Store Connect will demand a 6.9"
iPhone set and cannot be satisfied with padded iPad captures. Either shoot
them on an iPhone or set `TARGETED_DEVICE_FAMILY = 2` and ship iPad-only.

## 4. App Review notes -- the highest rejection risk here

A reviewer installing this gets an emulator that will not boot, because
they have no ROMs. Without an explanation that reads as a broken app, and
"app is non-functional" is a common rejection. Put this in the notes
field:

    This is a hardware emulator for the Commodore 64 (1982), permitted
    under guideline 4.7. It ships with no games and no system ROMs.

    The Commodore system ROMs are still under copyright and cannot legally
    be distributed with the app, so the user supplies their own, exactly as
    with every other C64 emulator. On first launch the app explains this
    and offers a scan that finds and installs them.

    To evaluate a working emulator, place any C64 ROM set (kernal, basic,
    chargen, and dos1541 for disk images) in the app's Documents folder via
    Files, then use Paths > Scan for ROMs. A zipped set works as-is.

    Without those files the app intentionally shows setup guidance rather
    than a black screen.

Consider bundling the MEGA65 project's free/open replacement ROMs so the
app boots to a usable BASIC without any user action -- worth checking
their licence and compatibility first, but it would remove this risk
entirely and make the first-run experience far better.
