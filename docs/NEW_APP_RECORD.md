# Creating a new App Store record

Phase 0 of `docs/APP_STORE_RELEASE.md`, written out in full because it is the
one phase that **cannot be scripted** and the one most likely to be reached in
a hurry — usually after discovering that the bundle ID in the Xcode project
does not match the record that already exists.

Like the release runbook this is deliberately generic; the worked example at
the bottom is Retro-C64.

## The one thing to know first

**The App Store Connect API cannot create app records.** `POST /v1/apps` is
refused outright:

```
The resource 'apps' does not allow 'CREATE'.
Allowed operations are: GET_COLLECTION, GET_INSTANCE, UPDATE
```

So `tools/appstore/asc.rb` — which does everything else — cannot do this, and
neither can any other API-key tool. The record is made by hand in a browser,
once, and every automated step (`status`, `builds`, `attach`, `submit`) only
starts working *after* it exists. Budget for a human being at a keyboard.

The **bundle ID** half *is* scriptable, and is worth doing first (below).

## Before you create anything: is a new record really what you want?

A new record is expensive and permanent. Ask whether the cheaper move applies:

- **A bundle ID mismatch is usually the accident, not the plan.** If the
  project's `PRODUCT_BUNDLE_IDENTIFIER` stopped matching the store record,
  check *when* it changed (`git log -S"<bundle id>" -- path/to/project.pbxproj`).
  If the rename was incidental to some unrelated commit, reverting the project
  is one line and keeps the record, its build history, metadata, screenshots,
  pricing and privacy answers.
- **A rejection is not a reason to start over.** A rejected version stays
  editable: fix the cause, upload a new build, attach it, resubmit.

Start a new record when the *product* is genuinely new, or when the bundle ID
must change and the old record is being abandoned deliberately. Nothing
carries over — see "What starting over actually costs" below.

## Step 1 — Register the bundle ID (scriptable)

The identifier must exist in the Developer portal before the record can point
at it. This *is* available over the API:

```rb
Spaceship::ConnectAPI::BundleId.create(
  name: "Retro C64",                        # portal label; letters/spaces/digits
  platform: "UNIVERSAL",                    # iOS + macOS; not per-device-family
  identifier: "com.crownpark.retroc64.app") # permanent
```

Notes that cost time if missed:

- `name` is only the portal's own label. It is **not** the App Store name, and
  Apple rejects punctuation here — `Retro-C64` fails, `Retro C64` is fine.
- `identifier` can never be changed or reused, even after deletion.
- Reverse-DNS, and it should match the Android `applicationId`, or the two
  stores diverge for the rest of the app's life.
- List what is already registered before adding: a half-finished earlier
  attempt is easy to miss, and the portal shows `<id>.<TEAMID>` wildcard
  siblings that look like duplicates but are not.

## Step 2 — Create the record (browser only)

appstoreconnect.apple.com → **Apps** → **+** → **New App**.

| Field | What to put | Changeable later? |
|---|---|---|
| Platforms | iOS (tick macOS only if actually shipping one) | adding is fine |
| Name | the public App Store name, ≤30 chars | yes, between versions |
| Primary language | must match the locale the metadata is written in | yes |
| Bundle ID | pick the one from step 1 | **never** |
| SKU | your own reference, never shown to users | **never** |
| User access | Full Access unless you have a reason | yes |

Two that bite:

- **The name must be unique across the entire App Store**, not just your
  account. There is no availability API — the form is where you find out. Have
  a second choice ready. If you already ship a similarly-named app, that name
  is taken *by you*.
- **The SKU is permanent and cannot be reused**, including by a deleted app.
  Something like `RETROC64-2026` is fine; the bundle ID again is also fine.

## Step 3 — Do the account-level gates immediately

This is the trap Phase 2 of the release runbook warns about, and a brand-new
record has *all* of them unset. None appears as a warning anywhere; they
surface once, as a generic "not in valid state", on the day you try to submit:

- **Pricing** — even free needs a price schedule
  (`asc.rb price <TERRITORY> 0`)
- **App Privacy** — the questionnaire, answered and published
- **Age rating**
- **Primary and secondary category**
- **Content rights** declaration

Do these the day the record is made, not the day you ship.

## Step 4 — Point the tooling at it

`tools/appstore/asc.rb` reads `ASC_BUNDLE_ID` from `~/.config/appstore.env`.
That file holds **one** bundle ID, so it keeps pointing at the old record
until changed — and every command silently addresses the wrong app until it
does. Either edit it, or pass the ID per invocation:

```sh
ASC_BUNDLE_ID=com.example.newapp tools/appstore/asc.rb status
```

`status` naming the app you expect is the check that step 2 worked. From here
the normal release loop (Phases 3–7) applies.

## What starting over actually costs

Nothing transfers between records. Budget for:

- every screenshot set, for every display size the binary claims — and a
  binary claiming iPhone **and** iPad needs both
- description, keywords, promotional text, support and marketing URLs
- pricing, App Privacy, age rating, categories (step 3)
- the build history: numbering restarts, and no TestFlight tester carries over
- **a full review, not a resubmission** — a first review of a new app is
  slower and stricter than a re-review of a rejected version

## Worked example — Retro-C64, 2026-08-22

The project had been renamed to `com.crownpark.retroc64.app` in commit
`fcef23d`, nine minutes *after* build 36 was uploaded to the existing
`com.vicemultiplatform.app` record ("C64-Retro", 36 builds, metadata and
screenshots complete). So no build with the current ID had ever been
uploaded, and the ID on a record can never change.

Bundle ID registered over the API as above → `R4QL3RS8BM`. The record itself
was blocked on step 2, by hand, with:

- Name: **Retro-C64**
- Bundle ID: `com.crownpark.retroc64.app`
- SKU: `RETROC64-2026`
- Primary language: **English (U.K.)** — matches the existing `en-GB` metadata

Worth recording because it is the cautionary half of this document: the
cheaper path was available throughout. Version 1.0.0 on the old record was
rejected only because App Review had no BIOS ROMs to test with, and the fix —
the bundled Open ROMs behind the wizard's "Store Compliance" button — was
already in the tree. Reverting one line in `project.pbxproj` would have
resubmitted it the same day.
