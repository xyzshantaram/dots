/**
 * ---
 * script: 135-icons.ts
 * desc: Installs the Boston icon theme from the AUR and points GTK at it.
 * needs: 40-packages.ts up (git, base-devel), 50-user.ts up
 * up: builds boston-icon-theme-git from the AUR as ARCH_USER and installs it as root, then writes gtk-3.0/gtk-4.0 settings and tries gsettings
 * down: removes the two settings files and the theme package
 * revisit: 2026-12-21
 * ---
 *
 * The theme comes from boston-icon-theme-git, not boston-icon-theme, and that is
 * not a preference. The plain package builds its source array by scraping a
 * webpage while makepkg parses the PKGBUILD:
 *
 *   _od_url=$(curl -s "https://www.opendesktop.org/dl?file_id=..." -X POST ... |
 *             sed -n 's|^ *<a href="\([^"]*\)">Please click here</a>.*$|\1|p')
 *   source=($_od_url)
 *
 * opendesktop.org now answers that request with a bot challenge - Anubis, the
 * same proxy the AUR itself uses - so the scrape returns nothing, _od_url is
 * empty, and source=() collapses to zero entries against one sha256sums entry.
 * makepkg reports that as "Integrity checks (sha256) differ in size from the
 * source array", which names the symptom rather than the cause. The package has
 * been flagged out of date since September 2026 and cannot be built by anyone.
 *
 * boston-icon-theme-git clones https://github.com/heychrisd/Boston-Icons with
 * sha256sums=('SKIP') instead, so there is no scrape and no expiring URL. It
 * provides and conflicts with boston-icon-theme, so it is a drop-in
 * replacement.
 *
 * The installed directory name comes from the theme itself, so it is globbed
 * from /usr/share/icons rather than hardcoded.
 */
import { $ } from "bun";
import process from "node:process";
import {
  ARCH_USER, asUser, aurInstall, inArchSoft, main, needMount, removeArch, say,
  writeUserFile,
} from "./lib.ts";

const HOME = `/home/${ARCH_USER}`;

/** The AUR package, and the name it installs under for pacman. */
const THEME = "boston-icon-theme-git";

async function up(): Promise<void> {
  await needMount();

  await aurInstall(THEME);

  const listing = await inArchSoft("ls", "-1", "/usr/share/icons");
  const theme = listing.stdout.toString().split("\n").find((d) => /^boston/i.test(d));
  if (!theme) {
    say("no Boston* directory under /usr/share/icons after install");
    process.exit(1);
  }
  say(`icon theme directory: ${theme}`);

  const settings = `[Settings]
gtk-icon-theme-name=${theme}
gtk-theme-name=Adwaita
gtk-application-prefer-dark-theme=false
`;

  await writeUserFile(`${HOME}/.config/gtk-3.0/settings.ini`, settings);
  await writeUserFile(`${HOME}/.config/gtk-4.0/settings.ini`, settings);
  say("wrote gtk-3.0 and gtk-4.0 settings.ini");

  const gsettings = await asUser(
    "gsettings", "set", "org.gnome.desktop.interface", "icon-theme", theme,
  ).nothrow().quiet();
  say(
    gsettings.exitCode === 0
      ? "gsettings updated"
      : "gsettings skipped (no session bus in chroot)",
  );
}

async function down(): Promise<void> {
  await needMount();
  await removeArch(`${HOME}/.config/gtk-3.0/settings.ini`);
  await removeArch(`${HOME}/.config/gtk-4.0/settings.ini`);
  await inArchSoft("pacman", "-Rns", "--noconfirm", THEME);
  say("removed icon settings and the theme package");
}

await main({ up, down });
