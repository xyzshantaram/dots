/**
 * ---
 * script: 40-packages.ts
 * desc: Installs every package the Arch side needs, in one pass, grouped so a failure is readable.
 * needs: 30-keys.ts up, network
 * up: pacman -S --needed over the groups below
 * down: pacman -Rns over the same list, ignoring failures
 * revisit: 2026-12-21
 * ---
 */
import process from "node:process";
import { fail, inArch, inArchSoft, main, needMount, note, ok, say } from "./lib.ts";

/**
 * pipewire-alsa is the bridge from ALSA's `default` device to PipeWire, and
 * pipewire-jack the same for JACK clients. Without the first, an application
 * that opens ALSA rather than PipeWire — voxtype does — finds no capture device
 * at all and reports "The requested device is no longer available", which is
 * what broke dictation on the first boot.
 *
 * python is for niri-split, the vendored KDL preprocessor in
 * bootstrap/tools/niri-split: `bun run niri-split` rebuilds the generated
 * config.kdl from conf.d/. The ladder installs the committed file, so python
 * is only needed to regenerate by hand.
 *
 * mandoc provides man, apropos and whatis, which is what reads the pages the
 * notes here point at; a fresh install has no manual at all without it.
 */
const BASE = [
  "base-devel", "git", "sudo", "fish", "bash", "btrfs-progs", "nano", "mandoc",
  "python",
  "networkmanager", "pipewire", "pipewire-pulse", "pipewire-alsa", "pipewire-jack",
  "wireplumber",
];

/**
 * The kernel the ESP hook copies, and the microcode that must load before its
 * initramfs. Without these two the boot entries written by 150-kernel-sync
 * point at files that do not exist, and systemd-boot refuses the entry.
 * linux-zen is usually already there from pacstrap; --needed makes it a no-op.
 *
 * efibootmgr is neither kernel nor microcode. systemd-boot manages its own
 * entries through bootctl, so this is here to read and repair the NVRAM entry
 * list from the installed system — the way back in when the boot menu is wrong.
 */
const KERNEL = ["linux-zen", "amd-ucode", "efibootmgr"];

/**
 * The launcher (vicinae) is not here: it is AUR-only, so 110-niri.ts installs
 * it through aurInstall instead. nwg-drawer used to sit in this list.
 *
 * swaync used to be here as the notification daemon, spawned before qs so
 * notifications existed by the time the shell registered. Quickshell's own
 * NotificationServer replaced it: one daemon, and the one that the control
 * centre can actually draw.
 *
 * polkit-gnome is the authentication agent. Without one, every polkit action
 * that needs a prompt fails immediately with "Not Authorized" instead of asking
 * — enrolling a fingerprint, mounting a filesystem, pkexec — because polkitd has
 * nobody to ask. niri does not implement XDG autostart, so the agent's .desktop
 * never runs and 110-niri spawns the binary from the session instead.
 *
 * kanshi arranges outputs on hotplug. niri can do it only by connector name,
 * and the Acer's connector changes with the path it takes, so 111-kanshi.ts
 * matches the monitor by make, model and serial instead.
 */
const DESKTOP = [
  "niri", "kanshi", "wezterm", "quickshell", "polkit-gnome",
  "swaybg", "xdg-desktop-portal-gnome", "xdg-desktop-portal-gtk",
  "nautilus", "papers", "gedit",
];

/**
 * Hardware access. ddcutil is what sets brightness on an external monitor, over
 * DDC/CI: there is no sysfs node for it the way there is for the internal
 * panel. It talks to /dev/i2c-*, so it also wants the i2c-dev module loaded and
 * write access to those nodes, which this ladder does not arrange — expect to
 * add the account to a group or a udev rule before it works.
 *
 * tuned is what the control centre's power menu switches, through tuned-adm.
 * TuneD rather than power-profiles-daemon: the two claim the same role and
 * cannot coexist, and TuneD is the one with profiles worth having on an AMD
 * laptop. The unit needs enabling as well as installing, which is the one thing
 * this list cannot do.
 */
const HW = [
  "keyd", "brightnessctl", "playerctl", "fprintd", "alsa-utils", "ddcutil",
  "tuned",
  "linux-firmware-amdgpu", "linux-firmware-other",
];

