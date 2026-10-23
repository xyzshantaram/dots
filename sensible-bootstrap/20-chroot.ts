/**
 * ---
 * script: 20-chroot.ts
 * desc: Thin wrapper around arch-chroot, so every step uses one entry point.
 * needs: 10-mount.ts up
 * up: opens an interactive root shell inside /mnt/arch; with extra arguments runs them instead (bun run 20-chroot.ts up pacman -Q)
 * down: nothing; a chroot leaves no state
 * revisit: 2026-12-21
 * ---
 */
import { $ } from "bun";
import process from "node:process";
import { ROOT_MNT, inArch, main, needMount, say } from "./lib.ts";

async function up(): Promise<void> {
  await needMount();
  const args = process.argv.slice(3);

  if (args.length > 0) {
    process.exit(await inArch(...args).nothrow().then((r) => r.exitCode));
  }

  say(`entering ${ROOT_MNT}; exit to return`);
  const shell = await $`arch-chroot ${ROOT_MNT} /usr/bin/env -i HOME=/root TERM=${process.env.TERM ?? "linux"} /bin/bash`
    .nothrow();
  process.exit(shell.exitCode);
}

async function down(): Promise<void> {
  say("interactive helper, nothing to undo");
}

await main({ up, down });
