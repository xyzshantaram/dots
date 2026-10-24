/**
 * ---
 * script: 100-wezterm.ts
 * desc: Installs the WezTerm config for the Arch account.
 * needs: 50-user.ts up
 * up: writes /home/ARCH_USER/.config/wezterm/wezterm.lua from files/wezterm/wezterm.lua
 * down: removes it
 * revisit: 2026-12-21
 * ---
 *
 * The config's background image lives in ~/wallpapers, which 112-wallpaper.ts
 * populates and swaybg picks from at random. WezTerm names one image rather
 * than choosing at random, because a terminal background is a deliberate
 * choice and a random one would be noise.
 *
 * Nothing here vendors an image. If ~/wallpapers/Drangarnir.png is absent,
 * wezterm logs a warning and starts with a plain background, which is the right
 * failure for a machine whose wallpapers have not been supplied yet.
 */
import process from "node:process";
import {
  ARCH_USER, existsInArch, fail, main, needMount, ok, removeArch, say, writeUserFile,
} from "./lib.ts";

const DEST = `/home/${ARCH_USER}/.config/wezterm/wezterm.lua`;

async function up(): Promise<void> {
  await needMount();
  const content = await Bun.file(`${import.meta.dir}/files/wezterm/wezterm.lua`).text();
  if (!content.includes("wezterm.config_builder")) {
    say("vendored wezterm.lua does not look like a WezTerm config");
    process.exit(1);
  }
  await writeUserFile(DEST, content);
  say(`installed ${DEST}`);
  // Read the family out of the config rather than repeating it here. A
  // hardcoded copy is how this line came to name a font that does not exist.
  const font = content.match(/wezterm\.font\s+'([^']+)'/)?.[1];
  say(font ? `font: ${font}` : "font: could not read the family from the config");
  say(`background: ~/wallpapers/Drangarnir.png (112-wallpaper.ts installs the directory)`);
}

async function down(): Promise<void> {
  await needMount();
  await removeArch(DEST);
  say("removed wezterm config");
}

async function verify(): Promise<void> {
  const p = `/home/${ARCH_USER}/.config/wezterm/wezterm.lua`;
  (await existsInArch(p)) ? ok("wezterm config present") : fail("wezterm config missing");
}

await main({ up, down, verify });
