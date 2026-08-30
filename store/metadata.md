# App Store product page

Copy for App Store Connect. Field limits are Apple's; the counts in brackets
are what the text below actually uses.

App ID 6800389617 -- `com.vicemultiplatform.app`

**This document is now the prose version.** The machine-readable copy lives in
`store/metadata/` and is what actually gets applied, with the `asc` CLI
(github.com/rorkai/App-Store-Connect-CLI):

    asc metadata validate --dir ./store/metadata
    asc metadata plan     --app 6800389617 --version 1.0.0 --dir ./store/metadata
    asc metadata approve  --review-dir .asc/metadata/review --all
    asc metadata apply    --app 6800389617 --version 1.0.0 --dir ./store/metadata \
                          --review-dir .asc/metadata/review --confirm

The locale is **en-GB**, not en-US: that is the app record's primary locale,
and Apple will not let you delete the primary localization, which is what a
switch to en-US amounts to.

The version string is **1.0.0**. It started as 1.0, and a build will not
attach to a version whose string does not match the build's own
`CFBundleShortVersionString`, which pubspec sets to 1.0.0. The error Apple
returns says only "The specified pre-release build could not be added".

## Name (30 max)

    Retro-C64                                             [9]

## Subtitle (30 max)

    Commodore 64, iPhone & iPad                           [27]

The old "Commodore 64, on your iPad" said iPad-only while the binary claims
both families, which is also why the description opens "iPhone and iPad".

## Promotional text (170 max, editable without a new build)

    A full Commodore 64 in your hands, working the moment you open it:
    disk images, tapes, cartridges and SID music, with save states and a
    library that organises itself.
                                                          [166]

## Description (4000 max)

    Retro-C64 brings the Commodore 64 to iPad, built on VICE, the
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

    WORKS THE MOMENT YOU OPEN IT
    Setup offers a demo that runs straight away, using a free,
    open-source ROM set built into the app. Nothing to find, nothing to
    download -- you can see a real emulated C64 boot before you decide
    anything.

    ABOUT COMMODORE'S ROMS
    Commercial C64 software was written against Commodore's own BASIC and
    KERNAL, which are still under copyright and cannot be distributed with
    any emulator. To run your old games you supply those yourself -- dump
    them from a C64 you own, use a licensed set such as C64 Forever, or
    copy them from an existing VICE installation. The app scans for them
    and files them in the right place automatically; a zipped ROM set
    works without unpacking. The built-in open ROMs are an independent
    reimplementation and will not run most commercial titles.

The old closing line -- "Without those files the emulator will not boot.
Please make sure you can supply them before buying or installing" -- was
true when written and is not any more: the app now ships the MEGA65 Open
ROMs and boots without anything from the user. Leaving it there would have
been both wrong and the single most discouraging sentence on the page.

## Keywords (100 max, comma separated, no spaces after commas)

    c64,commodore,retro,emulator,vice,8bit,sid,d64,disk,tape,cartridge,classic,vintage,computer
                                                          [91]

## URLs

- **Support URL** (required): https://github.com/CrownParkComputing/ViceMultiplatform
- **Marketing URL** (optional): leave blank
- **Privacy Policy URL** (required): https://www.crownparkcomputing.com/privacy

  That page is the WhittyApps policy, served from the `CPCIncGoogleApps` repo
  (`src/components/PrivacyPolicyPage.tsx`). It covered Google Play only and
  described accounts, analytics and advertising as though every app did all
  three, which contradicts the Data Not Collected declaration below -- Apple
  rejects a policy that disagrees with the privacy questionnaire. It now
  covers both stores and carries an "Apps That Collect No Data" section
  naming this app. Any change to what the app collects has to be reflected
  there as well as here.

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

# What is set, and what is left

Everything below was applied through `asc` against app 6800389617, version
1.0.0. `asc review doctor --app 6800389617` went from 34 blocking issues to 1.

## Applied

- **Name, subtitle, description, keywords, promotional text, support URL,
  privacy policy URL** -- from `store/metadata/`, locale en-GB.
- **Category**: primary Games with the Simulation subcategory, secondary
  Utilities. Apple permits retro console emulators under App Review
  Guideline 4.7; the app emulates hardware only and ships no games, which
  is the condition.
- **Age rating**: every declaration set to NONE/false, giving 4+. The
  questionnaire asks about user-generated content -- this app loads local
  files the user supplies and has no sharing, chat, or user-to-user
  features, so the answer is no.
