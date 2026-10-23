/**
 * ---
 * script: 10-graphics.ts
 * desc: Installs the image and vector tools: ImageMagick, GIMP and Inkscape.
 * needs: 40-packages.ts up in the main ladder, and network
 * up: pacman -S --needed imagemagick gimp inkscape
 * down: pacman -Rns over the same three, ignoring failures
 * revisit: 2026-12-21
 * ---
 *
 * ImageMagick is the one here that is not only a GUI application: `magick`
 * converts, resizes and reports on an image from a script, which is what makes
 * it useful to a ladder or an agent rather than only to a person.
 */
import process from "node:process";
import { inArch, main, needMount, say } from "../lib.ts";

const PACMAN = ["imagemagick", "gimp", "inkscape"];

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
