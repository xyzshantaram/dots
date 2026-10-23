/**
 * ---
 * script: 40-typesetting.ts
 * desc: Installs Typst and its language service: documents, next to the rest of the creative tools.
 * needs: 40-packages.ts up in the main ladder, and network
 * up: pacman -S --needed typst tinymist
 * down: pacman -Rns over both, ignoring failures
 * revisit: 2026-12-21
 * ---
 *
 * The compiler is enough on its own to build a document from a terminal —
 * `typst compile doc.typ` — so it does not belong behind an editor. tinymist is
 * the language service, which is what an editor needs for completions and live
 * preview; with the software-dev ladder installed, that is what Zed talks to.
 *
 * typstyle, the formatter, is in the repositories too and is a one-word
 * addition below if it is wanted.
 */
import process from "node:process";
import { inArch, main, needMount, say } from "../lib.ts";

const PACMAN = ["typst", "tinymist"];

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
