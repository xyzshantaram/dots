/**
 * ---
 * script: 111-kanshi.ts
 * desc: Installs the kanshi output profiles: the Acer to the left of the laptop panel, matched by monitor identity so the dock's connector name cannot move it.
 * needs: 40-packages.ts up (kanshi), 110-niri.ts up (config.kdl), 50-user.ts up
 * up: writes /home/ARCH_USER/.config/kanshi/config and adds one spawn-at-startup line to the niri config
 * down: removes that config and that one line
 * revisit: 2026-12-21
 * ---
 *
 * niri can place outputs itself, but only by connector name, and the Acer's
 * connector changes with the path it takes: DP-1 when it is plugged in
 * directly, DP-2 through the USB-C dock. kanshi matches on make, model and
 * serial instead, so the arrangement follows the monitor rather than the port.
 *
 * It runs from the niri session, not from a systemd user unit: it is a Wayland
 * client listening to wlr-output-management, which niri implements, and the
 * session is where that socket is. spawn-at-startup is the same arrangement
 * udiskie and the wallpaper use.
 *
 * The numbers are the ones niri's output block used to carry — the Acer at
 * scale 1.05 and the panel at 1.10, with the panel 1829 to the right because
 * 1920 / 1.05 is the Acer's logical width. The second, single-output profile
 * is what applies when the Acer is not connected; kanshi matches a profile only
 * when its output count equals the connected count, so the two cannot both
 * match.
 */
import process from "node:process";
import {
  ARCH_USER, asUserSoft, existsInArch, fail, main, needMount, ok, readArch, removeArch,
  say, writeUserFile,
} from "./lib.ts";

const NIRI = `/home/${ARCH_USER}/.config/niri/config.kdl`;
const CONFIG = `/home/${ARCH_USER}/.config/kanshi/config`;

/** One line, so undo can remove exactly what it added. */
const SPAWN = 'spawn-at-startup "kanshi"';

async function up(): Promise<void> {
  await needMount();

  if (!(await existsInArch("/usr/bin/kanshi"))) {
    say("kanshi is not installed; 40-packages.ts up installs it");
    process.exit(1);
  }

  await writeUserFile(CONFIG, await Bun.file(`${import.meta.dir}/files/kanshi/config`).text());
  say(`wrote ${CONFIG}`);

  const config = await readArch(NIRI);
  if (config === null) {
    say(`${NIRI} is missing; run 110-niri.ts up first`);
    process.exit(1);
  }
  if (config.split("\n").some((l) => l.trim() === SPAWN)) {
    say("niri already starts kanshi");
  } else {
    await writeUserFile(NIRI, `${config}${config.endsWith("\n") ? "" : "\n"}${SPAWN}\n`);
    say("added the kanshi line to the niri config");
  }

  const validate = await asUserSoft("niri", "validate", "-c", NIRI);
  if (validate.exitCode !== 0) {
    say("niri rejected the config after this change");
    process.stderr.write(validate.stderr.toString());
    process.exit(1);
  }
  say("niri validate: config ok");
  say("docked: Acer left at 1.05, panel right at 1.10; alone: panel at 0,0");
}

async function down(): Promise<void> {
  await needMount();

  const config = await readArch(NIRI);
  if (config !== null) {
    const kept = config.split("\n").filter((l) => l.trim() !== SPAWN);
    await writeUserFile(NIRI, kept.join("\n"));
    say("removed the kanshi line from the niri config");
  }

  await removeArch(CONFIG);
  say(`removed ${CONFIG}`);
  say("niri places outputs on its own again");
}

async function verify(): Promise<void> {
  (await existsInArch("/usr/bin/kanshi")) ? ok("kanshi installed") : fail("kanshi missing");
  (await readArch(CONFIG)) !== null ? ok("kanshi config present") : fail("kanshi config missing");
  const niri = (await readArch(NIRI)) ?? "";
  niri.includes(SPAWN) ? ok("niri starts kanshi") : fail("niri does not start kanshi");
}

await main({ up, down, verify });
