# Release status

Updated 2026-08-23.

## Done

**The bundle id matches the App Store Connect record.** It is
`com.crownparkcomputing.c64-retro`, hyphenated. The project said
`com.crownparkcomputing.c64retro`, which is a registered App ID with no record
behind it -- so a build would have uploaded to nothing and looked like it
worked. Profile: "Retro-C64 AppStore v2".

**CI builds, signs and uploads.** The iOS job needed the five fixes the
sibling apps needed, each failing differently: macos-26 for the iOS 26 SDK;
the image's DEFAULT Xcode, because only that one has its platform components
downloaded; Swift Package Manager off, since gamepads_ios has not adopted it;
`xcodebuild archive` + export rather than `flutter build ipa`, which hunts for
a development certificate no runner has; and `codesign:` in the key partition
list, without which signing fails as errSecInternalComponent.

**The app runs on a simulator again.** The cores were plain `.framework`
bundles holding only the device slice, so the app opened to a dlopen dump --
"incompatible platform (have 'iOS', need 'iOS-simulator')". They are
xcframeworks now, carrying both slices at the same path.

**Screenshots: 9 iPhone + 9 iPad, uploaded**, captured by
`flutter_app/tool/screenshots.sh`. Re-run it after any UI change.

**Listing metadata** is complete: description, keywords, promotional text,
support URL, subtitle, categories, privacy policy URL, age rating, review
contact and review notes.

## Purpose strings, and why the check matters

Two deliveries were spent learning this. A bundle that links a protected API
needs a purpose string whether or not the app calls it, and Apple reports the
lack AFTER a delivery that reported success -- by email, with CI green:

- `NSPhotoLibraryUsageDescription` (DKImagePickerController, via file_picker).
  Missing, the build is DISCARDED in processing and never appears.
- `NSBluetoothAlwaysUsageDescription` (gamepads). Missing, the build is
  accepted with a warning that must be corrected in the next delivery.

The CI step asserts a framework/key pair for each, so adding a plugin that
drags in a new protected API is a build failure rather than mail three days
later. Verified in the shipped IPA, not merely in the source plist.

## Not done

**App Privacy** must be answered in the browser: every API path for it returns
404 to this key, including for apps that are already in review.

**Submission** is deliberately untouched: everything is staged in App Store
Connect and pressing Submit is a person's decision.

## Re-running the screenshots

    SHOT_SEED=<dir> SHOT_SEED_SUPPORT=<dir> tool/screenshots.sh <udid> <outdir>

`SHOT_SEED` contents land in Documents; `SHOT_SEED_SUPPORT` contents land in
Application Support, which is where the ROMs live. Without the ROMs the app
starts in free-ROM mode, which deliberately hides most of the rail -- so the
run captures a four-entry sidebar and cannot reach most screens.
`SHOT_SKIP_RUNNING=1` skips the launch-a-title shot, which boots the real core
and can outlast the driver's connection.
