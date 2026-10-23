/**
 * ---
 * script: 80-fonts.ts
 * desc: Installs the vendored CMU Serif fonts, makes Inter the default sans-serif with Noto behind it, turns on full hinting, rebuilds the font cache, and checks the families niri and wezterm ask for.
 * needs: 40-packages.ts up
 * up: copies files/fonts/cmu/*.otf into /usr/local/share/fonts/cmu, writes the emoji, Inter and hinting drop-ins, fc-cache -f, verifies families
 * down: removes the CMU directory and the fontconfig drop-ins, re-runs fc-cache
 * revisit: 2026-12-21
 * ---
 *
 * CMU is vendored in files/fonts/cmu (OFL-1.1, from texlive-cm-unicode).
 * There is deliberately no fallback to another OS: this ladder builds a system
 * from the install guide plus this repo, and depending on a neighbouring
 * install would break that. An empty directory warns and carries on, because
 * only the dictation strip asks for CMU Serif.
 */
import { $ } from "bun";
import process from "node:process";
import {
  at, inArch, inArchSoft, main, needMount, removeArch, say, writeArch,
} from "./lib.ts";

const VENDORED = `${import.meta.dir}/files/fonts/cmu`;
const CMU_DEST = "/usr/local/share/fonts/cmu";

/**
 * Fontconfig drop-ins, in /etc/fonts/conf.d so they load after the shipped
 * rules (60-latin.conf and friends).
 *
 * The emoji one is numbered 98 rather than 99 on purpose. Its sans-serif alias
 * makes Noto Color Emoji a candidate, and if this file loaded after
 * 99-inter-sans.conf that alias could outrank Inter — which is exactly the
 * state this machine arrived in, with `fc-match sans-serif` answering with an
 * emoji font. Loading Inter last settles it.
 */
const EMOJI_CONF = "/etc/fonts/conf.d/98-noto-emoji-fallback.conf";
const INTER_CONF = "/etc/fonts/conf.d/99-inter-sans.conf";
const HINTING_CONF = "/etc/fonts/conf.d/99-hinting-full.conf";

/**
 * Families that must resolve, and why.
 *
 * The Fantasque family is `FantasqueSansM Nerd Font Mono`, and the odd spelling
 * is the real one: Nerd Fonts 3.x names these `FantasqueSansM Nerd Font`,
 * `... Mono` and `... Propo`. There is no `FantasqueSansMono Nerd Font`, which
 * is what this list and the configs used to ask for, so fontconfig quietly
 * substituted a default and the terminal never used the font at all. Confirmed
 * with `fc-query` against the files shipped by ttf-fantasque-nerd 3.5.1.
 *
 * `Mono` rather than the bare name: it forces every glyph, the icon range
 * included, onto the single-cell grid, which is what keeps a terminal's columns
 * aligned. The `Propo` variant spaces icons proportionally and is for text that
 * is not a grid.
 */
const REQUIRED: [string, string][] = [
  ["FantasqueSansM Nerd Font Mono", "wezterm, the fish prompt and quickshell"],
  ["Inter", "the default sans-serif, and UI text for quickshell"],
  ["Noto Sans", "CJK and non-Latin fallback"],
  ["Noto Color Emoji", "emoji fallback"],
];

async function countFonts(dir: string): Promise<number> {
  const listing = await $`ls ${dir}`.nothrow().quiet();
  if (listing.exitCode !== 0) return 0;
  return listing.stdout
    .toString()
    .trim()
    .split("\n")
    .filter((f) => /\.(otf|ttf)$/i.test(f)).length;
}

async function installCmu(): Promise<boolean> {
  const count = await countFonts(VENDORED);
  if (count === 0) {
    say(`no .otf/.ttf in files/fonts/cmu`);
    return false;
  }

  await $`mkdir -p ${at(CMU_DEST)}`;
  const copied = await $`cp -aL ${VENDORED}/. ${at(CMU_DEST)}/`.nothrow();
  if (copied.exitCode !== 0) {
    say("copying the CMU fonts failed");
    process.stderr.write(copied.stderr.toString());
    return false;
  }

  const landed = await countFonts(at(CMU_DEST));
  const links = await $`find ${at(CMU_DEST)} -type l`.quiet();
  if (links.stdout.toString().trim() !== "") {
    say("warning: symlinks survived the copy; some fonts may be dangling");
  }
  say(`installed ${landed} CMU files into ${CMU_DEST}`);
  return landed > 0;
}

