/**
 * ---
 * script: 145-hibernate.ts
 * desc: Makes the Arch side hibernate-only and makes hibernation resume: resume hook in the initramfs, wake-source mask, suspend->hibernate redirect, logind lid handling.
 * needs: 10-mount.ts up, 40-packages.ts up, SWAP_UUID in .env
 * up: adds `resume` to mkinitcpio HOOKS and rebuilds, installs the wake-source mask, sleep and logind drop-ins, and the image_size tmpfile
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
 * The mitigation lives in dualboot-utils/20-hibernate-mark.ts, which labels the
 * hibernated entry and makes it the one-shot boot default. It is a sign, not a
 * lock — see dualboot-utils/README.md.
 *
 * Arch's default HOOKS are busybox-based, so the `resume` hook is required and
 * must follow `udev`. A systemd-hook initramfs would get resume for free.
 */
import { $ } from "bun";
import process from "node:process";
import {
  SWAP_UUID, at, inArch, inArchSoft, main, needMount, readArch, removeArch,
  restoreBackup, say, writeArch,
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
    "/usr/local/bin/hibernate-wakeup-mask",
    await Bun.file(`${import.meta.dir}/files/sleep/hibernate-wakeup-mask`).text(),
    0o755,
  );
  await writeArch(
    "/etc/hibernate-wakeup-mask.list",
    await Bun.file(`${import.meta.dir}/files/sleep/hibernate-wakeup-mask.list`).text(),
  );
  say("installed wake-source mask");

  await writeArch(
    "/etc/systemd/system/systemd-suspend.service.d/10-suspend-is-hibernate.conf",
    `# Any caller that asks to suspend gets a hibernation instead.
# AllowSuspend stays enabled so this unit stays reachable; the wake-source
# mask runs first so a wake event cannot roll the hibernation back.
[Service]
ExecStartPre=/usr/local/bin/hibernate-wakeup-mask
ExecStart=
ExecStart=/usr/lib/systemd/systemd-sleep hibernate
`,
  );
  await writeArch(
    "/etc/systemd/system/systemd-hibernate.service.d/10-wakeup-mask.conf",
    `# Mask the wake sources that abort hibernation during power-off.
[Service]
ExecStartPre=/usr/local/bin/hibernate-wakeup-mask
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
    "/usr/local/bin/hibernate-wakeup-mask",
    "/etc/hibernate-wakeup-mask.list",
    "/etc/systemd/system/systemd-suspend.service.d/10-suspend-is-hibernate.conf",
    "/etc/systemd/system/systemd-hibernate.service.d/10-wakeup-mask.conf",
    "/etc/systemd/logind.conf.d/10-hibernate.conf",
    "/etc/tmpfiles.d/hibernation-image-size.conf",
  ]) {
    await removeArch(rel);
  }
  say("removed helpers and drop-ins; rebuilding initramfs");

  const rebuild = await inArchSoft("mkinitcpio", "-P");
  say(rebuild.exitCode === 0 ? "initramfs rebuilt without resume" : "mkinitcpio failed; rebuild by hand");
}

await main({ up, down });
