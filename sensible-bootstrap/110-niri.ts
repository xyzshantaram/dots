/**
 * ---
 * script: 110-niri.ts
 * desc: Installs the niri config: wezterm on Mod+T, nwg-drawer on Mod+D, gtklock on Super+Alt+L, the six XF86 keys, swaync and qs at startup, and the Copilot key bound to voxtype.
 * needs: 50-user.ts up, 40-packages.ts up
 * up: writes /home/ARCH_USER/.config/niri/config.kdl and validates it with niri validate
 * down: removes the config
 * revisit: 2026-12-21
 * ---
 */
import process from "node:process";
import {
  ARCH_USER, asUserSoft, main, needMount, removeArch, say, writeUserFile,
} from "./lib.ts";

const DEST = `/home/${ARCH_USER}/.config/niri/config.kdl`;

async function up(): Promise<void> {
  await needMount();
  const content = await Bun.file(`${import.meta.dir}/files/niri/config.kdl`).text();
  await writeUserFile(DEST, content);
  say(`installed ${DEST}`);

  const validate = await asUserSoft("niri", "validate", "-c", DEST);

  if (validate.exitCode !== 0) {
    say("niri rejected the config:");
    process.stderr.write(validate.stderr.toString());
    process.exit(1);
  }
  const out = validate.stdout.toString().trim();
  say(out ? `niri validate: ${out}` : "niri validate: config ok");

  say("binds: Mod+T wezterm / Mod+D nwg-drawer / Super+Alt+L gtklock");
  say("keys: volume mute -5% +5%, mic mute, brightness up/down, Pause -> voxtype");
}

async function down(): Promise<void> {
  await needMount();
  await removeArch(DEST);
  say("removed niri config; niri falls back to its built-in defaults");
}

await main({ up, down });
