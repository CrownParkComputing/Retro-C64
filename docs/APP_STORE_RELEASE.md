# Shipping an iOS app to TestFlight and the App Store

A complete runbook, written across two apps -- C64-Retro and Amiga-Retro --
and roughly a dozen rejections, nearly all avoidable. Deliberately generic:
nothing here is specific to either project, so it should serve the next app.

A designed version of this document is published at
https://claude.ai/code/artifact/979bd83e-b02d-4e7c-ba5d-ed75b8584f16 -- same
content, easier to scan when something is on fire. This file is the source of
truth; regenerate the page from it rather than editing the page.

`docs/IOS_BUILD.md` is the project-specific companion -- every trap this
codebase in particular has hit, with the symptom each presents as.

The commands assume `tools/appstore/asc.rb`, which wraps the App Store Connect
API for the parts the release needs. Run it with no arguments for usage.

## Four things that reframe everything below

1. **A clean `--validate-app` means nothing.** Structural checks (Swift
   support, bundle layout) run server-side *after* the upload, not during
   validation. Builds that validate cleanly are rejected minutes later. Only an
   upload proves an upload works.
2. **Every upload spends a build number.** App Store Connect refuses a
   `CFBundleVersion` it has seen, and says so *after* the transfer. A build that
   fails processing still burns its number. Bump on every attempt, and read the
   *server's* highest number, not your `pubspec.yaml` -- if anyone else uploads,
   yours has silently fallen behind.
3. **Apple's error text names the symptom, not the cause.** The most expensive
   rejection named Swift, in an app with no embedded Swift. Read the wording as
   a clue about which validator fired, not as a description of the fault.
4. **The account-level gates are invisible until you submit.** Pricing and the
   App Privacy answers are not shown as warnings anywhere on the version page.
   They surface once, as a generic "not in valid state", on the day you try to
   ship. Do them on day one -- see Phase 2.

## The phases, in order

Phases 0-2 are once per app and can all be done before there is a working
build. Phases 3-7 are the release loop.

| | | Blocking? |
|---|---|---|
| 0 | Bundle ID, then the App Store Connect record | everything |
| 1 | Signing identity and API key on the machine | the build |
| 2 | **Pricing, App Privacy, age rating, categories** | **the submission, silently** |
| 3 | Build, archive, export, upload | |
| 4 | Inspect the bundle before uploading | |
| 5 | Screenshots | the submission |
| 6 | Description, keywords, review notes | the submission |
| 7 | Attach the build and submit | |

---

## Phase 0 -- Decide the bundle ID before any record exists

It can never change afterwards, and must match across iOS and Android or the
two stores diverge.

## Phase 1 -- One-time machine setup

### Signing without an Xcode account

Manual signing needs no Apple ID and is more predictable than automatic.

```sh
security create-keychain -p "$PW" build.keychain
security set-keychain-settings build.keychain          # disable auto-lock
security unlock-keychain -p "$PW" build.keychain
security import dist.p12 -k build.keychain -P "$P12PW" -T /usr/bin/codesign -A

# Without this, codesign is denied the key non-interactively.
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$PW" build.keychain

# codesign uses the FIRST keychain holding the identity. No other keychain
# carrying the same certificate may precede this one.
security list-keychains -d user -s login.keychain-db build.keychain
```

Record the keychain password, the `.p12` password and where the private key
lives. A certificate whose keychain password is lost is unusable -- and still
appears in `security find-identity`, looking healthy.

### An App Store Connect API key

Removes Transporter from the loop and allows CLI upload.

- App Store Connect -> Users and Access -> Integrations -> **Team Keys**
- Role **App Manager**; download the `.p8` (one chance only)
- Place at `~/.appstoreconnect/private_keys/AuthKey_<KEYID>.p8`

Then `~/.config/appstore.env`, which `asc.rb` reads (mode 600; the `.p8` is the
secret, these are just identifiers):

```sh
ASC_KEY_ID=XXXXXXXXXX
ASC_ISSUER_ID=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
ASC_BUNDLE_ID=com.example.app
```

