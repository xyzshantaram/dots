/**
 * ---
 * script: 30-office.ts
 * desc: Installs OnlyOffice, the one package in this ladder the repositories do not carry.
 * needs: 40-packages.ts up in the main ladder (base-devel, for makepkg), and network
 * up: builds onlyoffice-bin from the AUR through lib.ts's aurInstall
 * down: pacman -Rns onlyoffice-bin
 * revisit: 2026-12-21
 * ---
 *
 * onlyoffice-bin rather than onlyoffice: the first is the upstream binary
 * build, the second rebuilds the desktop editors from source. Neither is in the
 * repositories, so this is the only step in the artistic ladder that needs the
 * AUR path, and it builds the same way 110-niri.ts does for vicinae.
 */
import process from "node:process";
import { aurInstall, inArchSoft, main, needMount, say } from "../lib.ts";

const PKG = "onlyoffice-bin";

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
