# Windows to store, start to finish

The route from a Flutter checkout on a Windows machine to a signed AAB on Play
and a signed IPA on TestFlight, without owning a Mac.

Two companion documents: `docs/APP_STORE_RELEASE.md` is the general iOS release
reference and its triage table for rejections, and `docs/IOS_BUILD.md` is the
project-specific trap log.

## The one hard constraint

**iOS cannot be built or signed on Windows. Ever.** Flutter's iOS AOT compiler,
`xcodebuild`, `codesign` and `actool` are macOS-only, and no amount of tooling
works around it. Everything else -- Dart, tests, Android, Linux -- runs anywhere.

So iOS builds happen on a Mac you rent by the minute. This repo already has one
wired up: the `ios` job in `.github/workflows/build.yml` runs on a `macos-14`
GitHub runner and produces a signed IPA. That, not a physical Mac, is the
iOS build machine.

Xcode Cloud does the same job and is the alternative if you would rather stay
inside Apple's tooling, but GitHub Actions is already configured here, builds
all three platforms in one run, and needs no Xcode to set up.

## Stage 1 -- develop and test on Windows

Everything except iOS.

```sh
flutter pub get
flutter analyze
flutter test                       # the whole suite, no device needed
flutter run -d windows             # or -d chrome
flutter run -d <android-device>    # real Android hardware over USB
flutter build apk --debug          # sideload to an Android device
```

Android is the local proving ground: same Dart, same plugins, same native
core loading path in structure if not in detail. What Android cannot tell you
is anything iOS-specific -- sandbox rules, `path_provider` behaviour, bundle
layout, framework loading. Those only surface on a real iPhone or iPad.

Do not chase an iOS simulator on Windows. It does not exist.

## Stage 2 -- push, and let CI build everything

`.github/workflows/build.yml` triggers on push to `main`, on tags matching
`v*`, on pull requests, and manually via **Actions -> Build -> Run workflow**.

| Job | Runner | Produces |
|---|---|---|
| `analyze` | ubuntu | analyzer + tests, gate for the rest |
| `android` | ubuntu | `.aab` for Play, plus an `.apk` |
| `ios` | **macos-14** | signed `.ipa` |
| `linux` | ubuntu | Linux bundle |
| `release` | ubuntu | collects artifacts onto a GitHub release |

Without signing secrets the jobs still run -- Android falls back to the debug
key and iOS builds unsigned -- so forks and pull requests are not blocked. Those
outputs are testable but **not uploadable to either store**.

## Stage 3 -- set the signing secrets, once per app

Seven repository secrets, under **Settings -> Secrets and variables -> Actions**.
This is the only fiddly part, and it is once per app, not once per release.

### Android (four secrets)

Generate an upload keystore. Keep it forever: Play identifies your app by this
key, and losing it means you cannot ship an update to the same listing.

```sh
keytool -genkey -v -keystore upload-keystore.jks \
  -keyalg RSA -keysize 2048 -validity 10000 -alias upload
```

Then base64 it -- secrets are text, a keystore is binary.

```sh
base64 -w0 upload-keystore.jks          # Linux/macOS
certutil -encode upload-keystore.jks out.txt   # Windows, then strip the header lines
```

| Secret | Value |
|---|---|
| `ANDROID_KEYSTORE_BASE64` | the base64 blob above |
| `ANDROID_KEYSTORE_PASSWORD` | keystore password |
| `ANDROID_KEY_ALIAS` | `upload`, or whatever `-alias` you chose |
| `ANDROID_KEY_PASSWORD` | key password (often the same) |

CI writes these back into `android/key.properties` and a `.jks` at build time.
`key.properties`, `*.jks` and `*.keystore` are gitignored, and must stay that
way -- the keystore in a public repo is the whole app's identity.

### iOS (three secrets)

These need Apple Developer Program membership and a one-off visit to
developer.apple.com. Both files are produced there, not on your machine.

| Secret | Where it comes from |
|---|---|
| `APPSTORE_CERT_BASE64` | an **Apple Distribution** certificate exported as `.p12`, base64'd |
| `APPSTORE_CERT_PASSWORD` | the password set when exporting the `.p12` |
| `APPSTORE_PROFILE_BASE64` | an **App Store** provisioning profile for the bundle ID, base64'd |

Making the `.p12` without a Mac is the awkward step, since Keychain Access is
macOS-only. On Windows, with OpenSSL:

```sh
openssl genrsa -out dist.key 2048
openssl req -new -key dist.key -out dist.csr \
  -subj "/emailAddress=you@example.com/CN=Your Name/C=GB"
# Upload dist.csr at developer.apple.com -> Certificates -> Apple Distribution,
# download distribution.cer, then:
openssl x509 -inform DER -in distribution.cer -out dist.pem
openssl pkcs12 -export -inkey dist.key -in dist.pem -out dist.p12 \
  -keypbe PBE-SHA1-3DES -certpbe PBE-SHA1-3DES -macalg sha1
```

The three legacy algorithm flags are not optional: OpenSSL 3's defaults produce
a `.p12` Apple's tooling cannot read, failing with "MAC verification failed"
that reads exactly like a wrong password.

**Keep `dist.key`.** It is the private half of the certificate and cannot be
recovered from Apple. Without it the certificate is decoration.

## Stage 4 -- cut a release

```sh
git tag v1.0.0 && git push --tags
```

The tag triggers the full matrix and attaches the artifacts to a GitHub release.
Download the `.aab` for Play and the `.ipa` for App Store Connect.

Before every tag, bump `version:` in `pubspec.yaml`. Both stores refuse a build
number they have already seen, and both tell you after the upload rather than
before. `1.0.0+7` is version name `1.0.0`, build `7`; the build number is what
must increase.

## Stage 5 -- upload

**Android.** Play Console -> your app -> Production/Testing -> create release ->
upload the `.aab`. First upload of a new app also wants the store listing,
content rating questionnaire and data safety form.

**iOS.** From any machine with the App Store Connect API key:

```sh
xcrun altool --upload-app -f app.ipa -t ios \
  --apiKey <KEY_ID> --apiIssuer <ISSUER_ID>
```

`altool` ships with Xcode, so on Windows use Transporter equivalents or add an
upload step to the `ios` CI job, which already runs on macOS and can upload
directly with the same key.

Then the product page. See `docs/APP_STORE_RELEASE.md` -- particularly the
review-notes section, which is where apps that need setup before they do
anything get rejected as non-functional.

## Setting up a brand new app

In order, because two of these are irreversible:

1. **Choose the bundle ID / application ID.** Identical on both platforms.
   Neither store lets you change it once a record exists.
2. Create the App Store Connect record and the Play Console listing.
3. Generate the Android keystore and the iOS certificate and profile; set the
   seven secrets.
4. Copy `.github/workflows/build.yml` across and adjust paths and the pinned
   Flutter version.
5. Push, confirm CI is green, then tag.

## If you would rather use Xcode Cloud

Same outcome, Apple's infrastructure, and it handles signing server-side so
none of the iOS secrets above are needed.

- Onboard at `https://appstoreconnect.apple.com/apps/<APP_ID>/ci`, in the
  browser -- Xcode's `Product -> Xcode Cloud` menu only appears with a project
  open, which is no use from Windows.
- Grant it access to the repository under **Settings -> Repositories**.
- Point the workflow's start condition at the branch you actually push. A
  workflow watching a stale branch simply never runs, silently.
- Delete the default **Test** action unless the shared scheme's tests are
  reliable; a test failure blocks the archive.
- Xcode Cloud archives and delivers straight to App Store Connect, with no
  post-export hook. Anything the bundle needs must come out of the build itself.
