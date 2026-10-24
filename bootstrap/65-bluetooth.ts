/**
 * ---
 * script: 65-bluetooth.ts
 * desc: Installs BlueZ and enables bluetoothd, so there is an adapter to control.
 * needs: 40-packages.ts up
 * up: pacman -S bluez bluez-utils, systemctl enable bluetooth.service
 * down: systemctl disable bluetooth.service, pacman -Rns bluez bluez-utils
 * revisit: 2026-12-21
 * ---
 *
 * bluez-libs is not this. Something else pulls it in, and it carries neither the
 * daemon nor bluetoothctl — so org.bluez never appears on the bus, quickshell's
 * Bluetooth module finds no adapter, and the bar draws the crossed-out glyph
 * while the control centre's toggle has nothing to toggle. The package that
 * makes the hardware exist here is bluez, and bluetoothctl is bluez-utils.
 *
 * The unit is enabled, and started when the ladder is running the live system.
 * In a chroot starting it would be a daemon with no hardware to probe; live, it
 * is the difference between a step you have to reboot after and one that leaves
 * an adapter the shell can see straight away.
 *
 * The adapter's own power state is deliberately not forced. BlueZ remembers it
 * across boots, and the shell has a toggle for it — a step that turned it on
 * would fight whoever turned it off.
 */
import { LIVE, fail, inArch, inArchSoft, main, needMount, ok, say } from "./lib.ts";

const PKGS = ["bluez", "bluez-utils"];

async function up(): Promise<void> {
  await needMount();
  const install = await inArch(
    "pacman", "-S", "--needed", "--noconfirm", ...PKGS,
  ).nothrow();
  if (install.exitCode !== 0) {
    say("pacman failed; see above");
    process.exit(install.exitCode);
  }
  if (LIVE) {
    await inArch("systemctl", "enable", "--now", "bluetooth.service");
  } else {
    await inArch("systemctl", "enable", "bluetooth.service");
  }
  say(`BlueZ installed, bluetooth.service ${LIVE ? "started and enabled" : "enabled for next boot"}`);
  say((await inArch("bluetoothctl", "--version").text()).trim());
}

async function down(): Promise<void> {
  await needMount();
  await inArchSoft("systemctl", "disable", "bluetooth.service");
  for (const pkg of PKGS) {
    await inArchSoft("pacman", "-Rns", "--noconfirm", pkg);
  }
  say("bluetooth service disabled and packages removed; failures ignored");
}

async function verify(): Promise<void> {
  const installed = await inArchSoft("pacman", "-T", ...PKGS);
  const missing = installed.stdout.toString().trim();
  if (installed.exitCode !== 0 && missing !== "") {
    fail(`missing packages: ${missing.replace(/\n/g, " ")}`);
  } else {
    ok("bluez and bluez-utils are installed");
  }

  const enabled = await inArchSoft("systemctl", "is-enabled", "bluetooth.service");
  enabled.exitCode === 0
    ? ok("bluetooth.service is enabled")
    : fail("bluetooth.service is not enabled");

  const ctl = await inArchSoft("test", "-x", "/usr/bin/bluetoothctl");
  ctl.exitCode === 0
    ? ok("bluetoothctl is present")
    : fail("bluetoothctl is not at /usr/bin/bluetoothctl");
}

await main({ up, down, verify });
