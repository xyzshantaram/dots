/**
 * ---
 * script: 120-quickshell.ts
 * desc: Installs the shell tree — the bar, the floats, the notification banners and the services under them — so `qs` draws it on every output.
 * needs: 50-user.ts up, 40-packages.ts up (quickshell), 110-niri.ts up (which spawns `qs -p` at startup)
 * up: writes every file under files/shell into /home/ARCH_USER/.config/shell, and removes the old ~/.config/quickshell
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
 */
import { readdir } from "node:fs/promises";
import { join, relative } from "node:path";
import {
  ARCH_USER, inArchSoft, main, needMount, removeArch, say, writeArch, writeUserFile,
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
  say(`to draw it now, without logging out: qs -p ${DEST}`);
}

async function down(): Promise<void> {
  await needMount();

  await removeArch(DEST);
  await removeArch("/etc/pam.d/qslock");
  say("removed the quickshell config");
}

await main({ up, down });
