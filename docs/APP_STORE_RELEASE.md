# Shipping an iOS app to TestFlight and the App Store

Written after eight uploads and five rejections getting build 8 of this app to
TestFlight, all five of which could have been avoided. Deliberately generic:
none of it is specific to this project, so it should serve the next app too.

A designed version of this document is published at
https://claude.ai/code/artifact/979bd83e-b02d-4e7c-ba5d-ed75b8584f16

`docs/IOS_BUILD.md` is the project-specific companion -- every trap this
codebase in particular has hit, with the symptom each presents as.

## Three things that reframe everything below

1. **A clean `--validate-app` means nothing.** Structural checks (Swift
   support, bundle layout) run server-side *after* the upload, not during
   validation. Builds that validate cleanly are rejected minutes later. Only an
   upload proves an upload works.
2. **Every upload spends a build number.** App Store Connect refuses a
   `CFBundleVersion` it has seen, and says so *after* the transfer. A build that
   fails processing still burns its number. Bump on every attempt.
3. **Apple's error text names the symptom, not the cause.** The most expensive
   rejection named Swift, in an app with no embedded Swift. Read the wording as
   a clue about which validator fired, not as a description of the fault.

## Triage

| Signature | Looks like | Actually is |
|---|---|---|
| `90426` SwiftSupport missing | a Swift packaging problem | a **bare `.dylib` in `Frameworks/`**. Only the Swift runtime historically sat there loose, so the scanner infers an embedded runtime and wants a SwiftSupport folder -- which Xcode never generates above a 12.2 deployment target, since ABI-stable Swift lives in the OS. Unfixable until the dylib becomes a `.framework`. Also fires when Mach-O metadata is damaged. |
| `90429` not at expected location | files are missing | same cause as 90426, and reported **even when the named files are at the named path**. Hand-adding SwiftSupport converts 90426 into this and gets no further. |
| `90683` missing purpose string | your app uses the camera | a *linked* framework is enough; use is irrelevant. `file_picker` alone pulls in camera, photos and location. Add all three usage strings saying the app does not use them. |
| `errSecInternalComponent` | a broken certificate | never the certificate. The keychain is **locked**; or another keychain **earlier in the search list holds the same cert** and codesign resolves to that locked copy; or the key's ACL omits codesign. A locked keychain still *lists* certificates as valid -- listing needs no private key. |
| `does not support provisioning profiles` | a broken Pod | `PROVISIONING_PROFILE_SPECIFIER` on the `xcodebuild` command line applies to **every** target, including Swift Packages and Pods. Set signing on the app target only. |
| `No profiles for '...' were found` | missing profile | automatic signing with no Apple ID in Xcode. It also seeks a *development* profile even when exporting for the App Store. Use manual signing. |
| `MAC verification failed` on `.p12` import | wrong password | OpenSSL 3 writes PKCS#12 Apple cannot read. Re-export with `-keypbe PBE-SHA1-3DES -certpbe PBE-SHA1-3DES -macalg sha1`. |
| `no suitable application record found` | wrong account | bundle ID does not match any App Store Connect record. A bundle ID can **never** change once a record exists. |

**Never rewrite Mach-O load commands.** `vtool -set-build-version ios <minos>
<sdk>` takes *two* versions, and `-replace` drops the `LC_BUILD_VERSION` tool
records identifying the toolchain. Passing the same value twice stamps every
framework as built against an ancient SDK with `ntools 0`; Apple then demands
the legacy embedded-Swift layout, and "rebuild using the current public (GM)
version of Xcode" turns out to be literal advice. A framework declaring a lower
`minos` than the app is normal. Check with
`otool -l <binary> | grep -A6 LC_BUILD_VERSION` against a pristine copy.

## One-time machine setup

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
- Place at `~/.appstoreconnect/private_keys/AuthKey_<KEYID>.p8`; keep the Key ID
  and Issuer ID

### Decide the bundle ID before any record exists

It can never change afterwards, and must match across iOS and Android or the
two stores diverge.

## The build loop

```sh
# 1. Bump the build number first. A spent number fails after the upload.
#    pubspec.yaml: version: 1.0.0+N

flutter build ios --release --no-codesign

# Signing belongs on the app target, never on the command line.
xcodebuild archive -workspace ios/Runner.xcworkspace -scheme Runner \
  -configuration Release -destination 'generic/platform=iOS' \
  -archivePath build/ios/archive/Runner.xcarchive

# method = app-store-connect (formerly app-store)
xcodebuild -exportArchive -archivePath build/ios/archive/Runner.xcarchive \
  -exportOptionsPlist ExportOptions.plist -exportPath build/ios/ipa

xcrun altool --upload-app -f build/ios/ipa/*.ipa -t ios \
  --apiKey <KEY_ID> --apiIssuer <ISSUER_ID>
```

### Inspect the bundle before uploading

```sh
cd $(mktemp -d) && unzip -q /path/to/app.ipa && A=Payload/*.app

ls $A/Frameworks/                       # .framework bundles ONLY, no bare .dylib
codesign --verify --deep --strict $A
codesign -dvv $A 2>&1 | grep Authority  # Apple Distribution -> WWDR -> Root
plutil -p $A/Info.plist | grep -E 'CFBundleVersion|Usage'
codesign -d --entitlements :- $A 2>/dev/null | grep beta-reports-active
```

Anything inside `Frameworks/` signed by an identity other than the app's own
fails validation, so check the frameworks and not just the app.

## Product page

Metadata blocks release independently of the binary, and none of it needs a
working build. Start early.

- **Privacy policy URL** -- required even when nothing is collected
- **Screenshots for every device family claimed** -- exact dimensions, no alpha.
  iPad captures cannot be padded into iPhone frames. If `UIDeviceFamily` claims
  iPhone you owe iPhone shots; narrowing `TARGETED_DEVICE_FAMILY` to iPad
  removes the obligation
- **App Privacy questionnaire** -- separate from the policy, separately blocking
- **Support URL**, category, age rating, copyright
- `ITSAppUsesNonExemptEncryption` in `Info.plist` so testers aren't gated on a
  manual answer every build
- At least one screenshot of the app *working* -- menus don't show what it does

### Review notes are where apps needing setup get rejected

If the app cannot demonstrate itself on a clean install -- it needs user-supplied
files, a login, hardware, a server -- the reviewer sees a broken app and rejects
it as non-functional. State in the notes what is missing, why, and the exact
steps to a working state, with a demo account or sample data where legal.

Better: make first launch degrade into guidance rather than a blank screen. That
fixes the reviewer's experience and every user's at once.

## Habits that would have saved the time

- **Check which artifact you actually uploaded.** Two rejections went on a stale
  IPA from an earlier session, still listed in Transporter. Delete old artifacts
  every build; check the version and build number named in the rejection.
- **Suspect your own recent changes before Apple's tooling.** A build phase
  rewriting Mach-O headers produced errors about Swift.
- **Diff against a pristine artifact.** Metadata damage is invisible until
  compared with an untouched copy.
- **Prefer the structural fix.** Hand-assembling the folder Apple asked for
  produced a new error; making the bundle conventional resolved it.
- **Keep machine-specific settings out of the repo.** Team IDs, profile names
  and signing style break CI and the next person's machine.