Override per app without editing the file:

```sh
ASC_BUNDLE_ID=com.example.other tools/appstore/asc.rb status
```

## Phase 2 -- The account-level gates

**This phase is the one that costs a day.** None of it concerns the binary,
none of it appears as a warning, and all of it blocks submission.

| Gate | Where | Notes |
|---|---|---|
| **Pricing** | `asc.rb price GBR 2.99` | A new app has *no* price schedule. Free apps need one too -- pass `0`. Sets the base territory at the same time. |
| **App Privacy** | web UI only | Not the privacy *policy* URL -- a separate questionnaire, separately blocking. **Not reachable from the API**: every `appDataUsages` endpoint 404s for a Team Key. |
| Age rating | web UI | The 2025 questionnaire has more questions than the old one. |
| Categories | web UI | Primary is required; subcategories are not. |
| Availability | web UI | Territories. |
| Privacy policy URL | web UI | Required even when nothing is collected. |
| Support URL | per version | Required. Marketing URL is not. |

App Privacy for an app with no network code is *"No, we do not collect data
from this app"* -- but verify rather than assume:

```sh
grep -rn "package:http\|HttpClient\|url_launcher\|Uri.https" lib/
grep -n "http\|dio\|url_launcher" pubspec.yaml
```

Once published, Apple's answer propagates asynchronously. Adding the version
to a submission immediately afterwards fails and then succeeds about 25
seconds later; `asc.rb submit` retries three times for exactly this reason.

## Phase 3 -- The build loop

```sh
# Read the server's highest build number. Do not trust pubspec.yaml: builds
# uploaded from another machine are invisible to it.
tools/appstore/asc.rb builds

# Bump pubspec.yaml to next: version: 1.0.0+N

flutter build ios --release --no-codesign

# Signing belongs on the app target, never on the command line.
xcodebuild archive -workspace ios/Runner.xcworkspace -scheme Runner \
  -configuration Release -destination 'generic/platform=iOS' \
  -archivePath build/ios/archive/Runner.xcarchive

# method = app-store-connect (formerly app-store)
xcodebuild -exportArchive -archivePath build/ios/archive/Runner.xcarchive \
  -exportOptionsPlist ExportOptions.plist -exportPath build/ios/ipa

xcrun altool --upload-app -f build/ios/ipa/*.ipa -t ios \
  --apiKey "$ASC_KEY_ID" --apiIssuer "$ASC_ISSUER_ID"
```

`ExportOptions.plist` is machine-specific and belongs outside the repo:

```xml
<key>method</key><string>app-store-connect</string>
<key>teamID</key><string>XXXXXXXXXX</string>
<key>signingStyle</key><string>manual</string>
<key>signingCertificate</key><string>Apple Distribution: Name (TEAMID)</string>
<key>provisioningProfiles</key>
<dict><key>com.example.app</key><string>Profile Name</string></dict>
```

Manual signing on the app target is also machine-specific: set
`CODE_SIGN_STYLE = Manual`, `CODE_SIGN_IDENTITY` and
`PROVISIONING_PROFILE_SPECIFIER` on the Runner target's **Release** config
only, and revert before committing. `main` should keep automatic signing so
Xcode Cloud still works.

```sh
cp ios/Runner.xcodeproj/project.pbxproj /tmp/pbxproj.orig   # before
cp /tmp/pbxproj.orig ios/Runner.xcodeproj/project.pbxproj   # after
```

## Phase 4 -- Inspect the bundle before uploading

```sh
cd $(mktemp -d) && unzip -q /path/to/app.ipa && A=Payload/*.app

ls $A/Frameworks/                       # .framework bundles ONLY, no bare .dylib
codesign --verify --deep --strict $A
codesign -dvv $A 2>&1 | grep Authority  # Apple Distribution -> WWDR -> Root
plutil -p $A/Info.plist | grep -E 'CFBundleVersion|MinimumOS|Usage|Encryption'
codesign -d --entitlements :- $A 2>/dev/null | grep beta-reports-active
```

