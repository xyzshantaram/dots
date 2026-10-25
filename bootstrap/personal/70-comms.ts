/**
 * ---
 * script: 70-comms.ts
 * desc: Installs himalaya, the CLI mail client, and the Discord desktop client.
 * needs: 40-packages.ts up in the main ladder, and network
 * up: pacman -S --needed himalaya discord
 * down: pacman -Rns over both, ignoring failures
 * revisit: 2026-12-21
 * ---
 *
 * himalaya is the mail half: a terminal client, so it works over ssh and in the
 * same session as everything else. It reads every account it is given from
 * ~/.config/himalaya, and some backends keep credentials there — so this step
 * installs the binary and leaves that file to its owner.
 *
 * Discord is the chat half, from the repositories rather than as a flatpak or a
 * repackaging. The native build goes through the same PipeWire and desktop
 * portal paths as the rest of this session, which is the plumbing the sandboxed
 * and wrapped builds spend their time working around.
 */
import process from "node:process";
import { inArch, main, needMount, say } from "../lib.ts";

const PACMAN = ["himalaya", "discord"];

async function up(): Promise<void> {
  await needMount();

  say(`installing ${PACMAN.join(" ")}`);
  const result = await inArch("pacman", "-S", "--needed", "--noconfirm", ...PACMAN).nothrow();
  if (result.exitCode !== 0) {
    say("pacman failed; see above. Re-run this step once fixed.");
    process.exit(result.exitCode);
  }
  say("installed");
}

async function down(): Promise<void> {
  await needMount();

  say("removing installed packages (failures ignored)");
  for (const pkg of PACMAN) {
    await inArch("pacman", "-Rns", "--noconfirm", pkg).nothrow().quiet();
  }
  say("removed; orphans left in place on purpose");
}

await main({ up, down });
