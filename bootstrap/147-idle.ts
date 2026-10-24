/**
 * ---
 * script: 147-idle.ts
 * desc: Idle hibernation through swayidle: 20 minutes on AC, 10 minutes on battery.
 * needs: 145-hibernate.ts up, 110-niri.ts up (config.kdl), 40-packages.ts up (swayidle), 50-user.ts up
 * up: installs idle-hibernate and adds a spawn-at-startup line to the niri config
 * down: removes the helper and that one line
 * revisit: 2026-12-21
 * ---
 *
 * swayidle rather than logind's IdleAction: logind only reports idle when the
 * session marks itself idle, and niri does not. niri implements
 * ext-idle-notify-v1, which is what swayidle listens to.
 *
 * swayidle's timeouts are static, so both timers run and idle-hibernate
 * decides from /sys/class/power_supply/AC/online whether to act.
 *
 * Started from niri, not from an XDG autostart entry: niri does not implement
 * the XDG autostart spec, so a .desktop file here would simply never run.
 *
 * Lid close is separate and lives in 145-hibernate.ts (logind, instant).
 */
import process from "node:process";
import {
  ARCH_USER, existsInArch, fail, inArchSoft, main, needMount, ok, readArch, removeArch,
  say, writeArch, writeUserFile,
} from "./lib.ts";

const NIRI = `/home/${ARCH_USER}/.config/niri/config.kdl`;

/** One line, so undo can remove exactly what it added.
 *
 * The command and its argument are a single quoted word. swayidle parses the
 * argument list as `timeout <seconds> <command>`, so `"idle-hibernate" "battery"`
 * made it treat `battery` as the next keyword: it exited with "Unsupported
 * command 'battery'" and 255 before the first timer, which is why idle
 * hibernation never happened.
 */
const SPAWN =
  'spawn-at-startup "swayidle" "-w" ' +
  '"timeout" "600" "/usr/local/bin/idle-hibernate battery" ' +
  '"timeout" "1200" "/usr/local/bin/idle-hibernate ac"';

async function up(): Promise<void> {
  await needMount();

  await writeArch(
    "/usr/local/bin/idle-hibernate",
    await Bun.file(`${import.meta.dir}/files/idle/idle-hibernate`).text(),
    0o755,
  );
  say("installed /usr/local/bin/idle-hibernate");

  const config = await readArch(NIRI);
  if (config === null) {
    say(`${NIRI} is missing; run 110-niri.ts up first`);
    process.exit(1);
  }
  if (config.split("\n").some((l) => l.trim() === SPAWN)) {
    say("niri already starts swayidle");
  } else {
    await writeUserFile(NIRI, `${config}${config.endsWith("\n") ? "" : "\n"}${SPAWN}\n`);
    say("added the swayidle line to the niri config");
  }

  const check = await inArchSoft("bash", "-n", "/usr/local/bin/idle-hibernate");
  if (check.exitCode !== 0) {
    say("idle-hibernate has a syntax error");
    process.stderr.write(check.stderr.toString());
    process.exit(1);
  }
  say("idle-hibernate parses");
  say("timers: 10 min -> hibernate if on battery; 20 min -> hibernate if on AC");
}

async function down(): Promise<void> {
  await needMount();

  const config = await readArch(NIRI);
  if (config !== null) {
    const kept = config.split("\n").filter((l) => l.trim() !== SPAWN);
    await writeUserFile(NIRI, kept.join("\n"));
    say("removed the swayidle line from the niri config");
  }

  await removeArch("/usr/local/bin/idle-hibernate");
  say("removed idle-hibernate");
}

async function verify(): Promise<void> {
  (await existsInArch("/usr/local/bin/idle-hibernate"))
    ? ok("idle-hibernate installed") : fail("idle-hibernate missing");
  const niri = (await readArch(`/home/${ARCH_USER}/.config/niri/config.kdl`)) ?? "";
  niri.includes("idle-hibernate")
    ? ok("niri starts swayidle") : fail("niri does not start swayidle; idle does nothing");
}

await main({ up, down, verify });
