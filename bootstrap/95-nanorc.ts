/**
 * ---
 * script: 95-nanorc.ts
 * desc: Installs the system-wide nano config at /etc/nanorc.
 * needs: 40-packages.ts up (nano)
 * up: writes /etc/nanorc from files/nanorc, retargeted at this account, and makes sure the backup directory it names exists
 * down: restores the original /etc/nanorc, or removes it if there was none
 * revisit: 2026-12-21
 * ---
 *
 * The vendored copy was taken from the Fedora side and still names /home/sid in
 * `set backupdir`; the path is retargeted at install time, the same way
 * 170-dictation.ts retargets its desktop entry, rather than kept as a
 * per-machine literal in the repo.
 */
import process from "node:process";
import {
  ARCH_USER, asUser, backupOnce, main, needMount, readArch, removeArch,
  restoreBackup, say, writeArch,
} from "./lib.ts";

const CONF = "/etc/nanorc";
const BACKUP_DIR = `/home/${ARCH_USER}/.cache/nano`;

async function up(): Promise<void> {
  await needMount();
  await backupOnce(CONF, ".nanorc-save");

  const vendored = await Bun.file(`${import.meta.dir}/files/nanorc`).text();
  await writeArch(CONF, vendored.replaceAll("/home/sid", `/home/${ARCH_USER}`));
  say(`installed ${CONF}`);

  // nano does not create `set backupdir` for itself, so a missing directory is
  // a failure every time a file is saved with a backup. Created as the account,
  // not as root, so it does not end up owned by root.
  await asUser("mkdir", "-p", BACKUP_DIR);
  say(`ensured ${BACKUP_DIR} exists`);

  const written = (await readArch(CONF)) ?? "";
  if (!written.includes(`/home/${ARCH_USER}/.cache/nano`)) {
    say("could not retarget the backup dir in the vendored nanorc");
    process.exit(1);
  }
  say("backup dir retargeted at this account");
}

async function down(): Promise<void> {
  await needMount();
  if (await restoreBackup(CONF, ".nanorc-save")) {
    say(`restored the original ${CONF}`);
  } else {
    await removeArch(CONF);
    say(`removed ${CONF} (there was no original to restore)`);
  }
}

await main({ up, down });
