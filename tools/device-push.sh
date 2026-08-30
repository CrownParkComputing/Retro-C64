#!/usr/bin/env bash
# Get a build onto a real device: start MobAI, wait for the device, install,
# and optionally launch.
#
#   tools/device-push.sh --build            # build the iOS IPA first, then install
#   tools/device-push.sh                    # install the IPA already built
#   tools/device-push.sh --android --build  # build and install the Android APK
#   tools/device-push.sh --launch           # also start the app afterwards
#   tools/device-push.sh --run              # JUST start what is already installed
#
# WHY THIS EXISTS. Every part of getting a build onto the iPad fails quietly
# and for a different reason, and none of them announce themselves:
#
#   * The iosbox IPA is UNSIGNED. Signing happens at install time, through
#     MobAI, against an Apple ID session -- so "install" is not a file copy
#     and there is no adb-equivalent to fall back on.
#   * MobAI starts its OWN usbmuxd, extracted to ~/.mobai/bin/usbmuxd. The
#     distro package is NOT needed and `systemctl start usbmuxd` fails with
#     "Unit usbmuxd.service not found" -- which looks like the problem and
#     is not.
#   * That embedded usbmuxd is started through `pkexec`, so it needs a
#     polkit agent to ask for the password. From a plain non-graphical shell
#     you get "Error creating textual authentication agent ... /dev/tty",
#     usbmuxd never starts, and the device list is silently empty forever.
#
# So the order matters and each step is checked separately, with the failure
# named rather than left to be inferred from an empty list.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
API="http://127.0.0.1:8686/api/v1"
MOBAI="${MOBAI_BIN:-$HOME/.local/bin/mobai}"
LOG="${TMPDIR:-/tmp}/mobai-serve.log"

BUILD=0
LAUNCH=0
RUN_ONLY=0
ANDROID=0
ARTIFACT=""
WAIT_SECS="${WAIT_SECS:-90}"

while [ $# -gt 0 ]; do
  case "$1" in
    --build)   BUILD=1 ;;
    --launch)  LAUNCH=1 ;;
    --run)     RUN_ONLY=1; LAUNCH=1 ;;
    --android) ANDROID=1 ;;
    --ipa|--apk) ARTIFACT="$2"; shift ;;
    --timeout) WAIT_SECS="$2"; shift ;;
    -h|--help) sed -n '2,10p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
  shift
done

say()  { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }
ok()   { printf '    \033[32mOK\033[0m %s\n' "$*"; }
warn() { printf '    \033[33m!!\033[0m %s\n' "$*"; }
die()  { printf '\n\033[1;31mSTOPPED: %s\033[0m\n' "$*" >&2; exit 1; }

# Start the app with a debugger attached.
#
# withDebugger is not optional, and it is NOT called `debug` here -- that is
# the MCP tool's name for it; the HTTP API calls it withDebugger ("enables JIT
# for Flutter debug builds"). iosbox only ever produces a DEBUG/JIT build, and
# iOS kills a Flutter JIT process within a second unless something is attached,
# which is why tapping the home-screen icon opens and instantly closes it.
# See docs/IOS_BUILD.md, "Debug configuration only".
#
# The bundle ID carries the signing team suffix, because sideloading re-signs
# under your own team; the installed one is looked up rather than assumed.
launch_app() {
  say "Launching"
  local bundle
  bundle="$(curl -fsS -m 30 "$API/devices/$DEVICE_ID/apps" 2>/dev/null | python3 -c '
import json,sys
try: d = json.load(sys.stdin)
except Exception: sys.exit(0)
apps = d.get("apps", d) if isinstance(d, dict) else d
for a in apps if isinstance(apps, list) else []:
    b = a.get("bundleId", "") if isinstance(a, dict) else str(a)
    if b.startswith("com.crownparkcomputing.c64-retro"):
        print(b); break
')"
  bundle="${bundle:-com.crownparkcomputing.c64-retro}"
  echo "    $bundle"
  curl -sS -m 180 -X POST "$API/devices/$DEVICE_ID/launch-app" \
    -H 'Content-Type: application/json' \
    -d "{\"bundleId\":\"$bundle\",\"withDebugger\":true}" \
    -w '\n    HTTP %{http_code}\n' | tail -2
}

