/**
 * ---
 * script: 135-icons.ts
 * desc: Installs the purple Tela icon theme from the AUR, points GTK at it, and switches GTK to its dark variant.
 * needs: 40-packages.ts up (git, base-devel), 50-user.ts up
 * up: builds tela-icon-theme-purple-git from the AUR as ARCH_USER and installs it as root, then writes gtk-3.0/gtk-4.0 settings and tries gsettings
 * down: removes the two settings files and the theme package
 * revisit: 2026-12-21
 * ---
 *
 * Tela, and only its purple variant, which is why the package is
 * tela-icon-theme-purple-git rather than tela-icon-theme. The plain package
 * builds every colour at once and there would be nothing left to name: the
 * point of picking a theme is the one you chose. The git package clones
 * https://github.com/vinceliuice/Tela-icon-theme and runs its install script
 * for the purple folders alone.
 *
 * It replaces Boston. That one was pinned to boston-icon-theme-git because the
 * plain boston-icon-theme could not be built at all: it built its source array
 * by scraping opendesktop.org while makepkg parsed the PKGBUILD, and that site
 * now answers with the same bot challenge the AUR itself uses, so the scrape
 * returned nothing and makepkg reported it as "Integrity checks (sha256) differ
 * in size from the source array". A URL fetched inside a PKGBUILD is a package
 * that expires; the lesson is worth keeping even though the theme is not.
 *
 * Dark is one flag, not a second theme package. gtk-application-prefer-dark-theme
 * selects the dark variant libgtk-3 carries inside itself, and color-scheme is
 * what GTK4 and libadwaita actually read. Neither needs gnome-themes-extra, and
 * neither needs an Adwaita-dark directory under /usr/share/themes — there is
 * none on this machine and there does not have to be.
 *
 * The installed directory name comes from the theme itself, so it is globbed
 * from /usr/share/icons rather than hardcoded.
 */
import process from "node:process";
import {
  ARCH_USER, asUser, aurInstall, fail, inArchSoft, main, needMount, ok, readArch,
  removeArch, say, writeUserFile,
} from "./lib.ts";

const HOME = `/home/${ARCH_USER}`;

/** The AUR package: Tela, purple folders only. */
const THEME = "tela-icon-theme-purple-git";

async function up(): Promise<void> {
  await needMount();

  await aurInstall(THEME);

  const listing = await inArchSoft("ls", "-1", "/usr/share/icons");
  const theme = listing.stdout.toString().split("\n").find((d) => /^tela.*purple/i.test(d));
  if (!theme) {
    say("no Tela*purple* directory under /usr/share/icons after install");
    process.exit(1);
  }
  say(`icon theme directory: ${theme}`);

  const settings = `[Settings]
gtk-icon-theme-name=${theme}
gtk-theme-name=Adwaita
gtk-application-prefer-dark-theme=true
`;

  await writeUserFile(`${HOME}/.config/gtk-3.0/settings.ini`, settings);
  await writeUserFile(`${HOME}/.config/gtk-4.0/settings.ini`, settings);
  say("wrote gtk-3.0 and gtk-4.0 settings.ini, dark");

  // Two keys, because the two toolkits read different things. GTK3's preference
  // is the settings.ini flag above. GTK4 and libadwaita take color-scheme, which
  // the portal serves to sandboxed apps as well.
  for (const [key, value] of [
    ["icon-theme", theme],
    ["color-scheme", "prefer-dark"],
  ] as const) {
    const result = await asUser(
      "gsettings", "set", "org.gnome.desktop.interface", key, value,
    ).nothrow().quiet();
    say(
      result.exitCode === 0
        ? `gsettings ${key} = ${value}`
        : `gsettings ${key} skipped (no session bus in chroot)`,
    );
  }
}

async function down(): Promise<void> {
  await needMount();
  await removeArch(`${HOME}/.config/gtk-3.0/settings.ini`);
  await removeArch(`${HOME}/.config/gtk-4.0/settings.ini`);
  await inArchSoft("pacman", "-Rns", "--noconfirm", THEME);
  say("removed icon settings and the theme package");
}

async function verify(): Promise<void> {
  const theme = await inArchSoft("sh", "-c", "ls -d /usr/share/icons/Tela-purple* 2>/dev/null | head -1");
  theme.stdout.toString().trim() !== "" ? ok("Tela purple icons installed") : fail("Tela purple icons missing");
  const gtk = (await readArch(`/home/${ARCH_USER}/.config/gtk-3.0/settings.ini`)) ?? "";
  gtk.includes("Tela") ? ok("GTK 3 names the Tela icons") : fail("GTK 3 settings do not name Tela");
}

await main({ up, down, verify });
