/**
 * ---
 * script: 30-keys.ts
 * desc: Initialises the pacman keyring and refreshes archlinux-keyring.
 * needs: 10-mount.ts up, network
 * up: pacman-key --init, --populate archlinux, then pacman -Sy archlinux-keyring
 * down: nothing; keyring changes are additive and idempotent
 * revisit: 2026-12-21
 * ---
 */
import { existsInArch, inArch, main, needMount, say } from "./lib.ts";

async function up(): Promise<void> {
  await needMount();

  const initialised =
    (await existsInArch("/etc/pacman.d/gnupg/pubring.gpg")) ||
    (await existsInArch("/etc/pacman.d/gnupg/pubring.kbx"));

  if (initialised) {
    say("keyring already initialised");
  } else {
    say("initialising keyring");
    await inArch("pacman-key", "--init");
    await inArch("pacman-key", "--populate", "archlinux");
  }

  say("refreshing archlinux-keyring");
  await inArch("pacman", "-Sy", "--noconfirm", "archlinux-keyring");
  say("done");
}

async function down(): Promise<void> {
  say("keyring changes are idempotent, nothing to undo");
}

await main({ up, down });