# ---------------------------------------------------------------------------
# Android: adb does the whole job and none of the above applies
# ---------------------------------------------------------------------------
if [ "$ANDROID" = 1 ]; then
  say "Android: building and installing over adb"
  command -v adb >/dev/null || die "adb not on PATH."
  if [ "$BUILD" = 1 ]; then
    ( cd "$REPO_ROOT/flutter_app" && flutter build apk --release ) || die "APK build failed."
  fi
  APK="${ARTIFACT:-$REPO_ROOT/flutter_app/build/app/outputs/flutter-apk/app-release.apk}"
  [ -f "$APK" ] || die "No APK at $APK -- run with --build."
  if [ -z "$(adb devices | awk 'NR>1 && $2=="device"')" ]; then
    die "No Android device. Plug it in, unlock it, and accept the USB-debugging prompt."
  fi
  adb install -r "$APK" || die "adb install failed."
  ok "installed $(basename "$APK")"
  [ "$LAUNCH" = 1 ] && adb shell monkey -p com.crownparkcomputing.c64retro -c android.intent.category.LAUNCHER 1 >/dev/null
  exit 0
fi

# ---------------------------------------------------------------------------
# iOS
# ---------------------------------------------------------------------------
say "Checking the desktop session"
# pkexec has to be able to ask for a password. Without a session it fails with
# a message about /dev/tty that says nothing about usbmuxd, and the only
# visible symptom is that no device ever appears.
if [ -z "${DISPLAY:-}" ] && [ -z "${WAYLAND_DISPLAY:-}" ]; then
  warn "No DISPLAY or WAYLAND_DISPLAY."
  warn "MobAI elevates its bundled usbmuxd with pkexec, which needs a polkit"
  warn "agent to prompt you. Run this from a terminal in your desktop session,"
  warn "or start the MobAI app by hand first and re-run."
else
  ok "graphical session present (pkexec can prompt)"
fi

say "Starting MobAI"
if curl -fsS -m 3 "$API/health" >/dev/null 2>&1; then
  ok "already running on 127.0.0.1:8686"
else
  [ -x "$MOBAI" ] || die "MobAI not found at $MOBAI (set MOBAI_BIN)."
  # No subcommand: the binary is a desktop app that serves the HTTP API and
  # the MCP endpoint as a side effect. `mobai serve` parses no differently.
  nohup "$MOBAI" >"$LOG" 2>&1 &
  echo "    started pid $!, log: $LOG"
  for _ in $(seq 30); do
    curl -fsS -m 2 "$API/health" >/dev/null 2>&1 && break
    sleep 1
  done
  curl -fsS -m 3 "$API/health" >/dev/null 2>&1 \
    || die "API never came up. Check $LOG"
  ok "API up on 127.0.0.1:8686"
fi

say "Waiting for usbmuxd"
# pkexec needs something to show the password dialog with. polkitd alone is
# not enough -- on Hyprland the agent is a separate unit, and with it stopped
# pkexec cannot prompt, usbmuxd never starts, and the only symptom is a
# device list that stays empty. Start it rather than diagnose it later.
if ! pgrep -x hyprpolkitagent >/dev/null 2>&1 \
   && ! pgrep -f 'polkit-(gnome|kde|mate)|xfce-polkit|lxpolkit' >/dev/null 2>&1; then
  if systemctl --user list-unit-files hyprpolkitagent.service >/dev/null 2>&1; then
    warn "no polkit agent running -- starting hyprpolkitagent"
    systemctl --user start hyprpolkitagent 2>/dev/null || true
  else
    warn "no polkit authentication agent is running, so pkexec cannot ask"
    warn "for your password. Install/start one for your desktop first."
  fi
fi
# 60s, not 30: elevation plus first-run extraction genuinely takes that long,
# and a short wait reports "no device" for what is really "not ready yet".
for _ in $(seq 60); do
  [ -S /var/run/usbmuxd ] && break
  sleep 1
done
if [ -S /var/run/usbmuxd ]; then
  ok "usbmuxd socket ready"