async function up(): Promise<void> {
  await needMount();

  if (!(await installCmu())) {
    say("no CMU source available; the dictation strip will use another serif");
  }

  await writeArch(
    EMOJI_CONF,
    `<?xml version="1.0"?>
<!DOCTYPE fontconfig SYSTEM "urn:fontconfig:fonts.dtd">
<!-- Prefer Noto Color Emoji over any monochrome emoji font, so colour emoji
     render in Firefox and GTK apps instead of tofu. Installed by bootstrap. -->
<fontconfig>
  <alias>
    <family>emoji</family>
    <prefer><family>Noto Color Emoji</family></prefer>
  </alias>
  <alias binding="same">
    <family>sans-serif</family>
    <accept><family>Noto Color Emoji</family></accept>
  </alias>
</fontconfig>
`,
  );
  say(`installed ${EMOJI_CONF}`);

  await writeArch(
    INTER_CONF,
    `<?xml version="1.0"?>
<!DOCTYPE fontconfig SYSTEM "urn:fontconfig:fonts.dtd">
<!-- Inter is the default sans-serif. The Noto families stay in the list behind
     it, so characters Inter has no glyph for (CJK and the rest) still resolve.
     Loads last, so the emoji alias in 98-noto-emoji-fallback.conf cannot
     outrank it. Installed by bootstrap. -->
<fontconfig>
  <match target="pattern">
    <test name="family" qual="any"><string>sans-serif</string></test>
    <edit name="family" mode="prepend" binding="strong"><string>Inter</string></edit>
  </match>
</fontconfig>
`,
  );
  say(`installed ${INTER_CONF}`);

  await writeArch(
    HINTING_CONF,
    `<?xml version="1.0"?>
<!DOCTYPE fontconfig SYSTEM "urn:fontconfig:fonts.dtd">
<!-- Full hinting, overriding the shipped 10-hinting-slight.conf. Installed by
     bootstrap. -->
<fontconfig>
  <match target="font">
    <edit name="hinting" mode="assign"><bool>true</bool></edit>
    <edit name="hintstyle" mode="assign"><const>hintfull</const></edit>
  </match>
</fontconfig>
`,
  );
  say(`installed ${HINTING_CONF}`);

  await inArchFcCache();
  say("font cache rebuilt");

  let missing = 0;
  for (const [family, purpose] of REQUIRED) {
    const found = await inArchSoft("fc-match", "-f", "%{family}", family);
    const match = found.stdout.toString().trim();
    if (found.exitCode === 0 && match.toLowerCase().includes(family.toLowerCase())) {
      say(`  ok    ${family}`);
    } else {
      say(`  MISS  ${family} (${purpose}) - fc-match returned '${match}'`);
      missing++;
    }
  }

  // Reported separately: only the dictation strip asks for CMU Serif.
  const cmu = await inArchSoft("fc-match", "-f", "%{family}", "CMU Serif");
  const cmuMatch = cmu.stdout.toString().trim();
  say(
    cmuMatch.toLowerCase().includes("cmu")
      ? "  ok    CMU Serif"
      : `  note  CMU Serif does not resolve (got '${cmuMatch}')`,
  );

  // The default sans-serif has to be Inter. Asking for the family by name, as
  // the loop above does, passes on the old setup too — this is the check that
  // catches sans-serif resolving to a Noto face instead.
  const sans = await inArchSoft("fc-match", "-f", "%{family}", "sans-serif");
  const sansFamily = sans.stdout.toString().trim();
  if (sansFamily === "Inter") {
    say("  ok    sans-serif resolves to Inter");
  } else {
    say(`  MISS  sans-serif resolves to '${sansFamily}', not Inter`);
    missing++;
  }

  if (missing > 0) {
    say(`${missing} family/families unresolved; icons and UI text may fall back`);
    process.exit(1);
  }
  say("all required font families resolve");
}

async function inArchFcCache(): Promise<void> {
  await inArch("fc-cache", "-f");
}

async function down(): Promise<void> {
  await needMount();
  await removeArch(CMU_DEST);
  for (const conf of [EMOJI_CONF, INTER_CONF, HINTING_CONF]) await removeArch(conf);
  await inArchFcCache();
  say("removed CMU fonts and the fontconfig drop-ins; cache rebuilt");
}

await main({ up, down });
