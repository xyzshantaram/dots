#!/usr/bin/env python3
"""Measure how long you hold CapsLock / Super, to choose overload_tap_timeout.

keyd's overload(meta, f13) fires the tap action when the key is released
without another key being pressed in between. overload_tap_timeout caps how
long a hold may last and still count as a tap, so anything longer is treated as
a deliberate modifier hold.

This watches the keyboard devices and records press->release durations, then
suggests a value. There is no single right answer: it depends on how quickly
you personally tap. Run it a few times, tapping as you would when you want the
drawer, and also holding as you would for Mod+T, so both populations show up.

Usage:
    python3 measure-taps.py            # watch, Ctrl+C to finish
    python3 measure-taps.py --seconds 30

Live events go to stderr; the summary goes to stdout so it can be piped.

Reading note: while keyd is running it grabs the physical keyboards, so events
arrive from keyd's virtual device. With the current keyd config both CapsLock
and Super appear there as KEY_LEFTMETA, which is fine here — we want the tap
duration for whichever key you use, and the timings are unchanged by remapping.
"""

import argparse
import fcntl
import glob
import os
import select
import signal
import struct
import sys
import time

EV_SYN = 0x00
EV_KEY = 0x01

KEY_CAPSLOCK = 58
KEY_LEFTMETA = 125
KEY_RIGHTMETA = 126

# struct input_event { timeval (16 bytes on 64-bit); __u16 type; __u16 code; __s32 value; }
EVENT = struct.Struct("llHHi")
EVENT_SIZE = EVENT.size

KEY_BIT_BYTES = 96  # covers KEY_MAX (0x2ff)

WATCHED = {
    KEY_CAPSLOCK: "capslock",
    KEY_LEFTMETA: "super",
    KEY_RIGHTMETA: "super-r",
}


def ioctl_bit(fd, ev, code):
    """True when the device reports support for `code` in the `ev` bitmap."""
    req = (2 << 30) | (KEY_BIT_BYTES << 16) | (ord("E") << 8) | (0x20 + ev)
    try:
        buf = fcntl.ioctl(fd, req, b"\0" * KEY_BIT_BYTES)
    except OSError:
        return False
    return bool(buf[code // 8] & (1 << (code % 8)))


def open_keyboards():
    """Every readable event device that can produce our keys."""
    found = []
    for path in sorted(glob.glob("/dev/input/event*")):
        try:
            fd = os.open(path, os.O_RDONLY | os.O_NONBLOCK)
        except PermissionError:
            continue
        except OSError:
            continue

        if not ioctl_bit(fd, EV_KEY, KEY_LEFTMETA) and not ioctl_bit(
            fd, EV_KEY, KEY_CAPSLOCK
        ):
            os.close(fd)
            continue

        caps = [name for code, name in WATCHED.items() if ioctl_bit(fd, EV_KEY, code)]
        name = ""
        try:
            with open(f"/sys/class/input/{os.path.basename(path)}/device/name") as fh:
                name = fh.read().strip()
        except OSError:
            pass
        found.append((path, fd, name, caps))
    return found


def summarise(samples):
    if not samples:
        return None
    xs = sorted(samples)
    n = len(xs)

    def pct(p):
        # nearest-rank; good enough for a sample of tens
        idx = min(n - 1, max(0, int(round(p / 100.0 * n)) - 1))
        return xs[idx]

    return {
        "n": n,
        "min": xs[0],
        "max": xs[-1],
        "median": xs[n // 2],
        "p75": pct(75),
        "p90": pct(90),
        "p95": pct(95),
    }


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--seconds", type=float, default=0, help="stop after N seconds")
    args = ap.parse_args()

    devices = open_keyboards()
    if not devices:
        print("no readable keyboard devices found", file=sys.stderr)
        print("on Arch this usually means the account is not in the `input` group", file=sys.stderr)
        return 1

    print(f"watching {len(devices)} device(s):", file=sys.stderr)
    for path, _, name, caps in devices:
        print(f"  {path}  {name or '(unnamed)'}  [{' '.join(caps)}]", file=sys.stderr)
    print("tap CapsLock/Super as you would for the drawer; Ctrl+C when done", file=sys.stderr)
    print("", file=sys.stderr)

    down_at = {}
    samples = []
    by_key = {}
    stopped = {"v": False}
    start = time.monotonic()

    def stop(*_):
        stopped["v"] = True

    signal.signal(signal.SIGINT, stop)
    signal.signal(signal.SIGTERM, stop)

    fds = {fd: (path, name) for path, fd, name, _ in devices}

    try:
        while not stopped["v"]:
            if args.seconds and time.monotonic() - start >= args.seconds:
                break
            try:
                ready, _, _ = select.select(list(fds), [], [], 0.25)
            except InterruptedError:
                continue

            for fd in ready:
                try:
                    data = os.read(fd, EVENT_SIZE * 64)
                except (BlockingIOError, OSError):
                    continue
                for off in range(0, len(data) - EVENT_SIZE + 1, EVENT_SIZE):
                    _, _, etype, code, value = EVENT.unpack_from(data, off)
                    if etype != EV_KEY or code not in WATCHED:
                        continue
                    if value == 2:  # autorepeat
                        continue

                    label = WATCHED[code]
                    if value == 1:
                        down_at[code] = time.monotonic()
                    elif value == 0 and code in down_at:
                        ms = (time.monotonic() - down_at.pop(code)) * 1000.0
                        samples.append(ms)
                        by_key.setdefault(label, []).append(ms)
                        print(f"  {label:<8} {ms:7.1f} ms", file=sys.stderr)
    finally:
        for fd in fds:
            os.close(fd)

    stats = summarise(samples)
    if stats is None:
        print("no taps recorded", file=sys.stderr)
        print("this can also happen if another process holds the devices", file=sys.stderr)
        return 1

    print(f"recorded {stats['n']} press/release(s)", file=sys.stderr)
    for label, xs in sorted(by_key.items()):
        print(f"  {label:<8} {len(xs)} sample(s)", file=sys.stderr)
    print("", file=sys.stderr)

    print("duration_ms")
    print(f"n\t{stats['n']}")
    for k in ("min", "median", "p75", "p90", "p95", "max"):
        print(f"{k}\t{stats[k]:.1f}")

    # Suggestion: a tap timeout wants to sit above your slowest deliberate tap
    # and below your shortest deliberate hold. p95 of everything you produced is
    # a starting point, rounded up to the next 50 ms. The real decider is the
    # gap between the two clusters below.
    suggest = max(50, int((stats["p95"] + 49) // 50 * 50))
    print("", file=sys.stderr)
    print(f"suggested overload_tap_timeout = {suggest}", file=sys.stderr)
    print("  (p95 of all holds, rounded up to 50ms)", file=sys.stderr)
    print("  if some of those were deliberate Mod+key holds, it will be too high;", file=sys.stderr)
    print("  re-run tapping only, then set it just above your slowest tap", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
