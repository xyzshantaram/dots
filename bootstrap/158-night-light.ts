/**
 * ---
 * script: 158-night-light.ts
 * desc: Installs the night light: gammastep, positioned from the machine's own location each session, falling back to Bangalore.
 * needs: 40-packages.ts up (gammastep, curl), 110-niri.ts up (the spawn line), 50-user.ts up
 * up: installs /usr/local/bin/night-light and checks it parses
 * down: removes the helper
 * revisit: 2026-12-21
 * ---
 *
 * A helper rather than a gammastep flag, because gammastep takes a fixed
 * latitude and longitude and this machine moves. The helper asks once, at
 * session start, and hands gammastep whatever it gets — or Bangalore, if the
 * network is not up yet or is a captive portal. See files/bin/night-light for
 * the reasoning; this step only installs it.
 *
 * niri spawns it, not systemd. gammastep is a Wayland client, so it needs the
 * session's socket, and niri's spawn-at-startup is the house pattern for
 * things that belong to the session rather than to the machine — the wallpaper,
 * udiskie and the shell are all there for the same reason. The spawn line lives
 * in files/niri/config.kdl with the others, so this step has one thing to
 * install and one thing to remove.
 *
 * gammastep is not installed here. It is in 40-packages.ts, because a package
 * list that is the whole machine's packages is easier to read than one that is
 * scattered through the steps that happen to want them.
 */
import {
  ARCH_USER, existsInArch, fail, inArch, inArchSoft, main, needMount, ok, readArch,
  removeArch, say, writeArch,
} from "./lib.ts";

const TARGET = "/usr/local/bin/night-light";

async function up(): Promise<void> {
  await needMount();

  await writeArch(TARGET, await Bun.file(`${import.meta.dir}/files/bin/night-light`).text());
  say(`installed ${TARGET}`);

  // writeArch writes 0644, and a helper under /usr/local/bin is root-owned, so
  // nobody but this step can make it runnable. Without this the spawn fails
  // with "Permission denied" and the night light simply never starts — which is
  // exactly what it did the first time.
  const mode = await inArch("chmod", "755", TARGET).nothrow();
  say(mode.exitCode === 0 ? "made it executable" : `could not chmod ${TARGET}`);

  const syntax = await inArchSoft("sh", "-n", TARGET);
  if (syntax.exitCode !== 0) {
    say("night-light has a syntax error:");
    process.stderr.write(syntax.stderr.toString());
    process.exit(1);
  }
  say("night-light parses");

  if ((await inArchSoft("pacman", "-Qq", "gammastep")).exitCode !== 0) {
    say("gammastep is not installed; run 40-packages.ts up first or this will fail at login");
  }
}

async function down(): Promise<void> {
  await needMount();
  await removeArch(TARGET);
  say(`removed ${TARGET}; the spawn line in the niri config is 110-niri.ts's`);
}

async function verify(): Promise<void> {
  (await existsInArch("/usr/local/bin/night-light"))
    ? ok("night-light installed") : fail("night-light missing");
  const pkg = await inArchSoft("pacman", "-Qq", "gammastep");
  pkg.stdout.toString().trim() !== "" ? ok("gammastep installed") : fail("gammastep missing");
  const niri = (await readArch(`/home/${ARCH_USER}/.config/niri/config.kdl`)) ?? "";
  niri.includes("night-light") ? ok("niri starts night-light") : fail("niri does not start night-light");
}

await main({ up, down, verify });
