/**
 * ---
 * script: 110-niri.ts
 * desc: Installs the niri config and the session pieces it names: wezterm on Mod+T, vicinae on Mod+D, the Quickshell lock on Mod+L, the six XF86 keys, swaync and qs at startup, and the Copilot key bound to voxtype. Installs vicinae itself (the launcher) and the mic-mute helper.
 * needs: 105-niri-gestures.ts up, 50-user.ts up, 40-packages.ts up
 * up: writes /home/ARCH_USER/.config/niri/ (config.kdl and conf.d/) and validates it with niri validate; installs vicinae-bin from the AUR, enables its user unit, and installs /usr/local/bin/mic-mute
 * down: removes the config directory, the mic-mute helper, the launcher's unit link and the AUR package
 * revisit: 2026-12-21
 * ---
 *
 * The config is split. conf.d/ is the source, one topic per file, and
 * config.kdl is generated from it by the vendored niri-split (MIT) in
 * bootstrap/tools/. Both are installed: niri reads only config.kdl, while
 * conf.d/ is what a person edits. Rebuild with `bun run niri-split` after an
 * edit. The generated file is committed, so the ladder itself never needs
 * python.
 *
 * The launcher is vicinae, which is AUR-only, so it comes through aurInstall
 * rather than 40-packages.ts. It is a server plus a client: a systemd *user*
 * unit holds the daemon and `vicinae toggle` is what the binds run. That unit
 * ships disabled, and a chroot has no user session to `systemctl --user enable`
 * against, so the enabling symlink is made by hand — the same trick
 * 170-dictation.ts uses for dictation.target.
 *
 * The F13 bind (Super/CapsLock tap, resolved in keyd) points at the same
 * command as Mod+D; if the tap ever stops working while Mod+D still does, the
 * problem is keyd or the tap window, not here.
 */
import process from "node:process";
import { readdir } from "node:fs/promises";
import { join, relative } from "node:path";
import { $ } from "bun";
import {
  ARCH_UID, ARCH_USER, LIVE, asUserSoft, at, aurInstall, fail, inArchSoft, main,
  needMount, ok, removeArch, say, writeArch, writeUserFile,
} from "./lib.ts";

const SRC = `${import.meta.dir}/files/niri`;
const DIR = `/home/${ARCH_USER}/.config/niri`;
const DEST = `${DIR}/config.kdl`;
const HOME = `/home/${ARCH_USER}`;

/** Every file under a directory, as paths relative to it. */
async function walk(dir: string, base = dir): Promise<string[]> {
  const out: string[] = [];
  for (const entry of await readdir(dir, { withFileTypes: true })) {
    const full = join(dir, entry.name);
    if (entry.isDirectory()) out.push(...(await walk(full, base)));
    else out.push(relative(base, full));
  }
  return out;
}

/** The launcher. AUR-only; the plain name is not in any official repo. */
const LAUNCHER = "vicinae-bin";
const LAUNCHER_UNIT = "/usr/lib/systemd/user/vicinae.service";
/** Where `systemctl --user enable vicinae.service` would put the link. */
const LAUNCHER_WANTS = `${HOME}/.config/systemd/user/graphical-session.target.wants`;

/** Toggles PipeWire and the ALSA switch behind the ThinkPad mic LED together. */
const MIC_MUTE = "/usr/local/bin/mic-mute";
const BRIGHTNESS = "/usr/local/bin/brightness";

async function installLauncher(): Promise<void> {
  if ((await inArchSoft("pacman", "-Q", LAUNCHER)).exitCode === 0) {
    say(`${LAUNCHER} already installed`);
  } else {
    // aurInstall rather than paru: a helper installs via `sudo pacman -U`, which
    // stops at a password prompt that has to be answered by hand. See lib.ts.
    await aurInstall(LAUNCHER);
  }

  await $`mkdir -p ${at(LAUNCHER_WANTS)}`;
  await $`ln -sf ${LAUNCHER_UNIT} ${at(LAUNCHER_WANTS)}/vicinae.service`;
  await $`chown ${ARCH_UID}:${ARCH_UID} ${at(LAUNCHER_WANTS)}`;
  await $`chown -h ${ARCH_UID}:${ARCH_UID} ${at(LAUNCHER_WANTS)}/vicinae.service`;
  say(`enabled vicinae.service for the user session (${LAUNCHER_WANTS})`);

  // Enabling is not enough when the target is the running system. By the time
  // the ladder writes this link, graphical-session.target has already been
  // reached, and systemd will not pull the unit in until the next login, so the
  // launcher has nothing to talk to. Ask that session to load and start it.
  //
  // A chroot has no user session to ask, and there the link alone is right.
  if (!LIVE) return;

  const runtime = `/run/user/${ARCH_UID}`;
  const session = (line: string) =>
    $`runuser -u ${ARCH_USER} -- env XDG_RUNTIME_DIR=${runtime} DBUS_SESSION_BUS_ADDRESS=unix:path=${runtime}/bus sh -c ${line}`
      .nothrow().quiet();

  await session("systemctl --user daemon-reload");
  const started = await session("systemctl --user start vicinae.service");
  say(
    started.exitCode === 0
      ? "vicinae.service started for this session"
      : "could not start vicinae.service; it will come up at the next login",
  );
}

