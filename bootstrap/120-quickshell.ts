/**
 * ---
 * script: 120-quickshell.ts
 * desc: Installs the quickshell config — the bar, and everything it grows into — so `qs` draws it on every output.
 * needs: 50-user.ts up, 40-packages.ts up (quickshell), 110-niri.ts up (which spawns `qs` at startup)
 * up: writes every file under files/quickshell into /home/ARCH_USER/.config/quickshell
 * down: removes the directory
 * revisit: 2026-12-21
 * ---
 *
 * The config is a tree, not one file: shell.qml, the components beside it, and
 * the singletons under services/. Each file is written through writeUserFile
 * rather than copied, because in target mode the repo is not visible from
 * inside the chroot — only the host can read it, and every write has to reach
 * through at() to the target root.
 *
 * The layout is flat at the root on purpose. QML resolves a component by
 * filename within its own directory, and a qmldir turns that directory into a
 * module, where only the types it lists are visible — so a bar/ subdirectory
 * would mean imports and a second qmldir to keep in step. services/ is the one
 * subdirectory, and the files here import it by name.
 */
import { readdir } from "node:fs/promises";
import { join, relative } from "node:path";
import { ARCH_USER, main, needMount, removeArch, say, writeUserFile } from "./lib.ts";

const SRC = `${import.meta.dir}/files/quickshell`;
const DEST = `/home/${ARCH_USER}/.config/quickshell`;

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

  say("110-niri.ts spawns `qs` at startup, which reads this directory");
  say(`to draw it now, without logging out: qs -p ${DEST}`);

  // The shell watches this file to know when to restart the evening clock
  // tint, and it has to exist before it can be watched. `bun
  // reset-clock-tint` is what touches it afterwards.
  await writeUserFile(`/home/${ARCH_USER}/.cache/dots/clock-tint-reset`, "");
  say("seeded the clock tint reset file");
}

async function down(): Promise<void> {
  await needMount();

  await removeArch(DEST);
  say("removed the quickshell config");
}

await main({ up, down });
