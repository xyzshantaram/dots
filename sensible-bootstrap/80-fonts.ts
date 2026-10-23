/**
 * ---
 * script: 80-fonts.ts
 * desc: Installs the vendored CMU Serif fonts, rebuilds the font cache, and checks the families niri and wezterm ask for.
 * needs: 40-packages.ts up
 * up: copies files/fonts/cmu/*.otf into /usr/local/share/fonts/cmu, writes the emoji fallback drop-in, fc-cache -f, verifies families
 * down: removes the CMU directory and the fontconfig drop-in, re-runs fc-cache
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
  ROOT_MNT, main, needMount, removeArch, say, writeArch,
} from "./lib.ts";

const VENDORED = `${import.meta.dir}/files/fonts/cmu`;
const CMU_DEST = "/usr/local/share/fonts/cmu";
const EMOJI_CONF = "/etc/fonts/conf.d/99-noto-emoji-fallback.conf";

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
  ["Inter", "UI text for quickshell"],
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

  await $`mkdir -p ${ROOT_MNT}${CMU_DEST}`;
  const copied = await $`cp -aL ${VENDORED}/. ${ROOT_MNT}${CMU_DEST}/`.nothrow();
  if (copied.exitCode !== 0) {
    say("copying the CMU fonts failed");
    process.stderr.write(copied.stderr.toString());
    return false;
  }

  const landed = await countFonts(`${ROOT_MNT}${CMU_DEST}`);
  const links = await $`find ${ROOT_MNT}${CMU_DEST} -type l`.quiet();
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
     render in Firefox and GTK apps instead of tofu. Installed by sensible-bootstrap. -->
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

  await inArchFcCache();
  say("font cache rebuilt");

  let missing = 0;
  for (const [family, purpose] of REQUIRED) {
    const found = await $`arch-chroot ${ROOT_MNT} fc-match -f %{family} ${family}`
      .nothrow().quiet();
    const match = found.stdout.toString().trim();
    if (found.exitCode === 0 && match.toLowerCase().includes(family.toLowerCase())) {
      say(`  ok    ${family}`);
    } else {
      say(`  MISS  ${family} (${purpose}) - fc-match returned '${match}'`);
      missing++;
    }
  }

  // Reported separately: only the dictation strip asks for CMU Serif.
  const cmu = await $`arch-chroot ${ROOT_MNT} fc-match -f %{family} "CMU Serif"`
    .nothrow().quiet();
  const cmuMatch = cmu.stdout.toString().trim();
  say(
    cmuMatch.toLowerCase().includes("cmu")
      ? "  ok    CMU Serif"
      : `  note  CMU Serif does not resolve (got '${cmuMatch}')`,
  );

  if (missing > 0) {
    say(`${missing} family/families unresolved; icons and UI text may fall back`);
    process.exit(1);
  }
  say("all required font families resolve");
}

async function inArchFcCache(): Promise<void> {
  await $`arch-chroot ${ROOT_MNT} fc-cache -f`;
}

async function down(): Promise<void> {
  await needMount();
  await removeArch(CMU_DEST);
  await removeArch(EMOJI_CONF);
  await inArchFcCache();
  say("removed CMU fonts and the emoji fallback; cache rebuilt");
}

await main({ up, down });
