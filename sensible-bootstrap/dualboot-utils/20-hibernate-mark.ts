/**
 * ---
 * script: hibernate-mark.ts
 * desc: Installs hibernate-mark on both installed systems, so either can show "(HIBERNATED)" in the boot menu and set itself as the one-shot default, plus the sleep hook that drops the shared ESP before the image is written.
 * needs: ../145-hibernate.ts up, ../150-kernel-sync.ts up
 * up: target and host each get hibernate-mark, the boot-time clear service on this side, and a pre-hibernate sleep hook
 * down: removes everything it added on both sides and clears any marker left behind
 * revisit: 2026-12-21
 * ---
 *
 * Only worth having when two installed systems share a swap partition. Whoever
 * hibernates owns that partition, and booting the other one starts its swap
 * unit and discards the image. That is not corruption, but the hibernated
 * session is gone.
 *
 * hibernate-mark is OS-aware: it reads /etc/os-release, finds the ESP at /efi
 * or /boot/efi, and touches only its own loader entries. Each OS owns its own
 * entries, which is why one script serves both sides instead of two variants.
 *
 * bootctl set-oneshot makes the hibernated entry the default for exactly one
 * boot, then self-clears through an EFI variable. That is what actually steers
 * the choice; the title is only a sign, not a lock.
 *
 * Clearing happens twice on this side on purpose: the post-sleep hook covers a
 * resume, which does not re-run boot units, and hibernate-mark-clear.service
 * covers a normal boot after an interrupted hibernation.
 */
import { $ } from "bun";
import process from "node:process";
import {
  inArchSoft, main, needMount, removeArch, say, writeArch,
} from "../lib.ts";

const FILES = `${import.meta.dir}/files`;
const MARKER = `${FILES}/marker/hibernate-mark`;
const CLEAR_UNIT = `${FILES}/marker/hibernate-mark-clear.service`;
const HOOK = `${FILES}/sleep/90-pre-hibernate.sh`;

const TARGET_HOOK = "/usr/lib/systemd/system-sleep/90-pre-hibernate.sh";

/** Paths on the machine running the ladder, not inside the target. */
const HOST_BIN = "/usr/local/bin/hibernate-mark";
const HOST_HOOK = "/usr/lib/systemd/system-sleep/90-pre-hibernate.sh";

async function up(): Promise<void> {
  await needMount();

  await writeArch("/usr/local/bin/hibernate-mark", await Bun.file(MARKER).text(), 0o755);
  await writeArch(
    "/etc/systemd/system/hibernate-mark-clear.service",
    await Bun.file(CLEAR_UNIT).text(),
  );
  await writeArch(TARGET_HOOK, await Bun.file(HOOK).text(), 0o755);
  await inArchSoft("systemctl", "enable", "hibernate-mark-clear.service");
  say("installed hibernate-mark, the clear service and the sleep hook in the target");

  for (const [label, path] of [
    ["hibernate-mark", "/usr/local/bin/hibernate-mark"],
    ["sleep hook", TARGET_HOOK],
  ] as const) {
    const check = await inArchSoft("bash", "-n", path);
    if (check.exitCode !== 0) {
      say(`${label} has a syntax error`);
      process.stderr.write(check.stderr.toString());
      process.exit(1);
    }
  }
  say("target copies parse");

  await installHost();

  say("mark: own entry title, one-shot default, shared mounts left alone");
  say("clear: every entry title cleaned, ESP remounted post-resume");
}

/**
 * Installs the same script on the machine running the ladder.
 *
 * The host half is skipped when this is not the other OS's home: there is no
 * second side to label. It also backs up anything it
 * replaces, and skips the backup when one already exists, so a second `up`
 * cannot overwrite the original with our own copy.
 */
async function installHost(): Promise<void> {
  for (const path of [HOST_BIN, HOST_HOOK]) {
    if (!(await Bun.file(path).exists())) continue;
    if (await Bun.file(`${path}.sensible-bootstrap-save`).exists()) continue;
    await $`cp -a ${path} ${`${path}.sensible-bootstrap-save`}`.quiet();
    say(`backed up ${path}`);
  }

  await $`install -Dm755 ${MARKER} ${HOST_BIN}`;
  await $`install -Dm755 ${HOOK} ${HOST_HOOK}`;
  say(`installed ${HOST_BIN} and ${HOST_HOOK} on this machine`);

  const check = await $`bash -n ${HOST_BIN}`.nothrow().quiet();
  if (check.exitCode !== 0) {
    say("the host-side hibernate-mark does not parse");
    process.exit(1);
  }
  const show = await $`${HOST_BIN} show`.nothrow().quiet();
  if (show.exitCode === 0) {
    say("host-side detection:");
    process.stderr.write(show.stdout.toString());
  } else {
    say("hibernate-mark found no ESP here; check findmnt /efi");
  }
}

async function removeHost(): Promise<void> {
  for (const path of [HOST_HOOK, HOST_BIN]) {
    const backup = `${path}.sensible-bootstrap-save`;
    if (await Bun.file(backup).exists()) {
      await $`mv -f ${backup} ${path}`.quiet();
      say(`restored ${path} from backup`);
    } else if (await Bun.file(path).exists()) {
      await $`rm -f ${path}`.quiet();
      say(`removed ${path}`);
    }
  }
}

async function down(): Promise<void> {
  await needMount();

  await inArchSoft("/usr/local/bin/hibernate-mark", "clear");
  await inArchSoft("systemctl", "disable", "hibernate-mark-clear.service");
  await removeArch("/etc/systemd/system/hibernate-mark-clear.service");
  await removeArch("/usr/local/bin/hibernate-mark");
  await removeArch(TARGET_HOOK);
  say("removed the target-side files");

  await removeHost();
  say("done");
}

await main({ up, down });
