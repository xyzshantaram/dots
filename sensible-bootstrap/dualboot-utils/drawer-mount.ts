/**
 * ---
 * script: drawer-mount.ts
 * desc: Mounts another installed OS's home read-only, as a drawer to read files out of, and installs the systemd service that opens a temporary read-write window.
 * needs: ../10-mount.ts up, DRAWER_UUID and DRAWER_USER in .env
 * up: appends an fstab entry (ro, nofail, automount, idle timeout), mounts it, installs drawer-rw.service
 * down: restores fstab from its backup, unmounts, removes the mountpoint and the unit
 * revisit: 2026-12-21
 * ---
 *
 * "Drawer" rather than anything OS-named: it is any home partition belonging to
 * another install, mounted read-only so its files can be read from this side.
 * Nothing in the base ladder depends on it, and a single-boot machine simply
 * leaves DRAWER_UUID unset.
 *
 * Read-only on purpose. Writes would be recorded as the other OS's user — ext4
 * stores the owner as a number, and the numbers usually collide at 1000 — so
 * anything created here could confuse what that OS thinks it owns. The
 * read-write window is a separate, expiring action:
 *
 *   systemctl start drawer-rw     rw now, back to ro in 10 minutes
 *   systemctl stop drawer-rw      ro now
 *   systemctl status drawer-rw    how long is left
 *
 * The swap caveat is the one that bites: never mount the other OS's filesystem
 * read-write while it is hibernated. drawer-rw.service checks hibernate-mark
 * before it will flip anything, so this is enforced rather than remembered.
 */
import { $ } from "bun";
import process from "node:process";
import {
  ROOT_MNT, backupOnce, isMounted, main, needMount, opt, readArch, restoreBackup,
  say, writeArch,
} from "../lib.ts";

const FSTAB = "/etc/fstab";
const SERVICE = "/etc/systemd/system/drawer-rw.service";

/**
 * Read from the environment, not lib.ts: the base ladder must run without any
 * of these set, so a missing value has to say "skipped" rather than exit.
 */
function drawer(): { uuid: string; mount: string; user: string } | null {
  const uuid = opt("DRAWER_UUID");
  const user = opt("DRAWER_USER");
  const mount = opt("DRAWER_MOUNT") ?? "/mnt/drawer";
  if (!uuid || !user) {
    say("DRAWER_UUID / DRAWER_USER unset; nothing to mount");
    say("set them in .env to open a drawer onto another OS's home");
    return null;
  }
  return { uuid, mount, user };
}

async function installService(mount: string): Promise<void> {
  // The unit ships pointing at the default drawer path; rewrite only the lines
  // that name it, so the rest of the file stays exactly as vendored.
  const unit = (await Bun.file(`${import.meta.dir}/files/systemd/drawer-rw.service`).text())
    .replaceAll("/mnt/drawer", mount);

  await writeArch(SERVICE, unit);
  say(`installed ${SERVICE} for ${mount}`);
  say("start a window with: systemctl start drawer-rw");
  say("it returns to read-only after 10 minutes, or now: systemctl stop drawer-rw");
}

async function up(): Promise<void> {
  const config = drawer();
  if (config === null) return;
  const { uuid, mount, user } = config;

  await needMount();
  await backupOnce(FSTAB, ".drawer-save");

  const LINE =
    `UUID=${uuid} ${mount} ext4 ro,nofail,x-systemd.automount,x-systemd.idle-timeout=10min 0 0`;

  const current = (await readArch(FSTAB)) ?? "";
  if (current.split("\n").some((l) => l.includes(mount))) {
    say("fstab already has the drawer entry");
  } else {
    const body = current.endsWith("\n") ? `${current}${LINE}\n` : `${current}\n${LINE}\n`;
    await writeArch(FSTAB, body);
    say("added fstab entry (ro, automount, 10 min idle timeout)");
  }

  await $`mkdir -p ${mount}`;
  if (!(await isMounted(mount))) {
    // Mount by device, not by a bare mountpoint. The fstab entry written just
    // above belongs to the target; `mount /mnt/drawer` resolves through the
    // fstab of the machine running this, which has never heard of it and says
    // exactly that:
    //
    //   mount: /mnt/drawer: can't find in /etc/fstab.
    const mounted = await $`mount /dev/disk/by-uuid/${uuid} -o ro ${mount}`.nothrow();
    if (mounted.exitCode !== 0) {
      say("mount failed; the target's fstab entry is in place, so the target mounts it at its own boot");
      process.stderr.write(mounted.stderr.toString());
      process.exit(1);
    }
  }
  say((await $`findmnt -rno TARGET,SOURCE,OPTIONS ${mount}`.text()).trim());
  say(`read from it with: rsync -a ${mount}/${user}/<path> ~/`);

  await installService(mount);
  say("never edit in place; the drawer is read-only until you start a window");
}

async function down(): Promise<void> {
  const config = drawer();
  if (config === null) return;
  const { mount } = config;

  if (await isMounted(mount)) {
    await $`umount ${mount}`;
    say("unmounted");
  }
  await needMount();
  await removeService();
  say(
    (await restoreBackup(FSTAB, ".drawer-save"))
      ? "fstab restored"
      : "no fstab backup; remove the entry by hand if present",
  );
  // The mountpoint is on the host, not inside the target, so it is removed
  // here. rmdir, not rm -rf, and only if empty, so a failed unmount can never
  // take data with it.
  await $`rmdir ${mount}`.nothrow().quiet();
  say("done");
}

async function removeService(): Promise<void> {
  await $`rm -f ${`${ROOT_MNT}${SERVICE}`}`.nothrow().quiet();
  say(`removed ${SERVICE}`);
}

await main({ up, down });