Anything inside `Frameworks/` signed by an identity other than the app's own
fails validation, so check the frameworks and not just the app.

## Phase 5 -- Screenshots

Display types are Apple's names, not the marketing ones:

| Devices | Display type | Size |
|---|---|---|
| iPhone 6.7" **and 6.9"** | `APP_IPHONE_67` | 1290x2796 or 1320x2868 |
| iPad 13" | `APP_IPAD_PRO_3GEN_129` | 2064x2752 |

There is no `APP_IPHONE_69` -- Apple folds 6.9" into the 6.7" set, which takes
the larger captures without complaint.

You owe screenshots for every family the **attached build** claims in
`TARGETED_DEVICE_FAMILY`. Narrowing to iPad (`= 2`) removes the iPhone
obligation entirely. iPad captures padded into an iPhone frame are rejected,
and letterboxed shots look like a broken app even when accepted.

**Every simulator capture carries an alpha channel and Apple rejects it** --
not at upload, but silently during processing. `sips` cannot remove it (a BMP
round-trip re-adds it) and PIL may not be installable, so:

```sh
swift tools/flatten-screenshot.swift raw.png out.png
tools/appstore/asc.rb shots APP_IPAD_PRO_3GEN_129 store/screenshots/*.png
```

`asc.rb shots` refuses files that still have alpha, and replaces the whole set
rather than appending.

### Photographing screens that sit behind navigation

`simctl` has no tap API, so there is no way to drive the UI to a screen. Two
techniques, both cheap:

- **Default the app to the screen.** Patch whichever field holds the selected
  tab or section, rebuild, and capture the first frame. Revert afterwards.
- **Seed the data through the app's own code.** An empty list photographs
  badly. Inject a call in `main()` that writes a few records via the real store
  class, so the screenshots show exactly what the app would have produced --
  rather than hand-written fixtures that can drift from the real format.

Two traps found doing this:

- A preference written straight into the container plist **does not stick**.
  The simulator's `cfprefsd` holds a cached copy and writes it back over your
  file. Patch the source instead.
- Beware app logic that deliberately re-runs onboarding on a new build (an
  `isNewBuild()` check). Setting the "setup complete" flag will not defeat it.

Also: give the capture a clean status bar, and reboot the simulator if a
previous app left a `◀ Back to <app>` breadcrumb in it.

```sh
xcrun simctl status_bar "$UDID" override --time "09:41" \
  --batteryState charged --batteryLevel 100 --wifiBars 3
```

## Phase 6 -- Product page

Metadata blocks release independently of the binary, and none of it needs a
working build. Start early.

- Description, keywords, support URL, copyright
- At least one screenshot of the app *working* -- menus don't show what it does
- `ITSAppUsesNonExemptEncryption` in `Info.plist` so testers aren't gated on a
  manual answer every build

**Re-read the copy against the build you are shipping.** One app's description
still said *"the emulator will not boot without a Kickstart ROM -- make sure
you can supply one before installing"* two builds after a free fallback ROM
was bundled and it booted out of the box. Stale copy that undersells the app is
worse than no copy, and nothing in the pipeline checks it.

### Review notes are where apps needing setup get rejected

If the app cannot demonstrate itself on a clean install -- it needs
user-supplied files, a login, hardware, a server -- the reviewer sees a broken
app and rejects it as non-functional. State in the notes what is missing, why,
and the exact steps to a working state, with a demo account or sample data
where legal.

Better: make first launch degrade into guidance rather than a blank screen.
Better still, where licensing allows: ship a free fallback so the app is
useful with nothing supplied. That converts a Guideline 4.7 argument into a
non-issue and improves every user's first run at the same time.

## Phase 7 -- Attach and submit

```sh
tools/appstore/asc.rb status          # what the version has and lacks
tools/appstore/asc.rb attach 31       # build must be VALID
tools/appstore/asc.rb blockers        # why it cannot be submitted, if it cannot
tools/appstore/asc.rb submit
```

### Reading a refused submission

A refusal returns a generic message that says nothing:

    appStoreVersions with id '...' is not in valid state.
    This resource cannot be reviewed, please check associated errors to see why.