/**
 * Lilex is the monospace default and comes patched from extra: the Nerd Font
 * build carries the icon glyphs, so the shell and the terminal do not need a
 * second font behind it. Fantasque stays installed because it was asked for,
 * not because anything resolves through it. Inter is the sans default; the
 * Noto families cover CJK, extra scripts and emoji.
 */
const FONTS = [
  "ttf-lilex-nerd", "ttf-fantasque-nerd", "inter-font",
  "noto-fonts", "noto-fonts-cjk", "noto-fonts-emoji", "noto-fonts-extra",
];

const IDLE = ["swayidle"];

/**
 * Removable media. udisks2 is the daemon that talks to the kernel and is
 * D-Bus activated, so it is not enabled as a service anywhere; udiskie is the
 * automounter that drives it, started from the niri session by 114-udisks.ts.
 * ArchWiki, udisks.
 */
const STORAGE = ["udisks2", "udiskie"];

/**
 * General applications. ffmpeg sits here rather than with the personal ladder's
 * audio and video tools, because it is useful on its own whether or not any of
 * those are installed.
 *
 * flatpak is the package manager, not flatpak-apps: the applications it carries
 * are installed by the ladders that want them (see personal/60-spotify.ts), so
 * that removing this step does not silently remove somebody's music.
 *
 * gammastep is the night light — the Wayland successor to redshift, which is
 * what knows when sunset is at a given latitude rather than at a fixed hour.
 *
 * gnome-system-monitor is the per-process view. The bar's split pill says how
 * loaded the machine is, not by what, and this is where that question gets
 * answered.
 */
const APPS = ["firefox", "podman", "ffmpeg", "flatpak", "gammastep", "gnome-system-monitor"];

/**
 * Dictation. fastflowlm 1.0.9 is in extra and newer than the AUR's
 * 0.9.34.r36; it depends on xrt and xrt-plugin-amdxdna itself. pyside6 and
 * layer-shell-qt are for the preview strip.
 *
 * wtype is the typing backend: voxtype prefers it on Wayland, and it needs
 * only the virtual-keyboard protocol that niri advertises. It lives here
 * rather than in DESKTOP because dictation is the only consumer.
 */
const DICT = ["fastflowlm", "xrt", "xrt-plugin-amdxdna", "pyside6", "layer-shell-qt", "wtype"];

const GREET = ["fortune-mod", "cowsay"];

const PKGS = [...BASE, ...KERNEL, ...DESKTOP, ...HW, ...FONTS, ...IDLE, ...STORAGE, ...APPS, ...DICT, ...GREET];

/**
 * The list to install, minus the stock niri when the patched build is in place.
 *
 * `pacman -S --needed niri` does not count "niri-gestures provides niri" as
 * satisfied — it would install the stock package, and because niri-gestures
 * conflicts with it, --noconfirm would drop the patched build without asking.
 * Rerunning `up` from an earlier step would then quietly undo
 * 105-niri-gestures.
 */
async function targets(): Promise<string[]> {
  if ((await inArchSoft("pacman", "-Qq", "niri-gestures")).exitCode !== 0) return PKGS;
  say("niri is provided by niri-gestures; leaving the stock package out");
  return PKGS.filter((pkg) => pkg !== "niri");
}

async function up(): Promise<void> {
  await needMount();
  const pkgs = await targets();
  say(`installing ${pkgs.length} packages`);
  const result = await inArch("pacman", "-S", "--needed", "--noconfirm", ...pkgs).nothrow();
  if (result.exitCode !== 0) {
    say("pacman failed; see above. Re-run this step once fixed.");
    process.exit(result.exitCode);
  }
  say("installed");
}

async function down(): Promise<void> {
  await needMount();
  say("removing installed packages (failures ignored)");
  for (const pkg of PKGS) {
    await inArch("pacman", "-Rns", "--noconfirm", pkg).nothrow().quiet();
  }
  say("removed; orphans left in place on purpose");
}

async function verify(): Promise<void> {
  // pacman -T prints what is not installed, so the check is the whole group in
  // one call rather than one pacman per package.
  const critical = ["niri", "quickshell", "greetd", "keyd", "snapper", "udiskie", "gammastep", "fprintd", "fish"];
  const r = await inArchSoft("pacman", "-T", ...critical);
  const missing = r.stdout.toString().trim();
  if (r.exitCode !== 0 && missing !== "") fail(`missing packages: ${missing.replace(/\n/g, " ")}`);
  else ok("the core package set is installed");
}

await main({ up, down, verify });
