/**
 * ---
 * script: 180-snapper.ts
 * desc: Mounts the @snapshots subvolume at /.snapshots, installs snapper with snap-pac, and takes one snapshot labelled as the end of the bootstrap.
 * needs: 10-mount.ts up, 40-packages.ts up, ARCH_UUID in .env, @snapshots created by hand
 * up: verifies @snapshots, adds the /.snapshots fstab entry, installs snapper and snap-pac, creates the root config against an absent /.snapshots, discards the subvolume create-config makes, mounts @snapshots in its place, tunes the config, then takes the post-bootstrap snapshot
 * down: deletes the snapper config, the fstab entry and the packages; snapshots are left on disk on purpose
 * revisit: 2026-12-21
 * ---
 *
 * Why @snapshots is a sibling subvolume rather than a directory: a snapshot
 * stored inside the subvolume it snapshots would be included in the next
 * snapshot, and each one would contain the previous. Mounting a sibling at
 * /.snapshots keeps them out of the tree being snapshotted.
 *
 * Order matters here, and not in the obvious direction. snapper's create-config
 * makes .snapshots itself, as a subvolume nested inside the one being
 * configured, and it does not tolerate anything already at that path: it fails
 * with errno 17 rather than reusing what it finds. So create-config has to run
 * against a /.snapshots that is absent, and the nested subvolume it leaves
 * behind is thrown away and replaced by the sibling @snapshots. Mounting
 * @snapshots first makes the whole step fail, which is how this was found.
 * ArchWiki, Snapper, "Configuration of snapper and mount point".
 *
 * snap-pac adds pre/post snapshots around every pacman transaction, which is
 * the point of having this at all: a bad upgrade becomes `snapper undochange`.
 * It is why an update no longer needs a manual snapshot first.
 *
 * Caveat worth knowing: rolling back / also rolls back /boot, while the ESP
 * keeps the newest kernel that esp-sync copied there. After a rollback, run
 * `esp-sync` by hand so the two agree again.
 */
import { $ } from "bun";
import process from "node:process";
import {
  ARCH_UUID, ROOT_MNT, at, fail, inArch, inArchSoft, isMounted, main, needMount, note,
  ok, readArch, say, writeArch,
} from "./lib.ts";

const FSTAB = "/etc/fstab";
const SNAP_DIR = "/.snapshots";
const SUBVOL = "@snapshots";
const MOUNT_AT = at(SNAP_DIR);
const LINE = `UUID=${ARCH_UUID} ${SNAP_DIR} btrfs subvol=${SUBVOL},noatime 0 0`;

const DESCRIPTION = "sensible-bootstrap complete";

async function subvolumeExists(): Promise<boolean> {
  const list = await $`btrfs subvolume list ${ROOT_MNT}`.nothrow().quiet();
  if (list.exitCode !== 0) {
    say(`btrfs subvolume list failed; is ${ROOT_MNT} a btrfs mount?`);
    process.exit(1);
  }
  return list.stdout
    .toString()
    .split("\n")
    .some((l) => l.trim().endsWith(`path ${SUBVOL}`));
}

/** Creates @snapshots from the btrfs top level, the only place it can be made. */
async function createSubvolume(): Promise<void> {
  const tmp = `/run/${SUBVOL}-create`;
  await $`mkdir -p ${tmp}`;
  const mounted = await $`mount -o subvolid=5 /dev/disk/by-uuid/${ARCH_UUID} ${tmp}`.nothrow();
  if (mounted.exitCode !== 0) {
    say("could not mount the btrfs top level to create the subvolume");
    process.stderr.write(mounted.stderr.toString());
    process.exit(1);
  }
  try {
    const created = await $`btrfs subvolume create ${`${tmp}/${SUBVOL}`}`.nothrow();
    if (created.exitCode !== 0) {
      say(`could not create ${SUBVOL}`);
      process.stderr.write(created.stderr.toString());
      process.exit(1);
    }
    say(`created subvolume ${SUBVOL}`);
  } finally {
    await $`umount ${tmp}`.nothrow().quiet();
    await $`rmdir ${tmp}`.nothrow().quiet();
  }
}

async function ensureFstab(): Promise<void> {
  const current = (await readArch(FSTAB)) ?? "";
  if (current.split("\n").some((l) => l.includes(SNAP_DIR))) {
    say(`${SNAP_DIR} already in fstab`);
    return;
  }
  const body = current.endsWith("\n") ? `${current}${LINE}\n` : `${current}\n${LINE}\n`;
  await writeArch(FSTAB, body);
  say(`added ${SNAP_DIR} to fstab (subvol=${SUBVOL})`);
}

