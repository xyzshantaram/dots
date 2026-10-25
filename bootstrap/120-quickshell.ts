/**
 * ---
 * script: 120-quickshell.ts
 * desc: Installs the shell tree — the bar, the floats, the notification banners and the services under them — so `qs` draws it on every output.
 * needs: 50-user.ts up, 40-packages.ts up (quickshell), 110-niri.ts up (which spawns `qs -p` at startup)
 * up: writes every file under files/shell into /home/ARCH_USER/.config/shell, removes the old ~/.config/quickshell, and starts or restarts the shell through niri when the target is this system
 * down: removes the directory
 * revisit: 2026-12-21
 * ---
 *
 * The config is a tree, not one file: shell.qml at the root, the bar under bar/,
 * the floats under float/, the notification banners under notices/, and the
 * singletons under core/ and services/. Each file is written through
 * writeUserFile rather than copied, because in target mode the repo is not
 * visible from inside the chroot — only the host can read it, and every write
 * has to reach through at() to the target root.
 *
 * Every subdirectory carries its own qmldir, because QML resolves a component by
 * filename within its own directory and a qmldir turns a directory into a
 * module. The root is deliberately not a module: shell.qml reaches Shell.qml by
 * filename, and one root qmldir listing every bar and float would go stale the
 * first time somebody added one without listing it — which is how Bar itself
 * once went missing from bar/qmldir.
 *
 * `up` also deletes the old ~/.config/quickshell. That tree was the entire bar
 * before the move, and a bare `qs` with no -p reads it. That is exactly how a
 * session ended up drawing the old bar, which has no click-catcher, and then
 * could not close the control centre from an outside click. Leaving a second
 * config where a bare `qs` will find it is a trap, so this removes it instead of
 * tolerating it.
 *
 * `up` also starts or restarts a running shell. Writing the files is not enough:
 * Quickshell does watch this directory, but that reload is soft and reuses the
 * windows already on screen, so a change to how many windows exist never shows
 * up. Starting `qs` again replaces the instance and recreates them, through
 * niri so the new process keeps the session scope the fingerprint prompt needs.
 * Starting one when none is running is the same path, which is also how a shell
 * that was killed comes back. Only on the live system: a chroot has no session.
 */
import { $ } from "bun";
import process from "node:process";
import { readdir } from "node:fs/promises";
import { join, relative } from "node:path";
import {
  ARCH_USER, LIVE, existsInArch, fail, inArchSoft, main, needMount, ok, removeArch, say,
  writeArch, writeUserFile,
} from "./lib.ts";

const SRC = `${import.meta.dir}/files/shell`;
const DEST = `/home/${ARCH_USER}/.config/shell`;

/** The tree DEST replaced. Removed on `up`, never written. */
const LEGACY = `/home/${ARCH_USER}/.config/quickshell`;

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

/**
 * Replaces the running shell with the tree just written.
 *
 * The session variables are read from the shell that is already running,
 * because this step runs as root under sudo, which does not carry
 * WAYLAND_DISPLAY or XDG_RUNTIME_DIR.
 *
 * The restart goes through niri's spawn action rather than starting `qs`
 * directly. A process started from this sudo session lands in the terminal's
 * logind session, which sits in "closing" once runuser has returned; polkit
 * then treats it as inactive and pam_fprintd is refused
 * net.reactivated.fprint.device.verify, so fingerprint unlock silently stops
 * working. niri's children run in niri.service, the same place the shell it
 * replaced came from.
 *
 * Returns false when there was nothing to restart, the start failed, or the old
 * process is still the only one — the caller then prints the manual command.
 */
