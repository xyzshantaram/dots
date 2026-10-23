/**
 * ---
 * script: 20-media.ts
 * desc: Installs the audio and video tools: Audacity and Kdenlive.
 * needs: 40-packages.ts up in the main ladder, and network
 * up: pacman -S --needed audacity kdenlive
 * down: pacman -Rns over both, ignoring failures
 * revisit: 2026-12-21
 * ---
 *
 * Both pull ffmpeg in as a dependency, but ffmpeg is installed by the main
 * ladder on purpose: it is worth having whether or not either of these is here.
 */
import process from "node:process";
import { inArch, main, needMount, say } from "../lib.ts";

const PACMAN = ["audacity", "kdenlive"];

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
