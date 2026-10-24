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
import { LIVE, ROOT_MNT, fail, inArch, main, needMount, ok, say } from "./lib.ts";

async function up(): Promise<void> {
  await needMount();
  const args = process.argv.slice(3);

  if (args.length > 0) {
    process.exit(await inArch(...args).nothrow().then((r) => r.exitCode));
  }

  if (LIVE) {
    // TARGET is this system, so the shell the caller already has is the shell
    // this would open. inArch() above is how to run one command either way.
    say("target is the running system; there is no chroot to enter");
    return;
  }

  say(`entering ${ROOT_MNT}; exit to return`);
  const shell = await $`arch-chroot ${ROOT_MNT} /usr/bin/env -i HOME=/root TERM=${process.env.TERM ?? "linux"} /bin/bash`
    .nothrow();
  process.exit(shell.exitCode);
}

async function down(): Promise<void> {
  say("interactive helper, nothing to undo");
}

async function verify(): Promise<void> {
  const r = await inArch("pacman", "-V").quiet().nothrow();
  r.exitCode === 0 ? ok("pacman answers inside the target") : fail("pacman does not run inside the target");
}

await main({ up, down, verify });
