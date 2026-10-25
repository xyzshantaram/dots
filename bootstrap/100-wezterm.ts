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
 * The config's background is the desktop's. wallpaper-random picks an image at
 * session start and records it in $XDG_RUNTIME_DIR/current-wallpaper;
 * WezTerm reads that file when a window is created, so the two cannot show
 * different images and an open window keeps the one it started with.
 *
 * Nothing here vendors an image. With no state file — outside a niri session,
 * or on a machine whose wallpapers have not been supplied — there is no
 * background at all, which is the right failure.
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
  say("background: whatever swaybg is showing ($XDG_RUNTIME_DIR/current-wallpaper)");
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