/**
 * Puts /.snapshots into the state create-config requires, which is "absent".
 *
 * create-config builds the subvolume itself and will not reuse one it finds.
 * With a mount or even an empty directory in the way it fails with errno 17
 * (File exists). Unmounting is not enough - the directory has to go as well.
 */
async function clearSnapshotsPath(): Promise<void> {
  if (await isMounted(MOUNT_AT)) {
    await $`umount ${MOUNT_AT}`;
    say(`unmounted ${SNAP_DIR} for create-config`);
  }
  await $`rm -rf ${MOUNT_AT}`;
}

async function ensureMounted(): Promise<void> {
  await $`mkdir -p ${MOUNT_AT}`;
  if (await isMounted(MOUNT_AT)) {
    say(`${SNAP_DIR} already mounted`);
  } else {
    const mounted = await $`mount /dev/disk/by-uuid/${ARCH_UUID} -o subvol=${SUBVOL} ${MOUNT_AT}`.nothrow();
    if (mounted.exitCode !== 0) {
      say(`mounting ${SNAP_DIR} failed`);
      process.stderr.write(mounted.stderr.toString());
      process.exit(1);
    }
    say(`mounted ${SUBVOL} at ${SNAP_DIR}`);
  }
  // ArchWiki: "Give the folder 750 permissions." This is the root of
  // @snapshots while it is mounted, so it lands on the right thing.
  await $`chmod 750 ${MOUNT_AT}`;
}

/** Replaces whole KEY="value" lines, leaving the rest of the file intact. */
async function tune(key: string, value: string): Promise<void> {
  const path = "/etc/snapper/configs/root";
  const current = await readArch(path);
  if (current === null) {
    say(`${path} missing after create-config`);
    process.exit(1);
  }
  const line = `${key}="${value}"`;
  const lines = current.split("\n").map((l) => (l.startsWith(`${key}=`) ? line : l));
  if (!lines.some((l) => l.startsWith(`${key}=`))) lines.push(line);
  await writeArch(path, lines.join("\n"));
}

async function ensureConfig(): Promise<void> {
  if (await Bun.file(at("/etc/snapper/configs/root")).exists()) {
    say("snapper root config already exists");
  } else {
    await clearSnapshotsPath();

    // --no-dbus is required here, not cosmetic. snapper's CLI talks to
    // snapperd over the system bus for most operations, and a chroot has no
    // running D-Bus, so the default path fails with a connection error. The
    // man page documents the flag as "Operate without a DBus connection",
    // with the caveat that a running snapperd will not see the changes — which
    // is exactly right for building a system that is not booted yet.
    const created = await inArch(
      "snapper", "--no-dbus", "-c", "root", "create-config", "/",
    ).nothrow();
    if (created.exitCode !== 0) {
      say("snapper create-config failed");
      process.stderr.write(created.stderr.toString());
      process.exit(1);
    }

    // create-config has just made /.snapshots a subvolume nested inside @. The
    // layout this step wants has it as a sibling, so drop the throwaway and let
    // ensureMounted put @snapshots in its place. ArchWiki is explicit that the
    // nested one is not needed for this layout.
    const discarded = await $`btrfs subvolume delete ${MOUNT_AT}`.nothrow();
    say(
      discarded.exitCode === 0
        ? `discarded the nested .snapshots subvolume create-config made`
        : "create-config left no .snapshots subvolume to discard",
    );
    say("created the snapper root config");
  }

  // Hourly timeline snapshots are noise here. snap-pac covers upgrades, and a
  // named snapshot marks the milestones. The limits keep the 50 GiB root from
  // filling with snapshots.
  await tune("TIMELINE_CREATE", "no");
  await tune("NUMBER_LIMIT", "20");
  await tune("NUMBER_LIMIT_IMPORTANT", "10");
  await tune("SPACE_LIMIT", "0.5");
  await tune("FREE_LIMIT", "0.2");
  say("tuned: no timeline snapshots, number limit 20, space limit 50%");
}

/** True when a snapshot already carries this step's userdata marker. */
async function alreadySnapshotted(): Promise<boolean> {
  const found = await inArchSoft(
    "sh", "-c", `grep -l sensible-bootstrap ${SNAP_DIR}/*/info.xml 2>/dev/null | head -1`,
  );
  return found.exitCode === 0 && found.stdout.toString().trim() !== "";
}