The actual reasons are nested in `errors[0].meta.associatedErrors`, which
**spaceship discards**. This is what `blockers` exists to print:

```
/v1/appDataUsages/  STATE_ERROR.APP_DATA_USAGES_REQUIRED
    Answers to what data your app collects and how it's used are needed.
/v2/appPrices/      STATE_ERROR.APP_PRICING_REQUIRED
    App is missing required pricing.
```

Without that, both look identical to a metadata problem on the version itself,
and every field on the version page reads as complete.

### A failed submit is not always a failed submission

Submission is four calls -- attach the build, create the submission, add the
version as an item, submit it. A wrapper's *final validation* can fail against
a submission that is perfectly correct, reporting

    review submission <id> does not contain target version <id>

**Before retrying any submission step, read the state.** Re-running the wrapper
creates a *second* submission. `asc.rb blockers` is safe to re-run: it reuses
an existing unsubmitted submission rather than creating another.

---

## Triage

| Signature | Looks like | Actually is |
|---|---|---|
| `90426` SwiftSupport missing | a Swift packaging problem | a **bare `.dylib` in `Frameworks/`**. Only the Swift runtime historically sat there loose, so the scanner infers an embedded runtime and wants a SwiftSupport folder -- which Xcode never generates above a 12.2 deployment target, since ABI-stable Swift lives in the OS. Unfixable until the dylib becomes a `.framework`. Also fires when Mach-O metadata is damaged. |
| `90429` not at expected location | files are missing | same cause as 90426, and reported **even when the named files are at the named path**. Hand-adding SwiftSupport converts 90426 into this and gets no further. |
| `90683` missing purpose string | your app uses the camera | a *linked* framework is enough; use is irrelevant. `file_picker` alone pulls in camera, photos and location. Add all three usage strings saying the app does not use them. |
| `STATE_ERROR.ENTITY_STATE_INVALID` on submit | the version is incomplete | almost always an **account-level** gate -- pricing or App Privacy. Run `asc.rb blockers`. |
| `errSecInternalComponent` | a broken certificate | never the certificate. The keychain is **locked**; or another keychain **earlier in the search list holds the same cert** and codesign resolves to that locked copy; or the key's ACL omits codesign. A locked keychain still *lists* certificates as valid -- listing needs no private key. |
| `does not support provisioning profiles` | a broken Pod | `PROVISIONING_PROFILE_SPECIFIER` on the `xcodebuild` command line applies to **every** target, including Swift Packages and Pods. Set signing on the app target only. |
| `No profiles for '...' were found` | missing profile | automatic signing with no Apple ID in Xcode. It also seeks a *development* profile even when exporting for the App Store. Use manual signing. |
| `MAC verification failed` on `.p12` import | wrong password | OpenSSL 3 writes PKCS#12 Apple cannot read. Re-export with `-keypbe PBE-SHA1-3DES -certpbe PBE-SHA1-3DES -macalg sha1`. |
| `no suitable application record found` | wrong account | bundle ID does not match any App Store Connect record. A bundle ID can **never** change once a record exists. |
| `The specified pre-release build could not be added` | a version-string mismatch | *also* fires when the build's `buildAudienceType` is `INTERNAL_ONLY`. See below. Check the audience before re-reading version strings. |
| duplicate build number | you forgot to bump | someone else uploaded. `asc.rb builds` reads the server; `pubspec.yaml` does not. |

**Never rewrite Mach-O load commands.** `vtool -set-build-version ios <minos>
<sdk>` takes *two* versions, and `-replace` drops the `LC_BUILD_VERSION` tool
records identifying the toolchain. Passing the same value twice stamps every
framework as built against an ancient SDK with `ntools 0`; Apple then demands
the legacy embedded-Swift layout, and "rebuild using the current public (GM)
version of Xcode" turns out to be literal advice. A framework declaring a lower
`minos` than the app is normal. Check with
`otool -l <binary> | grep -A6 LC_BUILD_VERSION` against a pristine copy.

## Internal-only builds cannot be submitted

