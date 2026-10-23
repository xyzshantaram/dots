/**
 * ---
 * script: 170-dictation.ts
 * desc: Ports the NPU dictation stack: FastFlowLM Whisper server, Voxtype, the preview strip, and the Pause-key toggle wired in niri.
 * needs: 40-packages.ts up (fastflowlm, pyside6, layer-shell-qt, wtype, git, base-devel), 50-user.ts up, 110-niri.ts up, 80-fonts.ts up (CMU Serif)
 * up: builds voxtype-bin from the AUR as ARCH_USER and installs it as root, then the strip and its wtype wrapper into the account, the user units and the NPU sleep hook
 * down: removes the units, the private bin directory, the config and the AUR package
 * revisit: 2026-12-21
 * ---
 *
 * Transcription is remote: Voxtype captures the microphone, posts to FastFlowLM
 * on 127.0.0.1:52625, and types the returned text through wtype. The strip is a
 * wtype wrapper, so it previews the transcript before anything is typed.
 *
 * The wrapper shadows `wtype` on voxtype's PATH only. wtype is voxtype's own
 * preferred Wayland driver, so no translation is needed between what voxtype
 * emits and what the wrapper forwards. The wrapper calls the real binary by
 * absolute path, because it shadows the name on a PATH that lists its own
 * directory first.
 *
 * What changed from the Fedora install:
 *   - flm lives at /usr/bin/flm (the fastflowlm package), not /usr/local/bin.
 *   - typing goes through wtype (in the repos) rather than eitype (AUR). niri
 *     advertises zwp_virtual_keyboard_manager_v1, which is all wtype needs, and
 *     eitype exists for the compositors that do not.
 *   - the Copilot key reaches niri through the `Pause` bind in config.kdl,
 *     not a KDE global shortcut.
 *   - the KWin-specific bits in the strip (target-window reporting) are inert
 *     on niri; the strip still draws as a layer-shell surface.
 *   - amdxdna is the in-tree driver, so the sleep hook only unloads it.
 *
 * After the first boot, `flm validate` should print the NPU line. If it does
 * not, the DKMS driver is the fallback (see the README).
 */
import process from "node:process";
import { $ } from "bun";
import {
  ARCH_UID, ARCH_USER, at, aurInstall, inArchSoft, main, needMount,
  removeArch, say, writeArch, writeUserFile,
} from "./lib.ts";

const HOME = `/home/${ARCH_USER}`;
const SRC = `${import.meta.dir}/files/dictation`;

/** Files installed into the account, source relative to files/dictation. */
const USER_FILES: [string, string, number][] = [
  ["bin/wtype", `${HOME}/.local/share/dictation/bin/wtype`, 0o755],
  ["bin/dictation-strip", `${HOME}/.local/share/dictation/bin/dictation-strip`, 0o755],
  ["bin/dictation-wait-modifiers", `${HOME}/.local/share/dictation/bin/dictation-wait-modifiers`, 0o755],
  // dictation-strip resolves this as ../qml/DictationStrip.qml from its own
  // directory. Without it the strip exits non-zero and every transcript falls
  // back to the clipboard.
  ["qml/DictationStrip.qml", `${HOME}/.local/share/dictation/qml/DictationStrip.qml`, 0o644],
  ["config/bin/dictation", `${HOME}/.local/bin/dictation`, 0o755],
  ["config/voxtype/config.toml", `${HOME}/.config/voxtype/config.toml`, 0o644],
  ["config/systemd/dictation.target", `${HOME}/.config/systemd/user/dictation.target`, 0o644],
  ["config/systemd/flm-whisper.service", `${HOME}/.config/systemd/user/flm-whisper.service`, 0o644],
  ["config/systemd/voxtype.service", `${HOME}/.config/systemd/user/voxtype.service`, 0o644],
  ["config/applications/net.local.voxtype.desktop", `${HOME}/.local/share/applications/net.local.voxtype.desktop`, 0o644],
];