async function ensureSnapshot(): Promise<void> {
  if (await alreadySnapshotted()) {
    say(`a "${DESCRIPTION}" snapshot already exists; not taking another`);
    return;
  }
  const created = await inArch(
    "snapper", "--no-dbus", "-c", "root", "create",
    "--description", DESCRIPTION,
    "--userdata", "sensible-bootstrap=1",
  ).nothrow();
  if (created.exitCode !== 0) {
    say("taking the snapshot failed");
    process.stderr.write(created.stderr.toString());
    process.exit(1);
  }
  say(`snapshot taken: ${created.stdout.toString().trim()}`);
}

/**
 * Collapses duplicate ${SNAP_DIR} lines in fstab down to the first.
 *
 * snapper's create-config creates the snapshots subvolume and adds its own
 * fstab entry when it does not find one. This step already owns that entry, so
 * the two can end up side by side. Duplicate mount points are not fatal —
 * systemd mounts the last one and warns — but they are a confusing thing to
 * find later, and this is the cheapest place to prevent it.
 *
 * Deliberately keeps the first line, which is ours: it carries `noatime`.
 */
async function normalizeFstab(): Promise<number> {
  const current = (await readArch(FSTAB)) ?? "";
  const lines = current.split("\n");
  let seen = false;
  const kept: string[] = [];
  let dropped = 0;

  for (const line of lines) {
    const isSnapshots = !line.trim().startsWith("#") &&
      line.split(/\s+/)[1] === SNAP_DIR;
    if (!isSnapshots) {
      kept.push(line);
      continue;
    }
    if (seen) {
      dropped++;
      continue;
    }
    seen = true;
    kept.push(line);
  }

  if (dropped > 0) await writeArch(FSTAB, kept.join("\n"));
  return dropped;
}

async function up(): Promise<void> {
  await needMount();

  if (!(await subvolumeExists())) {
    say(`${SUBVOL} does not exist; creating it`);
    await createSubvolume();
  } else {
    say(`subvolume ${SUBVOL} present`);
  }

  await ensureFstab();

  const installed = await inArch("pacman", "-S", "--needed", "--noconfirm", "snapper", "snap-pac")
    .nothrow();
  if (installed.exitCode !== 0) {
    say("installing snapper and snap-pac failed");
    process.exit(installed.exitCode);
  }
  say("snapper and snap-pac installed");

  // Before ensureMounted, not after: create-config needs /.snapshots to be
  // absent, and it discards whatever is there. Ours goes on afterwards.
  await ensureConfig();

  // create-config may have added its own snapshots entry; ours is already
  // there. Collapse duplicates before anything mounts from this fstab.
  const dupes = await normalizeFstab();
  if (dupes > 0) say(`removed ${dupes} duplicate ${SNAP_DIR} fstab line(s)`);

  await ensureMounted();

  await ensureSnapshot();

  say("from now on every pacman transaction gets pre/post snapshots");
}

async function down(): Promise<void> {
  await needMount();

  const deleted = await inArchSoft("snapper", "--no-dbus", "-c", "root", "delete-config");
  say(
    deleted.exitCode === 0
      ? "deleted the snapper root config"
      : "no snapper config to delete",
  );

  if (await isMounted(MOUNT_AT)) {
    await $`umount ${MOUNT_AT}`;
    say(`unmounted ${SNAP_DIR}`);
  }

  const current = (await readArch(FSTAB)) ?? "";
  const kept = current.split("\n").filter((l) => !l.includes(SNAP_DIR));
  if (kept.length !== current.split("\n").length) {
    await writeArch(FSTAB, kept.join("\n"));
    say(`removed the ${SNAP_DIR} fstab entry`);
  }

  await inArchSoft("pacman", "-Rns", "--noconfirm", "snap-pac", "snapper");
  say("removed snapper and snap-pac");

  // Snapshots are subvolumes holding real state. They are not deleted here on
  // purpose: deleting them is not reversible, and `down` should never quietly
  // destroy a rollback point.
  say(`the snapshots in ${SUBVOL} are still on disk; delete them by hand if wanted`);
  say(`e.g. mount subvol=${SUBVOL} and btrfs subvolume delete each one`);
}

async function verify(): Promise<void> {
  const fstab = (await readArch("/etc/fstab")) ?? "";
  fstab.includes("subvol=@snapshots")
    ? ok("fstab has the @snapshots entry") : fail("fstab has no @snapshots entry");
  const conf = (await readArch("/etc/snapper/configs/root")) ?? "";
  if (conf === "") {
    fail("no snapper root config");
    return;
  }
  ok("snapper root config present");
  /TIMELINE_CREATE="no"/.test(conf)
    ? ok("hourly timeline snapshots are off") : note("timeline snapshots are enabled");
}

await main({ up, down, verify });
