/**
 * ---
 * script: 120-quickshell.ts
 * desc: Installs the shell tree — the bar, the floats, the notification banners and the services under them — so `qs` draws it on every output.
 * needs: 50-user.ts up, 40-packages.ts up (quickshell), 110-niri.ts up (which spawns `qs -p` at startup)
 * up: writes every file under files/shell into /home/ARCH_USER/.config/shell, removes the old ~/.config/quickshell, and restarts the running shell against the new tree when the target is this system
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
 * `up` also restarts a running shell. Writing the files is not enough:
 * Quickshell does watch this directory, but that reload is soft and reuses the
 * windows already on screen, so a change to how many windows exist never shows
 * up. Starting `qs` again replaces the instance and recreates them. Only on the
 * live system: a chroot has no session to restart.
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
 * Returns false when there was nothing to restart, the start failed, or the old
 * process is still the only one — the caller then prints the manual command.
 */
async function restartShell(): Promise<boolean> {
  if (!LIVE) return false;

  const before = await $`pgrep -u ${ARCH_USER} -x qs`.nothrow().quiet();
  const oldPids = before.stdout.toString().trim().split("\n").filter((p) => p !== "");
  if (before.exitCode !== 0 || oldPids.length === 0) return false;

  // /proc/<pid>/environ is NUL-separated, and Bun's shell does not do `<`
  // redirection, so cat it and split on the separator.
  const environ = await $`cat /proc/${oldPids[0]}/environ`.nothrow().quiet();
  const keep = ["WAYLAND_DISPLAY", "XDG_RUNTIME_DIR", "DBUS_SESSION_BUS_ADDRESS", "XDG_CURRENT_DESKTOP"];
  const env: string[] = [];
  for (const line of environ.stdout.toString().split("\0")) {
    const eq = line.indexOf("=");
    if (eq > 0 && keep.includes(line.slice(0, eq))) env.push(line);
  }

  const started = await $`runuser -u ${ARCH_USER} -- env HOME=/home/${ARCH_USER} PATH=/usr/local/bin:/usr/bin ${env} qs -d -p ${DEST}`
    .nothrow().quiet();
  if (started.exitCode !== 0) {
    say("could not restart the shell; it will pick this up at the next login");
    process.stderr.write(started.stderr.toString());
    return false;
  }

  // Detached, so give it a moment to fail if it is going to, and require a
  // process that is not the old one: a failed start leaves the old shell up.
  await $`sleep 1`.quiet();
  const after = await $`pgrep -u ${ARCH_USER} -x qs`.nothrow().quiet();
  const newPids = after.stdout.toString().trim().split("\n").filter((p) => p !== "");
  if (!newPids.some((p) => !oldPids.includes(p))) {
    say("the shell did not come back as a new instance");
    return false;
  }
  say("restarted the shell against the new tree");
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
