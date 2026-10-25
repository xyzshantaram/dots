/**
 * ---
 * script: 112-wallpaper.ts
 * desc: Installs wallpaper-random and points niri at it, so every session starts with a random wallpaper from the account's wallpapers directory, recorded for the terminal.
 * needs: 110-niri.ts up (config.kdl), 50-user.ts up, 40-packages.ts up (swaybg)
 * up: copies files/wallpapers/* into the account's wallpapers dir, installs the picker, adds one spawn-at-startup line
 * down: removes the picker and that one line; wallpapers are left alone
 * revisit: 2026-12-21
 * ---
 *
 * The wallpaper itself is not committed. files/wallpapers/ carries a .gitignore
 * whose only job is to keep the contents out of version control, so the repo
 * ships the mechanism and the user supplies the images. See that directory's
 * README.
 *
 * niri's spawn-at-startup is used rather than an XDG autostart entry for the
 * same reason as 147-idle.ts: niri does not implement the XDG autostart spec,
 * so a .desktop file here would simply never run.
 *
 * swaybg is exec'd from the script, so it stays foreground and niri keeps it
 * alive for the session. If there are no wallpapers the script exits 0 without
 * starting anything, which leaves a plain background rather than a failed unit.
 *
 * The picker also writes the chosen path to
 * $XDG_RUNTIME_DIR/current-wallpaper. 100-wezterm and the lock screen read
 * that file, so the terminal's background and the lock's blurred image are the
 * same as the desktop's instead of choosing images of their own.
 */
import process from "node:process";
import { $ } from "bun";
import {
  ARCH_UID, ARCH_USER, asUserSoft, at, fail, main, needMount, ok, readArch, removeArch,
  say, writeArch, writeUserFile,
} from "./lib.ts";

const VENDORED = `${import.meta.dir}/files/wallpapers`;
const PICKER = "/usr/local/bin/wallpaper-random";
const NIRI = `/home/${ARCH_USER}/.config/niri/config.kdl`;
const PAPERS = `/home/${ARCH_USER}/wallpapers`;

/** One line, so undo can remove exactly what it added. */
const SPAWN = 'spawn-at-startup "/usr/local/bin/wallpaper-random"';

const IMAGE = /\.(png|jpe?g|webp|gif|bmp)$/i;

async function vendoredImages(): Promise<string[]> {
  const listing = await $`ls -A ${VENDORED}`.nothrow().quiet();
  if (listing.exitCode !== 0) return [];
  return listing.stdout
    .toString()
    .trim()
    .split("\n")
    .filter((f) => f && IMAGE.test(f));
}

/**
 * Copies the repo's wallpapers into the account, never overwriting.
 *
 * Additive on purpose: the account's wallpapers directory is the user's own, so
 * a second run must not clobber something dropped there by hand, and `down`
 * must not delete it.
 */
async function installPapers(): Promise<number> {
  const images = await vendoredImages();
  if (images.length === 0) {
    say(`no images in files/wallpapers; the account keeps whatever it has`);
    return 0;
  }

  await $`mkdir -p ${at(PAPERS)}`;
  let copied = 0;
  for (const name of images) {
    const dest = `${at(PAPERS)}/${name}`;
    if ((await $`test -e ${dest}`.nothrow().quiet()).exitCode === 0) continue;
    const result = await $`cp -a ${`${VENDORED}/${name}`} ${dest}`.nothrow();
    if (result.exitCode !== 0) {
      say(`could not copy ${name}`);
      process.stderr.write(result.stderr.toString());
      continue;
    }
    copied++;
  }
  await $`chown -R ${ARCH_UID}:${ARCH_UID} ${at(PAPERS)}`.nothrow().quiet();
  say(`copied ${copied} of ${images.length} wallpaper(s) into ${PAPERS}`);
  return copied;
}

async function up(): Promise<void> {
  await needMount();

  await $`mkdir -p ${at(PAPERS)}`;
  await $`chown ${ARCH_UID}:${ARCH_UID} ${at(PAPERS)}`.nothrow().quiet();
  await installPapers();

  await writeArch(PICKER, await Bun.file(`${import.meta.dir}/files/wallpaper/wallpaper-random`).text(), 0o755);
  say(`installed ${PICKER}`);

  const check = await $`bash -n ${at(PICKER)}`.nothrow().quiet();
  if (check.exitCode !== 0) {
    say("wallpaper-random has a syntax error");
    process.stderr.write(check.stderr.toString());
    process.exit(1);
  }
  say("wallpaper-random parses");

  const config = await readArch(NIRI);
  if (config === null) {
    say(`${NIRI} is missing; run 110-niri.ts up first`);
    process.exit(1);
  }
  if (config.split("\n").some((l) => l.trim() === SPAWN)) {
    say("niri already starts wallpaper-random");
  } else {
    await writeUserFile(NIRI, `${config}${config.endsWith("\n") ? "" : "\n"}${SPAWN}\n`);
    say("added the wallpaper line to the niri config");
  }

  const validate = await asUserSoft("niri", "validate", "-c", NIRI);
  if (validate.exitCode !== 0) {
    say("niri rejected the config after this change");
    process.stderr.write(validate.stderr.toString());
    process.exit(1);
  }
  say("niri validate: config ok");
  say("a random wallpaper is chosen at each session start and recorded for WezTerm");
}

async function down(): Promise<void> {
  await needMount();

  const config = await readArch(NIRI);
  if (config !== null) {
    const kept = config.split("\n").filter((l) => l.trim() !== SPAWN);
    await writeUserFile(NIRI, kept.join("\n"));
    say("removed the wallpaper line from the niri config");
  }

  await removeArch(PICKER);
  say(`removed ${PICKER}`);
  // papers stay: they are the user's files, not ours to delete.
  say(`left ${PAPERS} alone`);
}

async function verify(): Promise<void> {
  (await Bun.file(at("/usr/local/bin/wallpaper-random")).exists())
    ? ok("wallpaper-random installed") : fail("wallpaper-random missing");
  const niri = (await readArch(`/home/${ARCH_USER}/.config/niri/config.kdl`)) ?? "";
  niri.includes("wallpaper-random")
    ? ok("niri starts wallpaper-random") : fail("niri does not start wallpaper-random");
}

await main({ up, down, verify });