- **Content rights**: does not use third-party content. The app ships no
  games, no ROMs and no media; VICE is code under licence, not content.
- **Copyright**: 2026 Crown Park Computing.
- **Availability**: all 175 territories, and automatically available in new
  ones. This has to be bootstrapped with an explicit territory list --
  `pricing availability create` rejects `--all-territories`, and
  `pricing availability edit` refuses to run before a record exists.
- **Price**: GBP 1.99, base territory GBR. The start date must not be in the
  future or Apple answers "Entire timeline must be covered for GBR".
- **Screenshots**: the two iPad 13" landscape captures as IPAD_PRO_3GEN_129,
  and iPhone 6.9" placeholders as APP_IPHONE_69. `asc screenshots upload`
  wants a locale directory inside `--path`, so the files go in
  `<path>/en-GB/`, not `<path>/`. Both sets are placeholders -- see below.

## Left

### 1. App Review contact phone -- blocking

`asc review details-create` fails with "must provide a value for the
attribute 'contactPhone'". Nothing else about the review details is
contentious; the notes are ready in `store/review-notes.txt`. Once there is
a number:

    asc review details-create --version-id 34afed8c-e192-481f-87d5-4f9611305f26 \
      --contact-email EMAIL --contact-first-name FIRST --contact-last-name LAST \
      --contact-phone PHONE --demo-account-required=false \
      --notes "$(cat store/review-notes.txt)"

### 2. A build -- done, and no new one was needed

Three builds were already uploaded and VALID on App Store Connect: 6, 7 and
8, all marketing version 1.0.0, all encryption-exempt. Build **8** is
attached. Builds 6 and 7 are refused with the same opaque "pre-release build
could not be added" -- Apple wants the highest build number, and 8 is the one
`docs/APP_STORE_RELEASE.md` records as the one that finally got through.

So the macos-14 `ios` job in `.github/workflows/build.yml` does not need
running again for this submission. Note that it only uploads the IPA as a
workflow artifact; it has no App Store upload step, so a future build has to
be sent with `asc builds upload` or Transporter.

### 3. Screenshots -- not blocking any more, and not shippable

Both raw captures are the same picture despite being named `1-library.png`
and `2-history.png`: the C64 booted to BASIC with

    LOAD"*",8,1
    SEARCHING FOR *
    ?DEVICE NOT PRESENT  ERROR

on screen. So the entire product page, iPad and iPhone, is two near-identical
images of a failed disk load. That is what a customer browsing the store sees
and what a reviewer opens first, and on an app whose main rejection risk is
"looks non-functional" it could hardly be worse. Nothing here is a real
library or history screen, so the old note in this file claiming otherwise
was wrong too.

Shoot a proper set: a game running, the library with artwork, the on-screen
controls in use. Then:

    tools/make-store-screenshots.py

and re-upload each set with `--replace`.

### 4. iPhone screenshots -- placeholders only

`UIDeviceFamily` is `[1, 2]` and `TARGETED_DEVICE_FAMILY` is `"1,2"`, so a
6.9" iPhone set is required and padded iPad captures cannot honestly satisfy
it. What is uploaded now is exactly that padding: a 4:3 iPad picture in a
2.2:1 frame, most of the image black. Apple accepted the upload, and
`asc review doctor` is satisfied because it only checks that some screenshot
set exists -- neither fact makes it fit to ship. Replace with real iPhone
captures.

The alternative is `TARGETED_DEVICE_FAMILY = 2` plus `UIDeviceFamily [2]`,
which drops the obligation along with iPhone reach and needs a rebuild.

### 5. App Privacy questionnaire -- verify by hand

Data Not Collected. No analytics, no accounts, no tracking, no network calls
except the optional artwork host the user configures themselves, which is off
unless they set it. The public API cannot report whether this is published,
so confirm at
https://appstoreconnect.apple.com/apps/6800389617/appPrivacy before
submitting. It must agree with the privacy policy page or Apple rejects the
pair.

## Review notes

Held in `store/review-notes.txt`, because they are the highest rejection risk
here: a reviewer installing this gets an emulator that will not boot, having
no ROMs, and "app is non-functional" is a common rejection.

Consider bundling the MEGA65 project's free/open replacement ROMs so the app
boots to a usable BASIC without any user action -- worth checking their
licence and compatibility first, but it would remove this risk entirely and
make the first-run experience far better.