async function restartShell(): Promise<boolean> {
  if (!LIVE) return false;

  const niri = await $`pgrep -u ${ARCH_USER} -x niri`.nothrow().quiet();
  const niriPid = niri.stdout.toString().trim().split("\n").filter((p) => p !== "")[0];
  if (!niriPid) {
    say("niri is not running; the shell will start at the next login");
    return false;
  }

  const running = await $`pgrep -u ${ARCH_USER} -x qs`.nothrow().quiet();
  const oldPids = running.stdout.toString().trim().split("\n").filter((p) => p !== "");

  // niri owns the session, so its environ has the runtime dir and the bus.
  // /proc/<pid>/environ is NUL-separated, and Bun's shell does not do `<`
  // redirection, so cat it and split on the separator.
  const environ = await $`cat /proc/${niriPid}/environ`.nothrow().quiet();
  const keep = ["WAYLAND_DISPLAY", "XDG_RUNTIME_DIR", "DBUS_SESSION_BUS_ADDRESS", "XDG_CURRENT_DESKTOP", "NIRI_SOCKET"];
  const env: string[] = [];
  for (const line of environ.stdout.toString().split("\0")) {
    const eq = line.indexOf("=");
    if (eq > 0 && keep.includes(line.slice(0, eq))) env.push(line);
  }

  // niri does not export NIRI_SOCKET to its own children, so `niri msg` cannot
  // find the socket on its own. The socket is named after the niri pid in the
  // runtime directory; one session has one, so the first match is the one.
  const runtime = env.find((e) => e.startsWith("XDG_RUNTIME_DIR="))?.slice("XDG_RUNTIME_DIR=".length);
  let socket = env.find((e) => e.startsWith("NIRI_SOCKET="))?.slice("NIRI_SOCKET=".length);
  if (!socket && runtime) {
    const found = await $`ls ${runtime}/niri.wayland-*.sock`.nothrow().quiet();
    socket = found.stdout.toString().trim().split("\n").filter((p) => p !== "")[0];
  }
  if (!socket) {
    say("no niri socket found; the shell will start at the next login");
    return false;
  }
  const niriEnv = env.filter((e) => !e.startsWith("NIRI_SOCKET="));
  niriEnv.push(`NIRI_SOCKET=${socket}`);

  const started = await $`runuser -u ${ARCH_USER} -- env HOME=/home/${ARCH_USER} PATH=/usr/local/bin:/usr/bin ${niriEnv} niri msg action spawn -- qs -p ${DEST}`
    .nothrow().quiet();
  if (started.exitCode !== 0) {
    say("could not start the shell through niri; it will start at the next login");
    process.stderr.write(started.stderr.toString());
    return false;
  }

  // Detached, so give it a moment to fail if it is going to, and require a
  // process that is not one of the old ones: a failed start leaves the old
  // shell, if any, still up.
  await $`sleep 1`.quiet();
  const after = await $`pgrep -u ${ARCH_USER} -x qs`.nothrow().quiet();
  const nowPids = after.stdout.toString().trim().split("\n").filter((p) => p !== "");
  if (!nowPids.some((p) => !oldPids.includes(p))) {
    say("the shell did not come up as a new instance");
    return false;
  }
  say(oldPids.length === 0
    ? "started the shell"
    : "restarted the shell against the new tree");
  return true;
}

async function up(): Promise<void> {
  await needMount();

  const files = await walk(SRC);
  for (const file of files) {
    await writeUserFile(`${DEST}/${file}`, await Bun.file(join(SRC, file)).text());
  }
  say(`installed ${files.length} files into ${DEST}`);

  // The lock's PamContext names this service.
  await writeArch("/etc/pam.d/qslock", "auth include login\n");
  say("wrote /etc/pam.d/qslock");

  if ((await inArchSoft("test", "-d", LEGACY)).exitCode === 0) {
    await removeArch(LEGACY);
    say(`removed the old ${LEGACY}, so a bare \`qs\` cannot load it`);
  }

  say("110-niri.ts spawns `qs -p` at startup, which reads this directory");
  if (!(await restartShell())) {
    say(`to draw it now, without logging out: qs -p ${DEST}`);
  }
}

async function down(): Promise<void> {
  await needMount();

  await removeArch(DEST);
  await removeArch("/etc/pam.d/qslock");
  say("removed the quickshell config");
}

async function verify(): Promise<void> {
  for (const f of ["shell.qml", "Shell.qml", "services/Notifications.qml", "lock/Lock.qml", "lock/LockSurface.qml", "lock/LockService.qml"]) {
    const p = `/home/${ARCH_USER}/.config/shell/${f}`;
    (await existsInArch(p)) ? ok(`present: ${f}`) : fail(`missing: ${f}`);
  }
  (await existsInArch("/etc/pam.d/qslock"))
    ? ok("/etc/pam.d/qslock present") : fail("/etc/pam.d/qslock missing");
  (await existsInArch(`/home/${ARCH_USER}/.config/quickshell`))
    ? fail("the old ~/.config/quickshell is back") : ok("no legacy ~/.config/quickshell");
}

await main({ up, down, verify });
