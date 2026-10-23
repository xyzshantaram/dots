/**
 * ---
 * script: 117-greetd.ts
 * desc: Installs greetd with the tuigreet console greeter, so the login prompt is a TUI instead of a bare getty.
 * needs: 115-pam-fpr.ts up (so fingerprint works at the greeter)
 * up: installs greetd and greetd-tuigreet, writes /etc/greetd/config.toml, enables greetd.service
 * down: disables greetd, restores the shipped config, uninstalls both packages
 * revisit: 2026-12-21
 * ---
 *
 * FINGERPRINT COMES FOR FREE. Arch's greetd ships /etc/pam.d/greetd containing
 * `auth include system-local-login`, and 115-pam-fpr.ts already prepends
 * `auth sufficient pam_fprintd.so` to that file. So nothing here needs to touch
 * PAM, and adding a pam_fprintd line to /etc/pam.d/greetd would be a second
 * copy of the same rule.
 *
 * That is Arch-specific: Fedora's greetd instead does `auth substack
 * system-auth`, which does NOT route through system-local-login, so the same
 * setup would need its own patch there. Do not assume this transfers.
 *
 * POWER BUTTONS NEED A POLKIT RULE. The greeter runs as a system service with
 * no logind session, so polkit's defaults (which grant power actions to local
 * active-session users) never match it and tuigreet's F12 menu does nothing.
 * files/greetd/49-greeter-power.rules fixes that for the `greeter` account only.
 *
 * tuigreet is a console greeter, not a graphical one, so it needs no
 * compositor and no video group for the greeter user. greetd.service declares
 * `Conflicts=getty@tty1.service`, so it takes over tty1 on its own — there is
 * no getty to mask by hand. Console login still works on tty2 and up.
 *
 * The session list comes from /usr/share/wayland-sessions/, and the niri
 * package installs niri.desktop there with Exec=niri-session. `--cmd` below
 * only picks which one is preselected; F3 in tuigreet lists the rest.
 */
import process from "node:process";
import {
  at, inArch, inArchSoft, main, needMount, readArch, removeArch, say,
  writeArch,
} from "./lib.ts";

const CONF = "/etc/greetd/config.toml";
const SERVICE = "greetd.service";
/** Sort key matters: polkit takes the first matching rule, and 50-default is the system's. */
const POLKIT = "/etc/polkit-1/rules.d/49-greeter-power.rules";
const POLKIT_SRC = `${import.meta.dir}/files/greetd/49-greeter-power.rules`;

const PACKAGES = ["greetd", "greetd-tuigreet"];

/**
 * Greeter command. `greeter` is greetd's own user, created by the package;
 * tuigreet only needs to read /usr/share/wayland-sessions, which is world
 * readable.
 */
const CONFIG = `# Installed by bootstrap 117-greetd.ts.
#
# PAM is deliberately untouched: /etc/pam.d/greetd already does
# \`auth include system-local-login\`, and the fingerprint line lives there.

[terminal]
# The VT to run the greeter on. greetd.service declares
# Conflicts=getty@tty1.service, so the getty steps aside by itself.
vt = 1

[default_session]
# tuigreet lists sessions from /usr/share/wayland-sessions; the niri package
# installs niri.desktop there with Exec=niri-session.
command = "tuigreet --cmd niri-session"
user = "greeter"
`;

async function up(): Promise<void> {
  await needMount();

  const installed = await inArch("pacman", "-S", "--needed", "--noconfirm", ...PACKAGES)
    .nothrow();
  if (installed.exitCode !== 0) {
    say("installing greetd failed; see above");
    process.exit(installed.exitCode);
  }
  say(`installed ${PACKAGES.join(" ")}`);

  // Back up the shipped config once, so `down` restores what the package
  // intended rather than deleting the file the package owns.
  const shipped = at(CONF);
  if (!(await Bun.file(`${shipped}.greetd-save`).exists())) {
    await writeArch(`${CONF}.greetd-save`, (await readArch(CONF)) ?? "");
  }

  await writeArch(CONF, CONFIG);
  say(`wrote ${CONF}`);

  // Sanity: tuigreet is the thing the config names, and it must exist.
  const greeter = await inArchSoft("test", "-x", "/usr/bin/tuigreet");
  if (greeter.exitCode !== 0) {
    say("/usr/bin/tuigreet is missing after install");
    process.exit(1);
  }

  // The session it preselects has to exist too, or the greeter logs in to
  // nothing. niri provides this file.
  const session = await inArchSoft("test", "-f", "/usr/share/wayland-sessions/niri.desktop");
  if (session.exitCode !== 0) {
    say("no /usr/share/wayland-sessions/niri.desktop; the greeter would launch nothing");
    say("install niri first (40-packages.ts up)");
    process.exit(1);
  }
  say("tuigreet and the niri session are both present");

  await inArch("systemctl", "enable", SERVICE);
  say(`${SERVICE} enabled; it also claims the display-manager.service alias`);

  // Power menu. Without this the greeter has no logind session, so polkit
  // denies every power action and F12 silently does nothing.
  await writeArch(POLKIT, await Bun.file(POLKIT_SRC).text());
  say(`installed ${POLKIT} (greeter may power off, reboot, suspend, hibernate)`);
  const polkitOk = await inArchSoft("test", "-r", POLKIT);
  if (polkitOk.exitCode !== 0) {
    say("the polkit rule is not readable; the power menu will not work");
  }

  say("takes over tty1 on next boot; console login still works on tty2+");
  say("fingerprint is handled by system-local-login (115-pam-fpr.ts)");
}

async function down(): Promise<void> {
  await needMount();

  await inArchSoft("systemctl", "disable", SERVICE);
  say(`${SERVICE} disabled`);

  await removeArch(POLKIT);
  say("removed the greeter polkit rule");

  const restored = await Bun.file(at(`${CONF}.greetd-save`)).exists();
  if (restored) {
    await writeArch(CONF, (await readArch(`${CONF}.greetd-save`)) ?? "");
    await removeArch(`${CONF}.greetd-save`);
    say("restored the shipped greetd config");
  } else {
    await removeArch(CONF);
    say("removed the greetd config (no shipped copy to restore)");
  }

  await inArchSoft("pacman", "-Rns", "--noconfirm", ...PACKAGES);
  say(`removed ${PACKAGES.join(" ")}; tty1 login returns on next boot`);
}

await main({ up, down });
