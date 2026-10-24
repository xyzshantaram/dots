/**
 * ---
 * script: 20-media.ts
 * desc: Installs the audio and video tools: Audacity, Kdenlive, and qBittorrent.
 * needs: 40-packages.ts up in the main ladder, and network
 * up: pacman -S --needed audacity kdenlive qbittorrent
 * down: pacman -Rns over all three, ignoring failures
 * revisit: 2026-12-21
 * ---
 *
 * Both editors pull ffmpeg in as a dependency, but ffmpeg is installed by the
 * main ladder on purpose: it is worth having whether or not either of these is
 * here.
 *
 * qbittorrent is not an editor, but it is where the material these two work on
 * comes from, so it rides with them rather than sitting in a rung of its own.
 */
import process from "node:process";
import { inArch, main, needMount, say } from "../lib.ts";

const PACMAN = ["audacity", "kdenlive", "qbittorrent"];

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
