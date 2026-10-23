/**
 * ---
 * script: 120-quickshell.ts
 * desc: Installs the starter quickshell config so `qs` opens a visible bar to develop against.
 * needs: 50-user.ts up, 40-packages.ts up (quickshell)
 * up: writes /home/ARCH_USER/.config/quickshell/shell.qml
 * down: removes the directory
 * revisit: 2026-12-21
 * ---
 */
import { ARCH_USER, main, needMount, removeArch, say, writeUserFile } from "./lib.ts";

const DEST = `/home/${ARCH_USER}/.config/quickshell/shell.qml`;

async function up(): Promise<void> {
  await needMount();
  const content = await Bun.file(`${import.meta.dir}/files/quickshell/shell.qml`).text();
  await writeUserFile(DEST, content);
  say(`installed ${DEST}`);
  say("starter: top bar with a clock. No workspaces, tray or lock screen.");
  say(`run it once the session is up: qs -p /home/${ARCH_USER}/.config/quickshell`);
}

async function down(): Promise<void> {
  await needMount();
  await removeArch(`/home/${ARCH_USER}/.config/quickshell`);
  say("removed quickshell config");
}

await main({ up, down });