A build carrying `buildAudienceType: INTERNAL_ONLY` installs and tests
perfectly through TestFlight and can **never** be attached to an App Store
version. The attach fails with

    The specified pre-release build could not be added

which is the same sentence Apple returns for a `CFBundleShortVersionString`
that does not match the version record -- so the obvious reading sends you
checking version strings that are already correct.

The audience is fixed when the build is produced and cannot be changed
afterwards, so a run of internal-only builds is a run of builds none of which
can ship. For Xcode Cloud the producer is the workflow's archive action:
**Manage Workflows -> <workflow> -> Actions -> Archive -> Deployment
Preparation**, which must be *TestFlight and App Store*, not *TestFlight
(Internal Testing Only)*. Widening it costs nothing.

Check the audience on the first build of any new app, not on the day you
submit.

## Xcode Cloud triggers twice if you let it

A workflow with a `branchStartCondition` builds on every push. Triggering a run
manually after pushing produces a **second** build of the same commit, and
Xcode Cloud numbers each run, so build numbers arrive in pairs (9+10, 11+12)
with no indication why. Pick one trigger and stop using the other. The build
number is Xcode Cloud's run counter, not `pubspec.yaml`.

## A build can upload, validate and ship while being completely broken

Apple checks the bundle, not whether it draws. A binary that launches to a
black screen passes validation, passes processing, reaches TestFlight, and only
fails when a human opens it.

The instance that cost a day: on iOS 13+ the window and root view controller
belong to the scene, and something has to create them -- a storyboard named by
`UIMainStoryboardFile`/`UISceneStoryboardFile`, or code in the scene delegate.
A Flutter app whose scene delegate only *adopts* an existing window (because
some other build path creates one) and whose storyboard is wired to nothing
will never construct a `FlutterViewController`. No view controller means no
engine, which means **Dart never starts**: no crash, no log line, `flutter run`
hanging at "Waiting for VM Service port".

Two greps say whether an app has it:

```sh
grep -c "UIWindow(windowScene" ios/Runner/SceneDelegate.swift
grep -c "UIMainStoryboardFile\|UISceneStoryboardFile" ios/Runner/Info.plist
```

Both zero and every Xcode build of that app is black. A `.storyboard` file in
the project proves nothing if neither key names it.

The general lesson is cheaper than the specific one: **install the exact
artefact you are about to ship on real hardware and open it.** Every automated
signal in this pipeline -- build success, `altool` validation, App Store
processing, TestFlight availability -- can be green for a build that shows
users nothing at all.

## Release builds hide their own errors

A release build shows no red error screen. A widget that throws simply does not
paint, so the report that comes back is "white screen" and the exception never
leaves the device. One app lost most of a day to a sidebar whose `clamp()`
received a lower bound above its upper one -- which blanked every iPhone in
portrait and looked in turn like a signing fault, a core fault and a simulator
fault.

Install an error log on the first line of `main()`, writing to `Documents` so
the Files app can reach it without a cable:

```dart
FlutterError.onError = (details) { /* append to a file */ };
PlatformDispatcher.instance.onError = (error, stack) { /* and here */ };
```

It named the file and line on the first run. Add it to a new app before the
first tester build, not after the first white screen.

## Habits that would have saved the time

- **Check which artifact you actually uploaded.** Two rejections went on a stale
  IPA from an earlier session, still listed in Transporter. Delete old artifacts
  every build; check the version and build number named in the rejection.
- **Read the server's build numbers, not the repo's.**
- **Suspect your own recent changes before Apple's tooling.** A build phase
  rewriting Mach-O headers produced errors about Swift.
- **Diff against a pristine artifact.** Metadata damage is invisible until
  compared with an untouched copy.
- **Prefer the structural fix.** Hand-assembling the folder Apple asked for
  produced a new error; making the bundle conventional resolved it.
- **Keep machine-specific settings out of the repo.** Team IDs, profile names
  and signing style break CI and the next person's machine.
- **Re-read the store copy against the build.** Nothing checks it and it goes
  stale silently.
