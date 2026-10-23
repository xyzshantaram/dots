/**
 * ---
 * script: 70-keyd.ts
 * desc: Installs the keyd config (CapsLock as Meta, Copilot key as Pause) and enables keyd.
 * needs: 40-packages.ts up
 * up: writes /etc/keyd/default.conf from files/keyd/default.conf, enables keyd.service, reloads if running
 * down: stops and disables keyd, removes the config
 * revisit: 2026-12-21
 * ---
 */
import process from "node:process";
import {
  backupOnce, inArch, inArchSoft, main, needMount, readArch, removeArch,
  restoreBackup, say, writeArch,
} from "./lib.ts";

const CONF = "/etc/keyd/default.conf";
const VENDORED = `${import.meta.dir}/files/keyd/default.conf`;

async function up(): Promise<void> {
  await needMount();
  await backupOnce(CONF, ".keyd-save");

  const content = await Bun.file(VENDORED).text();
  if (!content.includes("[ids]")) {
    say(`vendored config at ${VENDORED} does not look like keyd config`);
    process.exit(1);
  }

  await writeArch(CONF, content);
  say(`installed ${CONF}`);

  await inArch("systemctl", "enable", "keyd.service");
  say("keyd enabled");

  const reload = await inArchSoft("systemctl", "reload", "keyd.service");
  say(reload.exitCode === 0 ? "keyd reloaded" : "keyd reload skipped (not running in this chroot)");

  if (await readArch(CONF)) say("config verified readable");
}

async function down(): Promise<void> {
  await needMount();
  await inArchSoft("systemctl", "disable", "--now", "keyd.service");

  if (await restoreBackup(CONF, ".keyd-save")) {
    say("restored the original keyd config");
  } else {
    await removeArch(CONF);
    say("removed keyd config (there was no original to restore)");
  }
  await removeArch(`${CONF}.bak`);
}

await main({ up, down });
