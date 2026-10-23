/**
 * ---
 * script: 10-mount.ts
 * desc: Mounts the Arch btrfs root (subvol @) and the shared ESP at ESP_MOUNT.
 * needs: 00-check.ts up
 * up: p5 subvol=@ noatime compress=zstd:3 -> /mnt/arch, ESP -> /mnt/arch$ESP_MOUNT; a no-op when the target is the running system
 * down: unmounts the ESP, then the root; a no-op when the target is the running system
 * revisit: 2026-12-21
 * ---
 *
 * ESP_MOUNT comes from .env and is /efi, the mountpoint ArchWiki recommends.
 * This install used /boot/efi; 12-esp-efi.ts moves it, and that step runs
 * after this one because it edits the target's fstab.
 *
 * With ROOT_MNT=/ there is no target root to mount — the ladder is writing into
 * the system it is running on — so both verbs return immediately. The `down`
 * guard is the important one: without it, that verb would unmount /.
 */
import { $ } from "bun";
import process from "node:process";
import {
  ARCH_UUID, ESP_MOUNT, ESP_UUID, LIVE, ROOT_MNT, isMounted, main, say,
} from "./lib.ts";

const ESP_AT = `${ROOT_MNT}${ESP_MOUNT}`;

async function up(): Promise<void> {
  if (LIVE) {
    say("target is the running system; there is nothing to mount");
    return;
  }
  if (!(await isMounted(ROOT_MNT))) {
    await $`mkdir -p ${ROOT_MNT}`;
    await $`mount -o subvol=@,noatime,compress=zstd:3 /dev/disk/by-uuid/${ARCH_UUID} ${ROOT_MNT}`;
    say(`root mounted: ${ROOT_MNT}`);
  } else {
    say("root already mounted, leaving as is");
  }

  await $`mkdir -p ${ESP_AT}`;
  if (!(await isMounted(ESP_AT))) {
    await $`mount /dev/disk/by-uuid/${ESP_UUID} ${ESP_AT}`;
  }
  say(`esp mounted: ${ESP_AT}`);

  // findmnt takes one mountpoint at a time. Given two positional arguments it
  // exits 1 and prints nothing at all (util-linux 2.41), which is easy to
  // mistake for the mounts having failed when they are both fine. Ask once per
  // path, and treat a missing entry as a warning rather than a hard failure:
  // the mounts above are what matters, and this line only reports them.
  for (const path of [ROOT_MNT, ESP_AT]) {
    const r = await $`findmnt -rno TARGET,SOURCE,FSTYPE ${path}`.nothrow().quiet();
    const line = r.stdout.toString().trim();
    if (r.exitCode === 0 && line) {
      process.stdout.write(`${line}\n`);
    } else {
      say(`warning: findmnt does not report ${path} as a mountpoint`);
    }
  }
}

async function down(): Promise<void> {
  if (LIVE) {
    // This guard is the one that matters: without it the unmount below would
    // be aimed at /.
    say("target is the running system; there is nothing to unmount");
    return;
  }
  // Snapshots first: a subvolume mounted under the root keeps the root busy,
  // so umount would fail and leave everything mounted.
  for (const path of [
    `${ROOT_MNT}/.snapshots`,
    ESP_AT,
    `${ROOT_MNT}/boot/efi`,
  ]) {
    if (await isMounted(path)) {
      await $`umount ${path}`;
      say(`unmounted ${path}`);
    }
  }
  if (await isMounted(ROOT_MNT)) {
    await $`umount ${ROOT_MNT}`;
    say("root unmounted");
  }
}

await main({ up, down });
