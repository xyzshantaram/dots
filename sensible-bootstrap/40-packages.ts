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
import { inArch, main, needMount, say } from "./lib.ts";

const BASE = [
  "base-devel", "git", "sudo", "fish", "bash", "btrfs-progs",
  "networkmanager", "pipewire", "pipewire-pulse", "wireplumber",
];

/**
 * The kernel the ESP hook copies, and the microcode that must load before its
 * initramfs. Without these two the boot entries written by 150-kernel-sync
 * point at files that do not exist, and systemd-boot refuses the entry.
 * linux-zen is usually already there from pacstrap; --needed makes it a no-op.
 */
const KERNEL = ["linux-zen", "amd-ucode"];

const DESKTOP = [
  "niri", "wezterm", "quickshell", "swaync", "gtklock", "nwg-drawer",
  "swaybg", "xdg-desktop-portal-gnome", "xdg-desktop-portal-gtk",
  "nautilus", "papers", "gedit",
];

const HW = [
  "keyd", "brightnessctl", "playerctl", "fprintd",
  "linux-firmware-amdgpu", "linux-firmware-other",
];

const FONTS = [
  "ttf-fantasque-nerd", "inter-font",
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

const APPS = ["firefox", "podman"];

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

async function up(): Promise<void> {
  await needMount();
  say(`installing ${PKGS.length} packages`);
  const result = await inArch("pacman", "-S", "--needed", "--noconfirm", ...PKGS).nothrow();
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

await main({ up, down });
