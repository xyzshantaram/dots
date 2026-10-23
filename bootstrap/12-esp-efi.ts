/**
 * ---
 * script: 12-esp-efi.ts
 * desc: Moves the ESP mountpoint from /boot/efi to /efi in the target's fstab.
 * needs: 10-mount.ts up
 * up: rewrites the ESP fstab line to ESP_MOUNT, creates the directory, remounts
 * down: rewrites the fstab line back to /boot/efi and remounts there
 * revisit: 2026-12-21
 * ---
 *
 * This install put the ESP at /boot/efi, which ArchWiki calls "historical and
 * now discouraged"; /efi is the recommended replacement. Every later step
 * writes to $ESP_MOUNT, so this runs early.
 *
 * The rewrite is line-based on the ESP UUID rather than a full fstab
 * regeneration: genfstab would reorder and re-add every other entry, and this
 * step should touch exactly one line.
 */
import { $ } from "bun";
import process from "node:process";
import {
  ESP_MOUNT, ESP_UUID, at, isMounted, main, needMount, readArch, say,
  writeArch,
} from "./lib.ts";

const FSTAB = "/etc/fstab";
const OLD_MOUNT = "/boot/efi";

/** The mountpoint the ESP currently has in fstab, or null when there is no line. */
async function espLine(): Promise<string | null> {
  const fstab = await readArch(FSTAB);
  if (fstab === null) return null;
  for (const line of fstab.split("\n")) {
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith("#")) continue;
    const fields = trimmed.split(/\s+/);
    if (fields.length < 2) continue;
    const [source, mountpoint] = fields;
    if (source === `UUID=${ESP_UUID}` || source === `/dev/disk/by-uuid/${ESP_UUID}`) {
      return mountpoint;
    }
  }
  return null;
}

/** Points the ESP fstab line at `target`, leaving every other line alone. */
async function setMountpoint(target: string): Promise<boolean> {
  const fstab = await readArch(FSTAB);
  if (fstab === null) {
    say(`${FSTAB} missing`);
    process.exit(1);
  }

  let touched = false;
  const lines = fstab.split("\n").map((line) => {
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith("#")) return line;
    const fields = trimmed.split(/\s+/);
    if (fields.length < 2) return line;
    const [source, mountpoint] = fields;
    if (source !== `UUID=${ESP_UUID}` && source !== `/dev/disk/by-uuid/${ESP_UUID}`) {
      return line;
    }
    if (mountpoint === target) return line;
    say(`fstab: ${mountpoint} -> ${target}`);
    fields[1] = target;
    touched = true;
    return fields.join("\t");
  });

  if (touched) await writeArch(FSTAB, lines.join("\n"));
  return touched;
}

async function up(): Promise<void> {
  await needMount();

  const current = await espLine();
  if (current === null) {
    say(`no fstab line with UUID=${ESP_UUID}; nothing to change`);
    say("10-mount.ts mounted the ESP at the .env value, which is where it stays");
    return;
  }
  if (current === ESP_MOUNT) {
    say(`fstab already points the ESP at ${ESP_MOUNT}`);
    return;
  }

  // Remount at the new place so the rest of the ladder finds it there.
  const oldAt = at(current);
  const newAt = at(ESP_MOUNT);

  await setMountpoint(ESP_MOUNT);
  await $`mkdir -p ${newAt}`;
  if (await isMounted(oldAt)) {
    await $`umount ${oldAt}`;
    say(`unmounted ${current}`);
  }
  if (!(await isMounted(newAt))) {
    await $`mount /dev/disk/by-uuid/${ESP_UUID} ${newAt}`;
    say(`mounted at ${ESP_MOUNT}`);
  }
  say(`esp is now at ${ESP_MOUNT}; loader entries keep working`);
  say(`left behind: ${current} is an empty directory, which is harmless`);
}

async function down(): Promise<void> {
  await needMount();

  const oldAt = at(OLD_MOUNT);
  const newAt = at(ESP_MOUNT);

  await setMountpoint(OLD_MOUNT);
  await $`mkdir -p ${oldAt}`;

  if (await isMounted(newAt)) {
    await $`umount ${newAt}`;
    say(`unmounted ${ESP_MOUNT}`);
  }
  if (!(await isMounted(oldAt))) {
    await $`mount /dev/disk/by-uuid/${ESP_UUID} ${oldAt}`;
    say(`mounted back at ${OLD_MOUNT}`);
  }
}

await main({ up, down });