else
  warn "no /var/run/usbmuxd after 30s."
  warn "If a password prompt appeared and was dismissed, re-run. If none"
  warn "appeared, MobAI could not elevate -- start the MobAI app from your"
  warn "desktop, approve the prompt, then re-run this script."
  grep -iE 'usbmuxd|pkexec|elevation' "$LOG" 2>/dev/null | tail -5
fi

say "Looking for a device"
DEVICE_JSON=""
for _ in $(seq "$WAIT_SECS"); do
  DEVICE_JSON="$(curl -fsS -m 5 "$API/devices" 2>/dev/null)"
  if [ -n "$DEVICE_JSON" ] && [ "$DEVICE_JSON" != "[]" ] \
     && printf '%s' "$DEVICE_JSON" | grep -q '"id"'; then
    break
  fi
  sleep 1
done

DEVICE_ID="$(printf '%s' "${DEVICE_JSON:-}" | python3 -c '
import json,sys
try: d = json.load(sys.stdin)
except Exception: sys.exit(0)
items = d.get("devices", d) if isinstance(d, dict) else d
if isinstance(items, list) and items:
    dev = items[0]
    print(dev.get("id") or dev.get("udid") or "")
')"

if [ -z "$DEVICE_ID" ]; then
  die "No device after ${WAIT_SECS}s.
    Plug the iPad/iPhone in, UNLOCK it, and tap Trust on the
    'Trust This Computer?' prompt -- an unlocked, trusted device is the only
    kind usbmuxd reports. A charge-only cable also looks exactly like this.
    Devices seen: ${DEVICE_JSON:-<none>}"
fi
ok "device $DEVICE_ID"

if [ "$BUILD" = 1 ]; then
  say "Building the IPA"
  "$REPO_ROOT/tools/build-ios-linux.sh" || die "iOS build failed."
fi

if [ "$RUN_ONLY" = 1 ]; then
  # Nothing to build or install: this exists because the app CANNOT be started
  # by tapping its icon. iosbox only produces a debug/JIT build, and iOS kills
  # a Flutter JIT process within a second unless a debugger is attached -- from
  # the home screen that looks exactly like an instant crash. Attaching one is
  # all this does, so the app can be started without a rebuild and without me.
  say "Starting the installed app"
  launch_app
  say "Done"
  exit 0
fi

IPA="${ARTIFACT:-$REPO_ROOT/flutter_app/build/iosbox/Runner.ipa}"
[ -f "$IPA" ] || die "No IPA at $IPA -- run with --build."
say "Installing $(basename "$IPA") ($(du -h "$IPA" | cut -f1))"

# Body per the server's own schema (GET /api/v1/openapi.json ->
# POST /devices/{id}/install-app): `path` is the only required field, and
# `resign` is what makes this work at all -- the iosbox IPA is unsigned, and
# without resign the install is a copy of something iOS will refuse to run.
# The Apple ID password is deliberately not passed: MobAI uses the cached
# session, so this script never handles the credential.
BODY_JSON="$(APPLE_ID="${MOBAI_APPLE_ID:-}" IPA_PATH="$IPA" python3 -c '
import json, os
body = {"path": os.environ["IPA_PATH"], "resign": True}
if os.environ.get("APPLE_ID"):
    body["appleId"] = os.environ["APPLE_ID"]
print(json.dumps(body))
')"

RESPONSE="$(curl -sS -m 600 -X POST "$API/devices/$DEVICE_ID/install-app" \
  -H 'Content-Type: application/json' \
  -d "$BODY_JSON" \
  -w '\n%{http_code}')"
CODE="$(printf '%s' "$RESPONSE" | tail -1)"
BODY="$(printf '%s' "$RESPONSE" | sed '$d')"

case "$CODE" in
  2*) ok "installed" ;;
  *)
    echo "$BODY"
    case "$BODY" in
      *"no valid cached credentials"*|*signing*)
        die "Signing failed. The IPA is unsigned and MobAI signs it at install
    time, so this needs a live Apple ID session -- open the MobAI app and
    sign in again, then re-run." ;;
      *"free developer account limit"*)
        die "Apple's 3-app sideload limit for free accounts. Delete another
    sideloaded app from the device and re-run." ;;
      *) die "install-app returned HTTP $CODE" ;;
    esac ;;
esac

if [ "$LAUNCH" = 1 ]; then
  launch_app
fi

say "Done"
