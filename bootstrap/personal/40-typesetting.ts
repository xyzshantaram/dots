/**
 * ---
 * script: 40-typesetting.ts
 * desc: Installs Typst, its language service, and fonttools: documents and fonts.
 * needs: 40-packages.ts up in the main ladder, and network
 * up: pacman -S --needed typst tinymist python-fonttools
 * down: pacman -Rns over the same three, ignoring failures
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
 *
 * fonttools is the other half of working with fonts rather than with documents:
 * it reads a font's tables, which is the only way to ask what a glyph is
 * *called* rather than which codepoint it sits at. Everything on this desktop's
 * bar is a glyph chosen by name, so that question comes up.
 */
import process from "node:process";
import { inArch, main, needMount, say } from "../lib.ts";

const PACMAN = ["typst", "tinymist", "python-fonttools"];

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