async function installAur(): Promise<void> {
  const missing: string[] = [];
  for (const pkg of ["voxtype-bin"]) {
    if ((await inArchSoft("pacman", "-Q", pkg)).exitCode !== 0) missing.push(pkg);
  }
  if (missing.length === 0) {
    say("voxtype-bin already installed");
    return;
  }

  // aurInstall rather than paru: a helper installs via `sudo pacman -U`, which
  // stops at a password prompt that has to be answered by hand. See lib.ts.
  await aurInstall(...missing);
}

async function up(): Promise<void> {
  await needMount();

  await installAur();

  for (const [source, dest, mode] of USER_FILES) {
    await writeUserFile(dest, await Bun.file(`${SRC}/${source}`).text(), mode);
  }
  say(`installed ${USER_FILES.length} files into ${HOME}`);

  // The desktop file carried Fedora's absolute path; retarget it.
  const desktop = `${HOME}/.local/share/applications/net.local.voxtype.desktop`;
  const text = await Bun.file(at(desktop)).text();
  await writeUserFile(desktop, text.replaceAll("/home/sid", HOME));
  say("retargeted the desktop entry at the Arch account");

  // default.target wants dictation.target. A symlink is what `systemctl --user
  // enable` would create; a chroot has no user session to run it in.
  const wants = `${HOME}/.config/systemd/user/default.target.wants`;
  await $`mkdir -p ${at(wants)}`;
  await $`ln -sf ../dictation.target ${at(wants)}/dictation.target`;
  await $`chown -h ${ARCH_UID}:${ARCH_UID} ${at(wants)} ${at(wants)}/dictation.target`;
  say("enabled dictation.target for the user session");

  // NPU needs a high memlock limit. flm validate reports it.
  await writeArch(
    "/etc/security/limits.d/20-dictation.conf",
    `# FastFlowLM runs Whisper on the NPU and needs to lock its buffers.
* soft memlock unlimited
* hard memlock unlimited
`,
  );
  say("raised the memlock limit");

  // Keep the NPU out of the hibernate power path: its resume path times out
  // and leaves the device dead until reboot. The vendored hook hardcodes
  // USER_NAME=sid, so replace that whole assignment rather than the literal.
  const hookSource = await Bun.file(`${SRC}/../sleep/50-dictation-npu.sh`).text();
  const hook = hookSource.replace(/^USER_NAME=.*$/m, `USER_NAME=${ARCH_USER}`);
  if (!hook.includes(`USER_NAME=${ARCH_USER}`)) {
    say(`could not retarget the sleep hook at ${ARCH_USER}`);
    process.exit(1);
  }
  await writeArch("/usr/lib/systemd/system-sleep/50-dictation-npu.sh", hook, 0o755);
  say("installed the NPU sleep hook");

  const syntax = await inArchSoft("python3", "-c", "import ast,sys; ast.parse(open(sys.argv[1]).read())",
    `${HOME}/.local/share/dictation/bin/dictation-strip`);
  say(
    syntax.exitCode === 0
      ? "dictation-strip parses"
      : "dictation-strip does not parse as Python; check the file",
  );

  say("toggle: the Copilot key (Pause) is bound in niri to `voxtype record toggle`");
  say("verify after first boot: flm validate   (expect an NPU line)");
}

async function down(): Promise<void> {
  await needMount();

  await removeArch(`${HOME}/.config/systemd/user/default.target.wants/dictation.target`);
  for (const [, dest] of USER_FILES) await removeArch(dest);
  await removeArch(`${HOME}/.local/share/dictation`);
  await removeArch(`${HOME}/.config/voxtype`);
  await removeArch("/etc/security/limits.d/20-dictation.conf");
  await removeArch("/usr/lib/systemd/system-sleep/50-dictation-npu.sh");
  say("removed the dictation files");

  await inArchSoft("pacman", "-Rns", "--noconfirm", "voxtype-bin");
  say("removed the AUR package");
}

await main({ up, down });
