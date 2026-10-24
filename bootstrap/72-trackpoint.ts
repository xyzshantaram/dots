/**
 * ---
 * script: 72-trackpoint.ts
 * desc: Tags the TrackPoint as a pointing stick, because this stick reports a variant the kernel rejects and psmouse falls back to a generic mouse — which is why niri's trackpoint settings and the trackpoint acceleration curve never applied.
 * needs: 40-packages.ts up (udev)
 * up: writes /etc/udev/rules.d/99-trackpoint-ps2.rules, reloads the rules and re-triggers input, then checks that the tag is set
 * down: removes the rule, reloads and re-triggers
 * revisit: 2026-12-21
 * ---
 *
 * The problem, from the Fedora side's own notes and confirmed here: this stick
 * answers TP_READ_ID with variant 0x07, and drivers/input/mouse/trackpoint.c
 * accepts only 0x01-0x06, so trackpoint_detect() returns -ENODEV and psmouse
 * leaves the AUX port as a bare "PS/2 Logitech Mouse". Everything downstream
 * then treats it as a mouse:
 *
 *   - /sys/bus/serio/devices/serio1/{sensitivity,speed} never appears, because
 *     the kernel TrackPoint driver never bound. That is why the trackpoint
 *     section in config.kdl is libinput's accel-speed and not a sysfs value.
 *   - libinput applies its generic mouse curve rather than filter-trackpoint.c.
 *   - niri classifies the device as a mouse, so `input { trackpoint { } }` does
 *     nothing to it at all.
 *
 * Setting ID_INPUT_POINTINGSTICK fixes the last two. It is a userspace
 * workaround; the kernel fix wants TP_VARIANT 0x07 in trackpoint.c, which is a
 * rebuilt kernel and out of scope for this ladder.
 *
 * The tag is read when a consumer opens the device, so a running niri keeps the
 * old classification until it re-opens it — a logout, or the unbind/bind below.
 */
import process from "node:process";
import {
  existsInArch, fail, inArch, inArchSoft, main, needMount, ok, removeArch, say, writeArch,
} from "./lib.ts";

const RULE = "/etc/udev/rules.d/99-trackpoint-ps2.rules";
const SRC = `${import.meta.dir}/files/trackpoint/99-trackpoint-ps2.rules`;

async function refresh(): Promise<void> {
  await inArchSoft("udevadm", "control", "--reload-rules");
  await inArchSoft("udevadm", "trigger", "--subsystem-match=input", "--action=change");
}

async function up(): Promise<void> {
  await needMount();

  await writeArch(RULE, await Bun.file(SRC).text());
  say(`installed ${RULE}`);

  await refresh();

  // The tag lands in udev's database for the event device; this is the cheapest
  // way to see whether the rule actually matched.
  const tagged = await inArchSoft(
    "sh", "-c", "grep -ls ID_INPUT_POINTINGSTICK /run/udev/data/* 2>/dev/null | head -1",
  );
  if (tagged.stdout.toString().trim() === "") {
    say("udev does not report ID_INPUT_POINTINGSTICK; the rule did not match");
    process.exit(1);
  }
  say("udev tags the TrackPoint as a pointing stick");

  say("log out and back in so niri re-opens the device and applies trackpoint{}");
  say("or, without logging out: unbind and rebind serio1 from psmouse");
}

async function down(): Promise<void> {
  await needMount();

  await removeArch(RULE);
  say(`removed ${RULE}`);

  await refresh();
  say("udev reloaded; the device is a plain mouse again after it is re-opened");
}

async function verify(): Promise<void> {
  const rule = "/etc/udev/rules.d/99-trackpoint-ps2.rules";
  (await existsInArch(rule)) ? ok("trackpoint udev rule present") : fail("trackpoint udev rule missing");
}

await main({ up, down, verify });
