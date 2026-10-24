/**
 * ---
 * script: 150-kernel-sync.ts
 * desc: Writes the Arch boot entry and keeps the ESP copies of kernel and initramfs current on every kernel update.
 * needs: 10-mount.ts up, 145-hibernate.ts up, KERNEL in .env
 * up: installs esp-sync and its pacman hook, writes arch.conf with resume=, runs the first sync
 * down: removes the entry, the hook, the script, and the ESP copies it made
 * revisit: 2026-12-21
 * ---
 *
 * The hook fires on usr/lib/modules/<version>/vmlinuz at PostTransaction,
 * after 90-mkinitcpio-install.hook has rebuilt the initramfs.
 */
import process from "node:process";
import {
  ARCH_UUID, ESP_MOUNT, KERNEL, SWAP_UUID, at, backupOnce, existsInArch,
  inArchSoft, main, needMount, readArch, removeArch, restoreBackup, say,
  writeArch,
} from "./lib.ts";

const CURRENT = "/EFI/arch/current";
const PREVIOUS = "/EFI/arch/previous";

const ARCH_CONF = `${ESP_MOUNT}/loader/entries/arch.conf`;
const KNOWN_GOOD = `${ESP_MOUNT}/loader/entries/arch-known-good.conf`;

/** Kernel arguments carried over from the Fedora side. */
const ARGS = [
  `root=UUID=${ARCH_UUID}`,
  "rootflags=subvol=@",
  "rw",
  "quiet",
  `resume=UUID=${SWAP_UUID}`,
  "amdgpu.ip_block_mask=0xfffff7ff",
  "amdgpu.cwsr_enable=0",
];

/**
 * No amd-ucode.img initrd line. Microcode is embedded into the main initramfs
 * by the `microcode` hook, which HOOKS lists by default on Arch, and which this
 * machine already has. The separate /boot/amd-ucode.img belongs to the older
 * arrangement where it had to be named as its own initrd before the main one;
 * it is not generated here at all, so naming it would point an entry at a file
 * that does not exist. ArchWiki, Microcode.
 */
function entry(title: string, dir: string): string {
  return `title   ${title}
linux   \\EFI\\arch\\${dir}\\vmlinuz-${KERNEL}
initrd  \\EFI\\arch\\${dir}\\initramfs-${KERNEL}.img
options ${ARGS.join(" ")}
`;
}

async function up(): Promise<void> {
  await needMount();

  // Every path referenced by the entries below has to exist first, and not for
  // the reason this comment used to give. systemd-boot assembles its menu from
  // loader/entries and does not check that the files are there (systemd-boot(7)
  // lists where entries come from, not any validation of them), so a missing
  // file does not hide the entry - it produces an entry that fails when it is
  // chosen. Worse than absent, because it reads as a fallback.
  const required = [
    `/boot/vmlinuz-${KERNEL}`,
    `/boot/initramfs-${KERNEL}.img`,
  ];
  const absent: string[] = [];
  for (const rel of required) {
    if (!(await existsInArch(rel))) absent.push(rel);
  }
  if (absent.length > 0) {
    say(`missing inside the target: ${absent.join(" ")}`);
    say(`install them first: 40-packages.ts up (needs ${KERNEL})`);
    say("refusing to write boot entries that point at absent files");
    process.exit(1);
  }

  // Microcode travels inside the initramfs rather than beside it, so verify it
  // actually got there instead of checking for a file that no longer exists.
  // ArchWiki's own method. Not fatal: a machine without early microcode still
  // boots, it just misses the updates.
  const early = await inArchSoft("lsinitcpio", "--early", `/boot/initramfs-${KERNEL}.img`);
  if (early.exitCode === 0 && /microcode/i.test(early.stdout.toString())) {
    say("initramfs carries microcode (early CPIO)");
  } else {
    say("warning: no microcode found inside the initramfs");
    say("check that `microcode` is in HOOKS, then rebuild: 145-hibernate.ts up does it");
  }

  await writeArch(
    "/usr/local/bin/esp-sync",
    await Bun.file(`${import.meta.dir}/files/esp/esp-sync`).text(),
    0o755,
  );
  await writeArch(
    "/usr/share/libalpm/hooks/99-esp-kernel-sync.hook",
    await Bun.file(`${import.meta.dir}/files/esp/99-esp-kernel-sync.hook`).text(),
  );
  say("installed esp-sync and the pacman hook");

  await backupOnce(ARCH_CONF, ".pre-esp-sync");

  await writeArch(ARCH_CONF, entry("Arch Linux", "current"));
  say(`wrote ${ARCH_CONF}`);
  say(`cmdline: ${ARGS.join(" ")}`);

  const sync = await inArchSoft("env", `KERNEL=${KERNEL}`, "/usr/local/bin/esp-sync");
  process.stdout.write(sync.stdout.toString());
  process.stderr.write(sync.stderr.toString());
  if (sync.exitCode !== 0) {
    say("first sync failed");
    process.exit(1);
  }

  const status = await inArchSoft("env", `KERNEL=${KERNEL}`, "/usr/local/bin/esp-sync", "--status");
  process.stdout.write(status.stdout.toString());

  const onEsp = await Bun.file(at(`${ESP_MOUNT}${CURRENT}/vmlinuz-${KERNEL}`)).exists();
  say(onEsp ? "verified: current kernel is on the ESP" : "current kernel is NOT on the ESP");
  if (!onEsp) process.exit(1);
}

async function down(): Promise<void> {
  await needMount();

  // The kernels on the ESP are the only bootable artifacts this machine has
  // while the ladder's entries are in place. Removing them can leave nothing
  // to boot, so undo proceeds in the safe order and keeps them unless told
  // otherwise.
  await removeArch(KNOWN_GOOD);
  say("removed arch-known-good.conf");

  const hadBackup = await Bun.file(at(`${ARCH_CONF}.pre-esp-sync`)).exists();
  const restored = await restoreBackup(ARCH_CONF, ".pre-esp-sync");
  if (restored) {
    say("restored the original arch.conf");
  } else if (hadBackup) {
    say("could not restore the original arch.conf; leaving this one in place");
  } else {
    say("no original arch.conf backup: leaving arch.conf in place so the machine still boots");
    say("remove it by hand once you have a working entry");
  }

  await removeArch("/usr/share/libalpm/hooks/99-esp-kernel-sync.hook");
  await removeArch("/usr/local/bin/esp-sync");
  say("removed the hook and esp-sync");

  const wipe = process.env.FORCE_ESP_WIPE === "1";
  if (!wipe) {
    const left = [CURRENT, PREVIOUS]
      .filter((dir) => Bun.file(at(`${ESP_MOUNT}${dir}/vmlinuz-${KERNEL}`)).size > 0)
      .join(" ");
    if (left) {
      say(`kept the ESP kernel copies (${left}); they are still bootable`);
      say("delete them with FORCE_ESP_WIPE=1 bun run 150-kernel-sync.ts down");
    }
    return;
  }

  // Only now, with an explicit opt-in, remove the images.
  const restoredEntry = (await readArch(ARCH_CONF)) ?? "";
  if (restoredEntry.includes("/current/") || restoredEntry.includes("/previous/")) {
    say("the restored arch.conf references these directories; refusing to delete them");
    say("fix arch.conf first, then re-run with FORCE_ESP_WIPE=1");
    process.exit(1);
  }
  await removeArch(CURRENT);
  await removeArch(PREVIOUS);
  say("removed the ESP kernel copies");
}

await main({ up, down });
