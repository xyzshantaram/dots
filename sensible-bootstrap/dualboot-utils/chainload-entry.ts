/**
 * ---
 * script: chainload-entry.ts
 * desc: Adds a boot-menu entry for another installed OS by chainloading its own EFI binary.
 * needs: ../10-mount.ts up, ../12-esp-efi.ts up
 * up: finds the other OS's EFI binary on the ESP and writes a loader entry
 * down: removes the entry
 * revisit: 2026-12-21
 * ---
 *
 * Chainloading costs no ESP space and leaves the other OS owning its own
 * kernels. Copying its kernel and initramfs onto the ESP would duplicate tens
 * of MiB per kernel and drift on every one of its updates.
 *
 * Nothing here is installed by default: this step is skipped entirely when the
 * other OS's EFI directory is absent, so a single-boot machine sees no error.
 * Set DRAWER_OS_LABEL to change how the entry is titled.
 */
import { $ } from "bun";
import process from "node:process";
import {
  ESP_MOUNT, ROOT_MNT, main, needMount, opt, removeArch, say, writeArch,
} from "../lib.ts";

const ESP = `${ROOT_MNT}${ESP_MOUNT}`;

/** Where the other OS keeps its bootloader on the ESP. */
const EFI_DIR = opt("OTHER_OS_EFI_DIR") ?? "fedora";

const ENTRY = `${ESP_MOUNT}/loader/entries/${EFI_DIR}.conf`;

/** Secure Boot installs shim; without it, grub is loaded directly. */
const CANDIDATES = [
  `EFI/${EFI_DIR}/shimx64.efi`,
  `EFI/${EFI_DIR}/grubx64.efi`,
  `EFI/${EFI_DIR}/shimx64-${EFI_DIR}.efi`,
];

async function up(): Promise<void> {
  await needMount();

  const found: string[] = [];
  for (const rel of CANDIDATES) {
    if ((await $`test -f ${`${ESP}/${rel}`}`.nothrow().quiet()).exitCode === 0) {
      found.push(rel);
    }
  }

  if (found.length === 0) {
    say(`no EFI binary for '${EFI_DIR}' on the ESP; nothing to chainload`);
    const listing = await $`ls ${`${ESP}/EFI`}`.nothrow().quiet();
    if (listing.exitCode === 0) {
      say(`ESP EFI directories: ${listing.stdout.toString().trim().split("\n").join(" ")}`);
    }
    say("single-boot machine, or set OTHER_OS_EFI_DIR in .env — skipping");
    return;
  }

  const title = opt("OTHER_OS_LABEL") ?? EFI_DIR.charAt(0).toUpperCase() + EFI_DIR.slice(1);
  const efiPath = `\\${found[0].split("/").join("\\")}`;
  await writeArch(ENTRY, `title   ${title}\nlinux   ${efiPath}\n`);
  say(`chainloading ${efiPath}`);
  say(`wrote ${ENTRY}`);
  say("the other OS keeps managing its own kernels; nothing was copied");
}

async function down(): Promise<void> {
  await needMount();
  await removeArch(ENTRY);
  say(`removed ${ENTRY}`);
}

await main({ up, down });
