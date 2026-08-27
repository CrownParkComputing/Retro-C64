# App Store Connect credentials on a second machine

Everything `tools/appstore/asc.rb` needs, and how to put it on a machine that
has never had it — a new Mac, a rented one, or CI.

## The three pieces

| Piece | Secret? | Where it lives |
|---|---|---|
| Key ID | no — an identifier | `~/.config/appstore.env` |
| Issuer ID | no — an identifier | `~/.config/appstore.env` |
| Private key `.p8` | **yes, entirely** | `~/.appstoreconnect/private_keys/` |

The first two are useless on their own: they name a key, they do not
authenticate as one. The `.p8` is the whole credential.

```
ASC_KEY_ID=UNF5PJ6LDK
ASC_ISSUER_ID=f32cdb13-fd78-4451-9621-f766abb8d1ba
ASC_BUNDLE_ID=com.example.theapp     # per app; see below
```

The key is **account-wide, not per-app**, so one key already reaches every
record on the account. A new app record needs no new key.

## The `.p8` is not in this repository, and must not be

It is not committed here, `*.p8` is in `.gitignore`, and it should stay that
way. Not caution for its own sake — the specific reasons:

- **git history is permanent.** A key committed and then deleted is still in
  every clone, every fork, and every CI cache that ever fetched the repo.
  Removing it means rewriting history and force-pushing, and you still have to
  assume it leaked.
- **Apple will not re-issue it.** The `.p8` downloads exactly once, at
  creation. A leaked key cannot be rotated in place: you revoke it, generate a
  new one, and update every machine and every CI secret that used it.
- **It is account-wide.** This key can create and modify app records, upload
  builds, and submit for review across the whole account — not just one app.
- **This repository already does it the other way.** Every other credential in
  `.github/workflows/build.yml` is a GitHub secret, not a file:
  `ANDROID_KEYSTORE_BASE64`, `APPSTORE_CERT_BASE64`, `APPSTORE_PROFILE_BASE64`.
  The `.p8` belongs in the same place, for the same reason.

## Provisioning a second Mac

**1. Copy the key across a channel that is not a repository.** AirDrop, a
password manager, an encrypted disk image, or `scp` over SSH. Whatever you
use, the file must arrive byte-identical — it is PEM text, so anything that
rewrites line endings will break it.

```sh
mkdir -p ~/.appstoreconnect/private_keys
# ...copy AuthKey_<KEY_ID>.p8 into that directory...
chmod 600 ~/.appstoreconnect/private_keys/AuthKey_*.p8
```

**The filename matters.** The tooling builds the path from the key ID as
`AuthKey_<ASC_KEY_ID>.p8`. Renamed, it is not found.

**2. Write the identifiers.**

```sh
mkdir -p ~/.config
cat > ~/.config/appstore.env <<'ENV'
ASC_KEY_ID=UNF5PJ6LDK
ASC_ISSUER_ID=f32cdb13-fd78-4451-9621-f766abb8d1ba
ASC_BUNDLE_ID=com.example.theapp
ENV
chmod 600 ~/.config/appstore.env
```

`ASC_BUNDLE_ID` selects which app record the tooling talks to, and the file
holds only one. Set it to the app you are releasing, or override per command:

```sh
ASC_BUNDLE_ID=com.crownpark.retroc64.app tools/appstore/asc.rb status
```

**3. Install fastlane**, which `asc.rb` loads spaceship from:

```sh
brew install fastlane
```

**4. Check it.** `status` naming the app you expect is the proof all three
pieces are right — a wrong key fails to authenticate, a wrong bundle ID says
`no app record for ...`.

```sh
tools/appstore/asc.rb status
```

Signing a build additionally needs the distribution certificate and profile,
which are a separate story — see "Phase 1" in `docs/APP_STORE_RELEASE.md`.

## Putting the key into CI

Base64 it into a repository secret. Run this on the machine that **has** the
key; it prints the value to paste into GitHub → Settings → Secrets and
variables → Actions:

```sh
base64 -i ~/.appstoreconnect/private_keys/AuthKey_UNF5PJ6LDK.p8 | pbcopy
```

Add three secrets — `ASC_KEY_P8_BASE64`, `ASC_KEY_ID`, `ASC_ISSUER_ID` — then
reconstruct the file in the job, matching how the Android keystore is already
handled in `build.yml`:

```yaml
- name: App Store Connect API key
  env:
    ASC_KEY_P8_BASE64: ${{ secrets.ASC_KEY_P8_BASE64 }}
    ASC_KEY_ID: ${{ secrets.ASC_KEY_ID }}
    ASC_ISSUER_ID: ${{ secrets.ASC_ISSUER_ID }}
  run: |
    mkdir -p ~/.appstoreconnect/private_keys ~/.config
    printf '%s' "$ASC_KEY_P8_BASE64" | base64 --decode \
      > ~/.appstoreconnect/private_keys/AuthKey_${ASC_KEY_ID}.p8
    chmod 600 ~/.appstoreconnect/private_keys/AuthKey_${ASC_KEY_ID}.p8
    printf 'ASC_KEY_ID=%s\nASC_ISSUER_ID=%s\n' \
      "$ASC_KEY_ID" "$ASC_ISSUER_ID" > ~/.config/appstore.env
```

Never `echo` the decoded key, and keep it out of `set -x` blocks — Actions
masks registered secret values in logs, but not anything derived from them.

## If it does leak

Assume the worst and act immediately; the key is account-wide.

1. App Store Connect → Users and Access → Integrations → Keys → **Revoke**.
2. Generate a new key and download the `.p8` (once).
3. Update every machine and every CI secret.
4. Review recent activity — builds, submissions, and any user changes.
