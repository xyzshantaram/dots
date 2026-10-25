/**
 * ---
 * script: 136-qt-theme.ts
 * desc: Puts Qt on the Breeze style with the Breeze-libadwaita dark colour scheme through qt6ct, so Qt applications match the dark GTK and libadwaita surfaces.
 * needs: 40-packages.ts up (qt6-base), 135-icons.ts up (it owns the icon theme name), 50-user.ts up
 * up: pacman-installs qt6ct and breeze, writes the vendored colour scheme, a qt6ct.conf pointing at it, the header stylesheet, and the environment.d snippet systemd user services read
 * down: removes qt6ct.conf, the colour scheme, the header stylesheet, the environment.d snippet and both packages
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
 * and it needs nothing but qt6ct. Their own install script only copies the
 * scheme into ~/.config/qt6ct/colors, so selecting it is still ours to do.
 *
 * The scheme is vendored rather than downloaded by the step. Five lines of
 * palette are worth having in the repository where they can be read and
 * diffed, not fetched at install time.
 *
 * style=Breeze, not Fusion: the scheme is a palette, not a widget style, and
 * the look upstream shows is Breeze's shapes wearing libadwaita's colours. The
 * Breeze style is a separate KDE plugin (the breeze package), and this step
 * installs it. That package brings KDE framework dependencies with it; the
 * lighter alternative is Fusion, which honours the palette but looks like
 * Fusion.
 *
 * custom_palette=true is what makes qt6ct apply the colour scheme. The name
 * reads backwards — false leaves Qt's default light palette while still naming
 * the scheme — and that one word is why Qt applications stayed white.
 *
 * The widget stylesheet covers what the palette cannot reach, with one vendored
 * rule each. Qt paints a QHeaderView section with QPalette::Button, the same
 * role as a push button, so lifting the palette until headers stand out lifts
 * every button with them. Breeze paints QMenuBar from its own light scheme
 * rather than the palette, so the bar stays light while the popup menus are
 * already dark.
 *
 * environment.d, not only niri's environment block: the block reaches what niri
 * spawns itself, and nothing else. The launcher (vicinae) is a systemd user
 * service, so applications started from it inherited no platform theme at all
 * and came up light while niri-spawned ones were dark. systemd reads
 * environment.d when the user manager starts, which is the level that reaches
 * vicinae and every other user service. The step writes the file but cannot
 * import it: a chroot has no user session to talk to, and the next login picks
 * it up.
 *
 * Qt5 is not installed on this machine — the Qt packages here are all qt6-* —
 * so there is no qt5ct half. If a Qt5 application ever appears it will be light
 * until one is added.
 */
import {
  ARCH_USER, existsInArch, fail, inArch, inArchSoft, main, needMount, ok, readArch,
  removeArch, say, writeUserFile,
} from "./lib.ts";

const HOME = `/home/${ARCH_USER}`;
const QT6CT = `${HOME}/.config/qt6ct`;
const SCHEME = `${QT6CT}/colors/breeze_libadwaita_dark.conf`;
const CONF = `${QT6CT}/qt6ct.conf`;
const QSS = `${QT6CT}/qss/qt-widgets.qss`;
const ENV = `${HOME}/.config/environment.d/10-qt.conf`;

/** qt6ct, and the KDE package that carries the Breeze style plugin. */
const PKGS = ["qt6ct", "breeze"];

async function up(): Promise<void> {
  await needMount();

  const installed = await inArch(
    "pacman", "-S", "--needed", "--noconfirm", ...PKGS,
  ).nothrow();
  if (installed.exitCode !== 0) {
    say(`could not install ${PKGS.join(" ")}; see above`);
    return;
  }
  say(`installed ${PKGS.join(" ")}`);

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
style=Breeze
color_scheme_path=${SCHEME}
custom_palette=true
${icon ? `icon_theme=${icon}\n` : ""}[Interface]
stylesheets=${QSS}
`,
  );
  say(`wrote ${CONF}${icon ? ` with icon theme ${icon}` : ""}`);

  await writeUserFile(
    QSS,
    await Bun.file(`${import.meta.dir}/files/theme/qt-widgets.qss`).text(),
  );
  say(`wrote ${QSS}`);

  await writeUserFile(
    ENV,
    `# Qt applications started by systemd user services — vicinae and everything
# it launches — need the platform theme too. niri's environment block only
# reaches what niri spawns itself.
QT_QPA_PLATFORMTHEME=qt6ct
`,
  );
  say(`wrote ${ENV}`);
  say("QT_QPA_PLATFORMTHEME=qt6ct is set in the niri environment block and in environment.d");
  say("Qt apps started before that landed keep the old palette until they restart");
}

async function down(): Promise<void> {
  await needMount();

  await removeArch(CONF);
  await removeArch(SCHEME);
  await removeArch(QSS);
  await removeArch(ENV);
  await inArchSoft("pacman", "-Rns", "--noconfirm", ...PKGS);
  say(`removed ${PKGS.join(" ")}, their config and the colour scheme`);
}

async function verify(): Promise<void> {
  (await existsInArch("/usr/lib/qt6/plugins/platformthemes/libqt6ct.so"))
    ? ok("qt6ct installed") : fail("qt6ct plugin missing");
  (await existsInArch("/usr/lib/qt6/plugins/styles/breeze6.so"))
    ? ok("Breeze style installed") : fail("Breeze style plugin missing");
  const conf = (await readArch(`/home/${ARCH_USER}/.config/qt6ct/qt6ct.conf`)) ?? "";
  conf.includes("breeze_libadwaita_dark")
    ? ok("qt6ct points at the Breeze scheme") : fail("qt6ct.conf does not name the scheme");
  conf.includes("custom_palette=true")
    ? ok("qt6ct applies the scheme palette") : fail("qt6ct.conf does not enable the scheme palette");
  conf.includes("style=Breeze")
    ? ok("qt6ct uses the Breeze style") : fail("qt6ct.conf does not select the Breeze style");
  (await existsInArch(QSS))
    ? ok("header stylesheet installed") : fail("header stylesheet missing");
  conf.includes(`stylesheets=${QSS}`)
    ? ok("qt6ct loads the header stylesheet") : fail("qt6ct.conf does not load the header stylesheet");
  const niri = (await readArch(`/home/${ARCH_USER}/.config/niri/config.kdl`)) ?? "";
  niri.includes("QT_QPA_PLATFORMTHEME")
    ? ok("niri exports QT_QPA_PLATFORMTHEME") : fail("niri does not export QT_QPA_PLATFORMTHEME");
  const env = (await readArch(`/home/${ARCH_USER}/.config/environment.d/10-qt.conf`)) ?? "";
  env.includes("QT_QPA_PLATFORMTHEME=qt6ct")
    ? ok("environment.d exports the platform theme to user services")
    : fail("environment.d does not export QT_QPA_PLATFORMTHEME");
}

await main({ up, down, verify });
