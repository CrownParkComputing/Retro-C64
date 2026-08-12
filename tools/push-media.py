#!/usr/bin/env python3
"""Copy C64 media onto the iPad, into the app's Documents folder.

    tools/push-media.py ~/Downloads/aria2/c64            # every *.zip in there
    tools/push-media.py ~/somewhere --glob '*.d64'
    tools/push-media.py ~/somewhere --into games         # a subfolder

Needs pymobiledevice3 and a trusted, unlocked device. MobAI's usbmuxd must be
running -- `tools/device-push.sh --run` brings it up if it is not.

Two things this exists to encode, both discovered the hard way:

  * The remote path needs a `Documents/` prefix even though house arrest is
    opened in documents-only mode. Without it every write fails with a bare
    "FILE_OPEN failed with status: 10", which says nothing about paths.
  * One AFC session for the whole batch. The pymobiledevice3 CLI takes one
    file per invocation, and paying the USB handshake ~3000 times turns a
    40-second job into an afternoon.
"""
import argparse
import asyncio
import pathlib
import sys
import time

from pymobiledevice3.lockdown import create_using_usbmux
from pymobiledevice3.services.house_arrest import HouseArrestService

# The sideloaded bundle carries the signing team's suffix; the plain ID is
# only correct for a store build.
DEFAULT_BUNDLE = "com.vicemultiplatform.app.88A3T9K9C5"


async def run(args) -> int:
    src = pathlib.Path(args.source).expanduser()
    if not src.is_dir():
        print(f"error: no such directory {src}", file=sys.stderr)
        return 1
    files = sorted(p for p in src.glob(args.glob) if p.is_file())
    if not files:
        print(f"error: nothing matching {args.glob} in {src}", file=sys.stderr)
        return 1

    total_bytes = sum(p.stat().st_size for p in files)
    print(f"{len(files)} file(s), {total_bytes/1e6:.0f} MB -> {args.bundle}")

    lockdown = await create_using_usbmux()
    ha = HouseArrestService(lockdown=lockdown, documents_only=True)
    await ha.send_command(args.bundle)

    remote_dir = "Documents" + (f"/{args.into}" if args.into else "")
    if args.into:
        try:
            await ha.makedirs(remote_dir)
        except Exception:
            pass  # already there

    t0 = time.time()
    sent = failed = 0
    for i, f in enumerate(files, 1):
        try:
            await ha.set_file_contents(f"{remote_dir}/{f.name}", f.read_bytes())
            sent += 1
        except Exception as e:
            failed += 1
            print(f"  ! {f.name}: {e}", file=sys.stderr)
        if i % 250 == 0 or i == len(files):
            rate = i / max(0.001, time.time() - t0)
            print(f"  {i}/{len(files)}  ({rate:.0f} files/s)")

    dt = time.time() - t0
    print(f"done: {sent} sent, {failed} failed, {dt:.0f}s")
    print(f"On the device: Paths & Setup -> Scan for games.")
    return 0 if failed == 0 else 1


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("source", help="local directory to copy from")
    ap.add_argument("--glob", default="*.zip", help="which files (default *.zip)")
    ap.add_argument("--into", default="", help="subfolder of Documents")
    ap.add_argument("--bundle", default=DEFAULT_BUNDLE)
    return asyncio.run(run(ap.parse_args()))


if __name__ == "__main__":
    raise SystemExit(main())
