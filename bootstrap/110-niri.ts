/**
 * ---
 * script: 110-niri.ts
 * desc: Installs the niri config and the session pieces it names: wezterm on Mod+T, vicinae on Mod+D, gtklock on Super+Alt+L, the six XF86 keys, swaync and qs at startup, and the Copilot key bound to voxtype. Installs vicinae itself (the launcher) and the mic-mute helper.
 * needs: 105-niri-gestures.ts up, 50-user.ts up, 40-packages.ts up
 * up: writes /home/ARCH_USER/.config/niri/config.kdl and validates it with niri validate; installs vicinae-bin from the AUR, enables its user unit, and installs /usr/local/bin/mic-mute
 * down: removes the config, the mic-mute helper, the launcher's unit link and the AUR package
 * revisit: 2026-12-21
 * ---
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
import { $ } from "bun";
import {
  ARCH_UID, ARCH_USER, asUserSoft, at, aurInstall, inArchSoft, main,
  needMount, removeArch, say, writeArch, writeUserFile,
} from "./lib.ts";

const DEST = `/home/${ARCH_USER}/.config/niri/config.kdl`;
const HOME = `/home/${ARCH_USER}`;

/** The launcher. AUR-only; the plain name is not in any official repo. */
const LAUNCHER = "vicinae-bin";
const LAUNCHER_UNIT = "/usr/lib/systemd/user/vicinae.service";
/** Where `systemctl --user enable vicinae.service` would put the link. */
const LAUNCHER_WANTS = `${HOME}/.config/systemd/user/graphical-session.target.wants`;

/** Toggles PipeWire and the ALSA switch behind the ThinkPad mic LED together. */
const MIC_MUTE = "/usr/local/bin/mic-mute";

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
}

async function up(): Promise<void> {
  await needMount();

  const content = await Bun.file(`${import.meta.dir}/files/niri/config.kdl`).text();
  await writeUserFile(DEST, content);
  say(`installed ${DEST}`);

  await installLauncher();

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

  const validate = await asUserSoft("niri", "validate", "-c", DEST);

  if (validate.exitCode !== 0) {
    say("niri rejected the config:");
    process.stderr.write(validate.stderr.toString());
    process.exit(1);
  }
  const out = validate.stdout.toString().trim();
  say(out ? `niri validate: ${out}` : "niri validate: config ok");

  say("binds: Mod+T wezterm / Mod+D vicinae / Super+Alt+L gtklock");
  say("keys: volume mute -5% +5%, mic mute, brightness up/down, Pause -> voxtype");
  say("gestures: 3-finger up/down = overview, 4-finger = workspaces and columns");
}

async function down(): Promise<void> {
  await needMount();

  await removeArch(`${LAUNCHER_WANTS}/vicinae.service`);
  await inArchSoft("pacman", "-Rns", "--noconfirm", LAUNCHER);
  say(`removed the ${LAUNCHER} unit link and package`);

  await removeArch(MIC_MUTE);
  await removeArch(DEST);
  say("removed the mic-mute helper and the niri config");
}

await main({ up, down });
