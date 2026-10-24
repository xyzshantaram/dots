/**
 * ---
 * script: 145-hibernate.ts
 * desc: Makes the Arch side hibernate-only and makes hibernation resume: resume hook in the initramfs, suspend->hibernate redirect, logind lid handling.
 * needs: 10-mount.ts up, 40-packages.ts up, KERNEL in .env
 * up: adds `resume` to mkinitcpio HOOKS and rebuilds, installs the sleep and logind drop-ins, and the image_size tmpfile
 * down: restores mkinitcpio.conf, removes the helpers, drop-ins and tmpfiles, rebuilds the initramfs
 * revisit: 2026-12-21
 * ---
 *
 * Swap sizing is the constraint here: hibernation needs somewhere big enough
 * for the image, and it has to be a real swap partition, not zram. A dedicated
 * partition is the usual answer, and its size should be at least RAM.
 *
 * When a swap partition is shared with another installed OS, whoever hibernates
 * owns it: booting the other one starts that swap unit and discards the image.
 *
 * Arch's default HOOKS are busybox-based, so the `resume` hook is required and
 * must follow `udev`. A systemd-hook initramfs would get resume for free.
 */
import { $ } from "bun";
import process from "node:process";
import {
  SWAP_UUID, at, existsInArch, fail, inArch, inArchSoft, main, needMount, ok, readArch,
  removeArch, restoreBackup, say, writeArch,
} from "./lib.ts";

const MKINITCPIO = "/etc/mkinitcpio.conf";

async function up(): Promise<void> {
  await needMount();

  const conf = await readArch(MKINITCPIO);
  if (conf === null) {
    say(`${MKINITCPIO} missing; is this a real Arch root?`);
    process.exit(1);
  }

  const hooksLine = conf.split("\n").find((l) => /^HOOKS=/.test(l.trim()));
  if (!hooksLine) {
    say("no HOOKS= line in mkinitcpio.conf");
    process.exit(1);
  }

  if (/\bresume\b/.test(hooksLine)) {
    say("resume hook already present");
  } else {
    await $`cp -a ${at(MKINITCPIO)} ${at(`${MKINITCPIO}.hib-save`)}`.quiet();

    // resume must follow udev (the swap device is referred to by udev node)
    // and precede filesystems. Inserting before `block` does both.
    const next = hooksLine.replace(/\bblock\b/, "resume block");
    if (next === hooksLine) {
      say("could not find `block` in HOOKS; edit mkinitcpio.conf by hand");
      process.exit(1);
    }
    await writeArch(MKINITCPIO, conf.replace(hooksLine, next));
    say(`HOOKS: ${next.replace(/^HOOKS=/, "").trim()}`);
  }

  say("rebuilding initramfs");
  await inArch("mkinitcpio", "-P");
  say("initramfs rebuilt");

  await writeArch(
    "/etc/systemd/system/systemd-suspend.service.d/10-suspend-is-hibernate.conf",
    `# Any caller that asks to suspend gets a hibernation instead.
# AllowSuspend stays enabled so this unit stays reachable.
[Service]
ExecStart=
ExecStart=/usr/lib/systemd/systemd-sleep hibernate
`,
  );
  await writeArch(
    "/usr/lib/systemd/system-sleep/50-hibernate-led",
    await Bun.file(`${import.meta.dir}/files/sleep/50-hibernate-led`).text(),
    0o755,
  );
  say("installed the hibernate LED blinker");

  await writeArch(
    "/etc/systemd/sleep.conf.d/10-hibernate-mode.conf",
    `# Write the image and power off, rather than handing S4 to the firmware.
#
# This machine hangs on the first hibernation attempt: the kernel logs
# "PM: hibernation: hibernation entry" and then nothing, and the next boot
# finds no image at all, so it cold boots. Every progress line that would
# follow — preallocation, "Basic memory bitmaps created", the image write —
# is missing, which puts the hang at the very start of the snapshot.
#
# Platform mode is the one difference between this machine and one where the
# same kernel works: it asks the firmware to do the ACPI S4 handoff, and that
# is the path AMD laptops wedge on. Shutdown mode takes the same snapshot and
# then powers off cleanly; the initramfs loads the image on the next boot, so
# the firmware is never involved. The cost is a slower power-off, which for a
# machine that currently does not hibernate at all is not a cost.
[Sleep]
HibernateMode=shutdown
`,
  );
  say("installed sleep drop-ins");

  await writeArch(
    "/etc/systemd/logind.conf.d/10-hibernate.conf",
    `[Login]
# The generic sleep action resolves to hibernate only.
SleepOperation=hibernate

# Lid close hibernates. No desktop environment holds a lid inhibitor here,
# so this is the only lid policy on the machine.
HandleLidSwitch=hibernate
HandleLidSwitchExternalPower=hibernate
HandleLidSwitchDocked=ignore
HandleSuspendKey=hibernate
HandleHibernateKey=hibernate
`,
  );
  say("installed logind drop-in");

  await writeArch(
    "/etc/tmpfiles.d/hibernation-image-size.conf",
    `# Ask the kernel for maximum image compression. 42 GiB of RAM has to fit
# in the 48 GiB shared swap partition, so headroom matters more than speed.
w /sys/power/image_size - - - - 0
`,
  );
  say("installed image_size tmpfile");
  say(`resume=UUID=${SWAP_UUID} goes on the cmdline; 150-kernel-sync.ts writes it`);
}

