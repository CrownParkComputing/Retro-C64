# Creating a new store app — the parts you cannot do via API

Written for the next emulator in the Retro-* family. Both Apple and Google
expose most of the post-creation lifecycle over REST, but the act of
**creating** the initial app record is not in either API: App Store Connect
rejects `POST /v1/apps` for the Team Key auth (`403 Forbidden` even with
App Manager role), and Play Console's equivalent requires interactive
acceptance of the Developer Distribution Agreement.

There is no scriptable shortcut. This is the walkthrough.

A good companion to this is
[`APP_STORE_RELEASE.md`](APP_STORE_RELEASE.md), which covers everything
*after* the app record exists. The split is: this doc is the bit you do
once, on the website; that one is the bit you do every release, in CI.

`LICENCE_COMPLIANCE.md` is also relevant before the first upload: the
account-level gating (pricing, App Privacy, age rating, categories,
territories) only shows up as "not in valid state" on the day you submit.
Do it on day one.

## The five things you need before you touch either console

1. **Bundle ID** — see [Bundle IDs](#bundle-ids). Never changes after
   either record exists. Must match across stores if you ship to both.
2. **App display name** — what the user sees on the home screen. Apple
   truncates at ~16 characters in iOS 17+ unless you ship a long-name
   workaround; pad accordingly.
3. **One-sentence pitch** — for the App Store subtitle and Play Console
   short description. Two-line limit on both.
4. **A privacy policy URL** — required even when nothing is collected.
   GitHub Pages on the public repo works.
5. **A support URL** — same. Repo README or a `support@` mailto.

## Bundle IDs

The Retro-* family uses `com.crownpark.<machine>`. The chosen name is the
   bundle id; choose it once.

| App | Bundle ID | Status |
|---|---|---|
| Retro-C64 | `com.retroc64` (kept old id for store install continuity) | shipped |
| Retro-Saturn | `com.crownpark.ymir_multiplatform` (pre-rename) | shipped |
| Retro-Amiga | `uk.co.crownpark.<name>` (Amiga kept a different namespace) | shipped |
| Retro-Dosbox | `com.crownpark.<name>` | shipped |
| Retro-Spectrum | `com.crownpark.retro_spectrum` | shipped |
| Retro-Hypseus (Dragon's Lair / Singe) | `com.crownpark.retrohyposeus` | in flight |

Pick `com.crownpark.<machine>` for new apps in this family unless there is
a specific reason to deviate. The leading `crownpark` prefix is the
existing Apple Developer Team prefix; matching it means you do not need a
new Apple Developer account.

Android `applicationId` and the iOS `PRODUCT_BUNDLE_IDENTIFIER` both have
to match the bundle id. Drift between the two is the single most common
   reason a build installs but the wrong record is created.

---

## App Store Connect — first record

Web only. Roughly fifteen minutes if you have everything in section 1.

### Step 1 — create the record

1. Sign in to https://appstoreconnect.apple.com/ as the Team Agent or
   an Admin / App Manager.
2. **My Apps** → **+** → **New App**.
3. Fill in:
   - **Platforms**: iOS (or iOS + iPadOS). iOS-only is the cleanest for
     a phone-first emulator; iPad captures are still required as
     screenshots when iPad is in.
   - **Primary Language**: pick the locale the description will be in.
     Add other localisations later.
   - **Bundle ID**: pick from the dropdown of bundle ids registered on
     this team. **The id has to exist in App Store Connect OR Apple
     Developer Portal before this screen offers it.** If it does not,
     go to https://developer.apple.com/account/resources/identifiers,
     **+**, **App IDs**, register `com.crownpark.<machine>` with the
     capabilities you'll use — for an emulator: no push, no sign-in with
     Apple, no in-app purchase, no Game Center, no associated domains.
     App ID strings are case-sensitive.
   - **SKU**: any unique string. Convention here is
     `crownpark-<machine>-ios`.
   - **User Access**: leave at Full Access for now.

### Step 2 — fill the account-level gates

**Do this on day one.** None of it concerns the binary and none of it
appears as a warning. All of it blocks submission silently. The full list
is in `APP_STORE_RELEASE.md` §"Phase 2"; the steps are:

- **Pricing and Availability**: even free apps need a price schedule.
  Pick the cheapest tier or pass `0`.
- **App Privacy**: separate from the privacy policy URL. For an emulator
  with no analytics: *"No, we do not collect data from this app"*. Walk
  through every category; the wizard lets you finish with all "No" and
  that is correct for most emulators.
- **Age Rating**: questionnaire. Pick the lowest age (4+) for an emulator
  with no objectionable content.
- **Categories**: primary is required. **Games > Entertainment** is the
  usual fit. Subcategories are not.
- **Availability**: territories. Default is all; narrow if there is a
  reason.
- **Privacy Policy URL**: required even when nothing is collected.
- **Support URL**: required.

### Step 3 — create the bundle id in the Developer Portal if it does not exist

Apple Developer Portal → Certificates, Identifiers & Profiles →
**Identifiers** → **+** → **App IDs** → **App**:

- **Description**: the user-visible app name (max 64 chars).
- **Bundle ID**: **Explicit** for apps you ship yourself. Format
  `com.crownpark.<machine>`.
- **Capabilities**: scroll through and turn off anything the app does
  not use. For an emulator: In-App Purchase, push notifications, Game
  Center, Sign In with Apple, all off. **App Groups**, **Associated
  Domains**, **iCloud** also off.
- **Register**. The App ID is now available in App Store Connect.

### Step 4 — register a signing identity

If you have not already: Certificates → **+** → **Apple Distribution**.
The CSR step requires Keychain Access on a Mac. The certificate is
returned in `.cer` form; download and double-click to install.

Provisioning profiles come later, after the first build is uploaded and
the bundle id is matched to a record.

### Step 5 — TestFlight setup

When the first build uploads, App Store Connect offers to attach it to a
TestFlight build. Approve the first one and **set the audience to "TestFlight
and App Store"**, not "Internal Testing Only". The latter cannot be
attached to an App Store version and the symptom is the unhelpful
"pre-release build could not be added" error — see
`APP_STORE_RELEASE.md` §"Internal-only builds cannot be submitted".

Create the **Internal Testing** group (`My Apps → <app> → TestFlight →
Internal Testing → +`) with the testers' Apple IDs. Internal Testing
builds do not need a Beta App Review.

The first External Testing group requires a Beta App Review, which is a
full submission. Skip it for the first build; add it when reviewers are
lined up.

---

## Google Play Console — first app

Web only. Roughly twenty minutes for the initial app; another ten for
the signing key handover.

### Step 1 — create the app

1. Sign in to https://play.google.com/console as the account owner.
2. **Create app** → fill in:
   - **App name**: user-visible, 50 chars max. Same string as the App
     Store display name where possible.
   - **Default language**: the locale for the store listing.
   - **App or game**: Game. **Free or paid**: Free (Play Store charges a
     one-time fee per paid app; most emulators are free).
   - **Declarations**: tick the two boxes (Developer Programme policies,
     US export laws). Both required.

The app is now in **Draft** state. Nothing about it is visible to the
public yet.

### Step 2 — fill the store listing

In the left rail: **Store presence → Main store listing**.

| Field | Notes |
|---|---|
| App name | already set |
| Short description | 80 chars, shown under the icon |
| Full description | 4000 chars, the long pitch |
| App icon | 512x512 PNG, no alpha (Apple rejects alpha but Play is stricter about it) |
| Feature graphic | 1024x500 PNG/JPG, required |
| Screenshots | phone required (min 2, max 8); 7" tablet and 10" tablet optional but recommended |
| Privacy policy URL | required |
| App category | **Game > Arcade** or **Game > Simulation** depending on the system |
| Contact details | required (email at minimum) |

Everything above is editable any time. Fill it now, not on launch day.

### Step 3 — set up Play App Signing

This is the one piece that is irreversible and you cannot do without
help from a Mac.

1. **Setup → App signing**. Play Console generates three keys:
   - **Upload key**: the one you sign APKs / AABs with locally.
   - **App signing key**: the one Google keeps; used to sign the actual
     delivered artefact. You do not see the private key.
   - **Key upgrade key**: a recovery path Google can use if your upload
     key is lost.
2. **Generate upload key on a Mac** (this is the bit that does not work
   on Linux):

   ```sh
   keytool -genkey -v \
     -keystore ~/keystores/<machine>-upload.jks \
     -keyalg RSA -keysize 2048 -validity 9125 \
     -alias upload \
     -storepass <pw> -keypass <pw> \
     -dname "CN=<machine>, OU=CrownPark, O=CrownPark, L=London, S=GB, C=GB"
   ```

   Back the `.jks` up somewhere off the laptop. Without it, a future
   upload will fail and there is no recovery path that does not require
   Google's escalation.

3. Export the keystore as base64 (this is what goes into the CI secret):

   ```sh
   base64 -w 0 <machine>-upload.jks > <machine>-upload.jks.b64
   ```

4. In **Setup → App signing → Upload key certificate**, upload the
   `.jks`. Play Console stores a fingerprint; from then on every
   upload must be signed with that exact `.jks`.

### Step 4 — set up the service account for CI

1. Google Cloud Console → IAM & Admin → **Service Accounts** → Create.
   Name `play-store-uploader` or similar.
2. Grant role **Service Account User**; no project-wide access is needed.
3. Create a JSON key, download, base64 it.
4. Play Console → **Setup → API access** → Link the service account, grant
   **Release manager** access.
5. In CI: `GOOGLE_APPLICATION_CREDENTIALS_JSON` = base64'd JSON, and the
   service account can call `androidpublisher` API.

The CI workflow already does the upload via the publisher API. The
service account has to exist before the first automated upload.

### Step 5 — internal testing track

Left rail → **Testing → Internal testing** → **Create track**. Internal
testing does not require a review. Add testers' email addresses under
**Testers** → **Create email list**.

The first AAB uploaded to internal testing goes through a one-time
review (Play Store's automated checks) that takes a few hours. After
that, subsequent uploads to the same track take minutes.

### Step 6 — production track

Left rail → **Release → Production → Create release**. The first
release to production requires:
- All the store listing fields from Step 2 complete.
- A privacy policy URL.
- A target audience and content rating (questionnaire).
- A data safety form (separate from the privacy policy; mirrors what
  Apple App Privacy asks).
- A "Newsroom" or "What's new" note for the first release.

---

## Cross-store checklist (per new app)

Use this as a fill-in form when you add a new emulator to the family.

```
Bundle ID (iOS):           com.crownpark.<machine>
Android applicationId:     com.crownpark.<machine>
Display name (home):       Retro-<Machine>
App Store name:            <same>
Play Store name:           <same>
Short description (both):  <one sentence, <80 chars>
Full description (both):   <pitch, <4000 chars>
Privacy policy URL:        https://CrownParkComputing.github.io/Retro-<Machine>/privacy
Support URL:               https://github.com/CrownParkComputing/Retro-<Machine>/blob/main/README.md
GitHub repo:               https://github.com/CrownParkComputing/Retro-<Machine>
Licence (app):             GPL v3 (or per upstream core)
Category:                   Game > Arcade
Age rating:                4+
Territories:               all (default)
Compliance screen URL:     /<Machine> → ✅ Compliance
"Back to setup" wired:     yes (compliance screen → main.dart onRerunSetup)
Wizard version-keyed:       yes (isSetupCompletedFor(version))
CI build matrix:           analyze / linux / android / ios / release-on-tag
```

---

## Per-store one-time setup (do once, ever)

For each app, the platform-specific secrets are listed here so they can
be uploaded to GitHub Actions → Settings → Secrets and variables → Actions.

### iOS / App Store Connect

| Secret | Source |
|---|---|
| `APPSTORE_CERT_BASE64` | `.p12` of the Apple Distribution certificate, base64 |
| `APPSTORE_CERT_PASSWORD` | password used when exporting the `.p12` |
| `APPSTORE_PROFILE_BASE64` | the App Store provisioning profile (`.mobileprovision`), base64 |

### Android / Play

| Secret | Source |
|---|---|
| `ANDROID_KEYSTORE_BASE64` | the upload `.jks`, base64 |
| `ANDROID_KEYSTORE_PASSWORD` | keystore password |
| `ANDROID_KEY_ALIAS` | usually `upload` |
| `ANDROID_KEY_PASSWORD` | key password (often same as keystore password) |
| `GOOGLE_APPLICATION_CREDENTIALS_JSON` | the service account JSON key, base64 |

### Common to both

| Secret | Source |
|---|---|
| GitHub Actions `GITHUB_TOKEN` | automatic per workflow run; no setup needed |

---

## Per-store one-time setup (do once per emulator)

In App Store Connect, under **My Apps → <app> → General → App
Information**:

- **Name**: display name (max 30 chars)
- **Subtitle**: short pitch (max 30 chars)
- **Category**: **Games > Arcade**
- **Content Rights**: yes if the app contains third-party content
- **Age Rating**: 4+
- **Support URL**: support URL
- **Marketing URL**: optional
- **Privacy Policy URL**: required

In Play Console, under **App content → Privacy policy** and **App
content → Data safety**:

- **Privacy policy URL**: required
- **Data safety form**: declare nothing is collected. The form is
  lengthy; "No" to every question is the answer for an emulator that
  makes no network calls of its own.

Both stores show a checklist under the version page. Run through it
manually once; the entries are the same on subsequent releases.

---

## What cannot to do for this even after the app exists

These are the actions that remain manual-only even after the record
exists, and so come up on every release:

- App Store **App Review** submission is via web UI. The CLI submit
  flow eventually does work; the first version of an app needs the web
  UI to confirm export-compliance, fill in the encryption question, and
  approve the price schedule.
- Play Console **Production release** requires clicking "Roll out" in
  the web UI the first time. Subsequent rollouts via the publisher API
  work.
- **Pricing changes** are web-only on both stores.

Everything else (build numbers, screenshots, phase-of-release metadata)
has at least a partial API.