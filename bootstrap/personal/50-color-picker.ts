/**
 * ---
 * script: 50-color-picker.ts
 * desc: Installs wl-color-picker from the AUR: pick a colour off the screen instead of guessing at hex.
 * needs: 10-graphics.ts up (imagemagick is one of its runtime dependencies), and network
 * up: builds and installs wl-color-picker through lib.ts's aurInstall
 * down: pacman -Rns wl-color-picker
 * revisit: 2026-12-21
 * ---
 *
 * AUR-only, so it is the second step in this ladder that builds rather than
 * installs. Its runtime dependencies are grim, slurp, zenity, wl-clipboard,
 * libnotify and imagemagick; aurInstall reads them out of .SRCINFO and installs
 * them as root, so naming the package here is enough.
 *
 * It is a script rather than a compiled tool: slurp selects a region, grim
 * captures it, and the colour comes back over the clipboard and a notification.
 * That is why the bar can be designed from a palette picked off the screen.
 */
import process from "node:process";
import { aurInstall, inArchSoft, main, needMount, say } from "../lib.ts";

const PKG = "wl-color-picker";

async function up(): Promise<void> {
  await needMount();

  if ((await inArchSoft("pacman", "-Qq", PKG)).exitCode === 0) {
    say(`${PKG} is already installed`);
    return;
  }

  await aurInstall(PKG);
  say(`installed ${PKG}`);
}

async function down(): Promise<void> {
  await needMount();

  const removed = await inArchSoft("pacman", "-Rns", "--noconfirm", PKG);
  say(removed.exitCode === 0 ? `removed ${PKG}` : `${PKG} was not installed`);
}

await main({ up, down });
