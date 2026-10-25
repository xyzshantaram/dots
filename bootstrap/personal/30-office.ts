/**
 * ---
 * script: 30-office.ts
 * desc: Installs the office suites: LibreOffice from the repositories, and OnlyOffice from the AUR.
 * needs: 40-packages.ts up in the main ladder (base-devel, for makepkg), and network
 * up: pacman -S libreoffice-fresh, then builds onlyoffice-bin from the AUR through lib.ts's aurInstall
 * down: pacman -Rns over both
 * revisit: 2026-12-21
 * ---
 *
 * LibreOffice is the default suite: it is in the repositories, so it installs
 * without a build, and its import and export filters are what a document that
 * arrives from elsewhere is most likely to need. `libreoffice-fresh` is the
 * current branch; `libreoffice-still` is the previous release under the same
 * name, and the two conflict, so this names the one it means.
 *
 * onlyoffice-bin rather than onlyoffice: the first is the upstream binary
 * build, the second rebuilds the desktop editors from source. Neither is in the
 * repositories, so OnlyOffice still goes through the AUR path, the same way
 * 110-niri.ts does for vicinae.
 */
import process from "node:process";
import { aurInstall, inArch, inArchSoft, main, needMount, say } from "../lib.ts";

const PACMAN = ["libreoffice-fresh"];
const AUR = "onlyoffice-bin";

async function up(): Promise<void> {
  await needMount();

  say(`installing ${PACMAN.join(" ")}`);
  const result = await inArch("pacman", "-S", "--needed", "--noconfirm", ...PACMAN).nothrow();
  if (result.exitCode !== 0) {
    say("pacman failed; see above. Re-run this step once fixed.");
    process.exit(result.exitCode);
  }

  if ((await inArchSoft("pacman", "-Qq", AUR)).exitCode === 0) {
    say(`${AUR} is already installed`);
    return;
  }

  await aurInstall(AUR);
  say(`installed ${PACMAN.join(" ")} and ${AUR}`);
}

async function down(): Promise<void> {
  await needMount();

  for (const pkg of [AUR, ...PACMAN]) {
    const removed = await inArchSoft("pacman", "-Rns", "--noconfirm", pkg);
    say(removed.exitCode === 0 ? `removed ${pkg}` : `${pkg} was not installed`);
  }
}

await main({ up, down });
