/**
 * ---
 * script: 155-battery.ts
 * desc: Ports the battery and power tweaks from ../battery-sleep-configs: charge thresholds 65/85, audio codec power saving, wifi powersave, keyboard backlight off, pm_async off.
 * needs: 40-packages.ts up (networkmanager)
 * up: installs the threshold helper, unit and udev rule, the modprobe and tmpfiles drop-ins, and the NetworkManager conf
 * down: removes all of it
 * revisit: 2026-12-21
 * ---
 *
 * Not ported on purpose: tuned-ppd and the tuned profiles (no tuned on Arch),
 * PowerDevil and powerdevilrc (no KDE). The dictation NPU sleep hook is
 * installed by 170-dictation.ts, because it is meaningless without dictation.
 *
 * The ThinkPad charge-threshold helper and its udev rule were not in the
 * battery-sleep-configs repo: they live in Fedora's /usr/local/bin and
 * /etc/udev. They are vendored into files/battery/ so this port is
 * self-contained.
 */
import { existsInArch, fail, inArchSoft, main, needMount, ok, removeArch, say, writeArch } from "./lib.ts";

const F = `${import.meta.dir}/files/battery`;

async function up(): Promise<void> {
  await needMount();

  await writeArch(
    "/usr/local/bin/battery-charge-thresholds",
    await Bun.file(`${F}/battery-charge-thresholds`).text(),
    0o755,
  );
  await writeArch(
    "/etc/systemd/system/battery-charge-thresholds.service",
    await Bun.file(`${F}/battery-charge-thresholds.service`).text(),
  );
  await writeArch(
    "/etc/udev/rules.d/99-battery-charge-thresholds.rules",
    await Bun.file(`${F}/99-battery-charge-thresholds.rules`).text(),
  );
  await inArchSoft("systemctl", "enable", "battery-charge-thresholds.service");
  say("charge thresholds 65/85 installed and enabled");

  await writeArch(
    "/etc/modprobe.d/audio-mute.conf",
    await Bun.file(`${F}/audio-mute.conf`).text(),
  );
  say("audio codec power saving (power_save=8) installed");

  await writeArch(
    "/etc/tmpfiles.d/keyboard-backlight-off.conf",
    await Bun.file(`${F}/keyboard-backlight-off.conf`).text(),
  );
  await writeArch(
    "/etc/tmpfiles.d/pm-async-workaround.conf",
    await Bun.file(`${F}/pm-async-workaround.conf`).text(),
  );
  say("tmpfiles installed (keyboard backlight off, pm_async=0)");

  await writeArch(
    "/etc/NetworkManager/conf.d/wifi-powersave.conf",
    await Bun.file(`${F}/wifi-powersave.conf`).text(),
  );
  say("NetworkManager wifi powersave = 3");
  say("all of this applies from the next boot; nothing is started in this chroot");
}

async function down(): Promise<void> {
  await needMount();

  // Put the EC thresholds back to full range while the helper still exists.
  await inArchSoft(
    "env", "START=0", "END=100", "/usr/local/bin/battery-charge-thresholds",
  );
  await inArchSoft("systemctl", "disable", "battery-charge-thresholds.service");

  for (const rel of [
    "/usr/local/bin/battery-charge-thresholds",
    "/etc/systemd/system/battery-charge-thresholds.service",
    "/etc/udev/rules.d/99-battery-charge-thresholds.rules",
    "/etc/modprobe.d/audio-mute.conf",
    "/etc/tmpfiles.d/keyboard-backlight-off.conf",
    "/etc/tmpfiles.d/pm-async-workaround.conf",
    "/etc/NetworkManager/conf.d/wifi-powersave.conf",
  ]) {
    await removeArch(rel);
  }
  say("removed the battery and power files; thresholds reset to 0/100");
}

async function verify(): Promise<void> {
  for (const f of [
    "/usr/local/bin/battery-charge-thresholds",
    "/etc/systemd/system/battery-charge-thresholds.service",
    "/etc/udev/rules.d/99-battery-charge-thresholds.rules",
    "/etc/modprobe.d/audio-mute.conf",
    "/etc/NetworkManager/conf.d/wifi-powersave.conf",
    "/etc/tmpfiles.d/keyboard-backlight-off.conf",
    "/etc/tmpfiles.d/pm-async-workaround.conf",
  ]) {
    (await existsInArch(f)) ? ok(`present: ${f.split("/").pop()}`) : fail(`missing: ${f}`);
  }
}

await main({ up, down, verify });
