/**
 * ---
 * script: 136-qt-theme.ts
 * desc: Gives Qt the Breeze-libadwaita dark colour scheme through qt6ct, so Qt applications match the dark GTK and libadwaita surfaces.
 * needs: 40-packages.ts up (qt6-base), 135-icons.ts up (it owns the icon theme name), 50-user.ts up
 * up: pacman-installs qt6ct, writes the vendored colour scheme and a qt6ct.conf pointing at it
 * down: removes qt6ct.conf, the colour scheme and the package
 * revisit: 2026-12-21
 * ---
 *
 * The scheme is vizenc/breeze-libadwaita, qtct variant: Breeze's dark surfaces
 * with libadwaita's blue accent (#3584e4), which is what makes a Qt app sit
 * next to a GTK one without looking like two different desktops.
 *
 * Their README's main path is the KDE one and needs plasma-workspace and
 * systemsettings to apply a .colors file — a whole KDE desktop to colour a
 * handful of Qt apps. The repo ships the qt6ct variant for exactly this case,
 * and it needs nothing but qt6ct.
 *
 * The scheme is vendored rather than downloaded by the step. Their own install
 * script curls it from GitHub, and five lines of palette are worth having in the
 * repository where they can be read and diffed, not fetched at install time.
 *
 * style=Fusion, not Breeze: the Breeze *style* is a separate KDE plugin (the
 * breeze package), and the colours are the part that matters. Fusion honours a
 * colour scheme on its own.
 *
 * Qt5 is not installed on this machine — the Qt packages here are all qt6-* —
 * so there is no qt5ct half. If a Qt5 application ever appears it will be light
 * until one is added.
 */
import {
  ARCH_USER, inArch, inArchSoft, main, needMount, removeArch, say, writeUserFile,
} from "./lib.ts";

const HOME = `/home/${ARCH_USER}`;
const QT6CT = `${HOME}/.config/qt6ct`;
const SCHEME = `${QT6CT}/colors/breeze_libadwaita_dark.conf`;
const CONF = `${QT6CT}/qt6ct.conf`;

async function up(): Promise<void> {
  await needMount();

  const installed = await inArch(
    "pacman", "-S", "--needed", "--noconfirm", "qt6ct",
  ).nothrow();
  if (installed.exitCode !== 0) {
    say("could not install qt6ct; see above");
    return;
  }
  say("installed qt6ct");

  await writeUserFile(
    SCHEME,
    await Bun.file(`${import.meta.dir}/files/theme/breeze_libadwaita_dark.conf`).text(),
  );

  // The palette is verified by shape rather than by size: a scheme that lost its
  // active_colors line would still be a valid file and a silently light desktop.
  const palette = await inArchSoft("grep", "-c", "^active_colors=", SCHEME);
  if (palette.exitCode !== 0) {
    say(`${SCHEME} has no active_colors line`);
    return;
  }
  say(`wrote ${SCHEME}`);

  // Read from what 135-icons actually installed rather than hardcoding it, so
  // the two steps cannot end up naming different directories.
  const icons = await inArchSoft("ls", "-1", "/usr/share/icons");
  const icon = icons.stdout.toString().split("\n").find((d) => /^tela.*purple/i.test(d));

  await writeUserFile(
    CONF,
    `[Appearance]
style=Fusion
color_scheme_path=${SCHEME}
custom_palette=false
${icon ? `icon_theme=${icon}\n` : ""}`,
  );
  say(`wrote ${CONF}${icon ? ` with icon theme ${icon}` : ""}`);
  say("QT_QPA_PLATFORMTHEME=qt6ct is set in the niri environment block");
  say("Qt apps started before that landed keep the old palette until they restart");
}

async function down(): Promise<void> {
  await needMount();

  await removeArch(CONF);
  await removeArch(SCHEME);
  await inArchSoft("pacman", "-Rns", "--noconfirm", "qt6ct");
  say("removed qt6ct, its config and the colour scheme");
}

await main({ up, down });
