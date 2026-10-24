/**
 * ---
 * script: 114-udisks.ts
 * desc: Mounts removable media on insert: udiskie running inside the niri session, so USB drives and cards come up automatically.
 * needs: 110-niri.ts up (config.kdl), 50-user.ts up, 40-packages.ts up (udisks2, udiskie)
 * up: writes ~/.config/udiskie/config.yml and adds one spawn-at-startup line
 * down: removes that config and that one line
 * revisit: 2026-12-21
 * ---
 *
 * udiskie runs from the niri session rather than as a systemd user service, and
 * that is the whole design. ArchWiki, udisks: what a user may do through udisks
 * is decided by polkit, and the stock rules that permit mounting without a
 * password match an *active* user session. A unit started outside the graphical
 * session has no session to match, so every mount is challenged and automounting
 * appears to do nothing at all. niri's spawn-at-startup puts udiskie inside the
 * session logind already knows about.
 *
 * udisks2.service is deliberately not enabled. The daemon is D-Bus activated on
 * first use, which is what the same wiki page recommends; enabling it would
 * start a daemon that the session may never ask anything of.
 *
 * spawn-at-startup rather than an XDG autostart entry for the reason
 * 112-wallpaper.ts and 147-idle.ts already record: niri does not implement the
 * XDG autostart spec, so a .desktop file here would never run.
 *
 * Implied by the polkit arrangement above, and worth knowing when it breaks: if
 * mounts are refused rather than silent, the session was not seen as active, and
 * the fallback is a polkit rule for the `storage` group. udiskie's own wiki
 * carries that rule. Nothing here needs it while the session is active.
 */
import process from "node:process";
import { $ } from "bun";
import {
  ARCH_USER, asUserSoft, existsInArch, fail, main, needMount, ok, readArch, removeArch,
  say, writeUserFile,
} from "./lib.ts";

const NIRI = `/home/${ARCH_USER}/.config/niri/config.kdl`;
const CONFIG = `/home/${ARCH_USER}/.config/udiskie/config.yml`;

/** One line, so undo can remove exactly what it added. */
const SPAWN = 'spawn-at-startup "udiskie"';

async function up(): Promise<void> {
  await needMount();

  if (!(await existsInArch("/usr/bin/udiskie"))) {
    say("udiskie is not installed in the target; 40-packages.ts up installs it");
    process.exit(1);
  }

  const source = await Bun.file(`${import.meta.dir}/files/udiskie/config.yml`).text();
  await writeUserFile(CONFIG, source);
  say(`wrote ${CONFIG}`);

  const config = await readArch(NIRI);
  if (config === null) {
    say(`${NIRI} is missing; run 110-niri.ts up first`);
    process.exit(1);
  }
  if (config.split("\n").some((l) => l.trim() === SPAWN)) {
    say("niri already starts udiskie");
  } else {
    await writeUserFile(NIRI, `${config}${config.endsWith("\n") ? "" : "\n"}${SPAWN}\n`);
    say("added the udiskie line to the niri config");
  }

  const validate = await asUserSoft("niri", "validate", "-c", NIRI);
  if (validate.exitCode !== 0) {
    say("niri rejected the config after this change");
    process.stderr.write(validate.stderr.toString());
    process.exit(1);
  }
  say("niri validate: config ok");
  say("removable media will mount on insert under /run/media/" + ARCH_USER);
  say("unmount with udiskie-umount -a, or -d to power the device down");
}

async function down(): Promise<void> {
  await needMount();

  const config = await readArch(NIRI);
  if (config !== null) {
    const kept = config.split("\n").filter((l) => l.trim() !== SPAWN);
    await writeUserFile(NIRI, kept.join("\n"));
    say("removed the udiskie line from the niri config");
  }

  await removeArch(CONFIG);
  say(`removed ${CONFIG}`);
}

async function verify(): Promise<void> {
  (await existsInArch("/usr/bin/udiskie")) ? ok("udiskie installed") : fail("udiskie missing");
  (await readArch(`/home/${ARCH_USER}/.config/udiskie/config.yml`)) !== null
    ? ok("udiskie config present") : fail("udiskie config missing");
  const niri = (await readArch(`/home/${ARCH_USER}/.config/niri/config.kdl`)) ?? "";
  niri.includes('spawn-at-startup "udiskie"')
    ? ok("niri starts udiskie") : fail("niri does not start udiskie");
}

await main({ up, down, verify });