async function up(): Promise<void> {
  await needMount();

  const files = await walk(SRC);
  for (const file of files) {
    await writeUserFile(`${DIR}/${file}`, await Bun.file(join(SRC, file)).text());
  }
  say(`installed ${files.length} files into ${DIR}`);

  // Local and quick, and before the launcher below: a network failure fetching
  // vicinae must not leave the mic key pointing at a file that was never
  // written.
  await writeArch(
    MIC_MUTE,
    await Bun.file(`${import.meta.dir}/files/bin/mic-mute`).text(),
    0o755,
  );
  const syntax = await inArchSoft("sh", "-n", MIC_MUTE);
  if (syntax.exitCode !== 0) {
    say("mic-mute has a syntax error:");
    process.stderr.write(syntax.stderr.toString());
    process.exit(1);
  }
  say(`installed ${MIC_MUTE}`);

  await writeArch(
    BRIGHTNESS,
    await Bun.file(`${import.meta.dir}/files/bin/brightness`).text(),
    0o755,
  );
  const bSyntax = await inArchSoft("sh", "-n", BRIGHTNESS);
  if (bSyntax.exitCode !== 0) {
    say("brightness has a syntax error:");
    process.stderr.write(bSyntax.stderr.toString());
    process.exit(1);
  }
  say(`installed ${BRIGHTNESS}`);

  const validate = await asUserSoft("niri", "validate", "-c", DEST);

  if (validate.exitCode !== 0) {
    say("niri rejected the config:");
    process.stderr.write(validate.stderr.toString());
    process.exit(1);
  }
  const out = validate.stdout.toString().trim();
  say(out ? `niri validate: ${out}` : "niri validate: config ok");

  // Last, because it is the only part that needs the network and an AUR build;
  // everything above is already usable without it.
  await installLauncher();

  say("binds: Mod+T wezterm / Mod+V clipboard / Mod+D toggle floating / Super tap vicinae");
  say("keys: volume mute -5% +5%, mic mute, brightness up/down, Pause -> voxtype");
  say("gestures: 3-finger up/down = overview, 4-finger = workspaces and columns");
}

async function down(): Promise<void> {
  await needMount();

  await removeArch(`${LAUNCHER_WANTS}/vicinae.service`);
  await inArchSoft("pacman", "-Rns", "--noconfirm", LAUNCHER);
  say(`removed the ${LAUNCHER} unit link and package`);

  await removeArch(MIC_MUTE);
  await removeArch(BRIGHTNESS);
  await removeArch(DIR);
  say("removed the mic-mute helper and the niri config directory");
}

async function verify(): Promise<void> {
  const cfg = `/home/${ARCH_USER}/.config/niri/config.kdl`;
  (await Bun.file(at(cfg)).exists()) ? ok("niri config present") : fail("niri config missing");
  (await Bun.file(at(`${DIR}/conf.d/01-outputs.kdl`)).exists())
    ? ok("niri conf.d present") : fail("niri conf.d missing");
  const v = await inArchSoft("niri", "validate", "-c", cfg);
  v.exitCode === 0 ? ok("niri accepts config.kdl") : fail("niri rejects config.kdl");
  (await Bun.file(at("/usr/local/bin/mic-mute")).exists()) ? ok("mic-mute installed") : fail("mic-mute missing");
  (await Bun.file(at("/usr/local/bin/brightness")).exists()) ? ok("brightness installed") : fail("brightness missing");
  const unit = `/home/${ARCH_USER}/.config/systemd/user/graphical-session.target.wants/vicinae.service`;
  (await Bun.file(at(unit)).exists()) ? ok("vicinae user unit enabled") : fail("vicinae user unit not enabled");
}

await main({ up, down, verify });