async function down(): Promise<void> {
  await needMount();

  say(
    (await restoreBackup(MKINITCPIO, ".hib-save"))
      ? "mkinitcpio.conf restored"
      : "no mkinitcpio backup; resume hook left in place",
  );

  for (const rel of [
    "/etc/systemd/system/systemd-suspend.service.d/10-suspend-is-hibernate.conf",
    "/usr/lib/systemd/system-sleep/50-hibernate-led",
    "/etc/systemd/sleep.conf.d/10-hibernate-mode.conf",
    "/etc/systemd/logind.conf.d/10-hibernate.conf",
    "/etc/tmpfiles.d/hibernation-image-size.conf",
  ]) {
    await removeArch(rel);
  }
  say("removed helpers and drop-ins; rebuilding initramfs");

  const rebuild = await inArchSoft("mkinitcpio", "-P");
  say(rebuild.exitCode === 0 ? "initramfs rebuilt without resume" : "mkinitcpio failed; rebuild by hand");
}

async function verify(): Promise<void> {
  const hooks = (await readArch("/etc/mkinitcpio.conf")) ?? "";
  /\bresume\b/.test(hooks) ? ok("HOOKS include resume") : fail("HOOKS lack resume; the image will not be restored");

  const suspend = (await readArch("/etc/systemd/system/systemd-suspend.service.d/10-suspend-is-hibernate.conf")) ?? "";
  /^ExecStart=$/m.test(suspend)
    ? ok("suspend clears the packaged ExecStart")
    : fail("suspend drop-in will run suspend and hibernate");
  suspend.includes("systemd-sleep hibernate")
    ? ok("suspend redirects to hibernate") : fail("suspend does not redirect to hibernate");

  ((await readArch("/etc/systemd/sleep.conf.d/10-hibernate-mode.conf")) ?? "").includes("HibernateMode=shutdown")
    ? ok("HibernateMode=shutdown") : fail("HibernateMode is not shutdown");

  ((await readArch("/etc/systemd/logind.conf.d/10-hibernate.conf")) ?? "").includes("HandleLidSwitch=hibernate")
    ? ok("lid close hibernates") : fail("lid close does not hibernate");

  const mask = await inArchSoft("grep", "-rls", "hibernate-wakeup-mask", "/etc/systemd/system");
  mask.exitCode === 0 ? fail("a drop-in still runs the wake-source mask") : ok("no wake-source mask");

  (await existsInArch("/usr/lib/systemd/system-sleep/50-hibernate-led"))
    ? ok("hibernate LED hook installed") : fail("hibernate LED hook missing");
}

await main({ up, down, verify });
