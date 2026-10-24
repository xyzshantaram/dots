/**
 * ---
 * script: 00-check.ts
 * desc: Read-only preflight. Asserts the assumptions every later step needs.
 * needs: root (to stat the block devices and to mount the probe)
 * up: verifies p5 is btrfs, the ESP is vfat, the UUIDs match .env, a kernel is installed in the target, and the ESP has room for two kernel sets. With TARGET as the running system it only checks the OS family and the host tools.
 * down: nothing; this step leaves no state behind
 * revisit: 2026-12-21
 * ---
 *
 * With ROOT_MNT=/ this step has almost nothing to check: there is no target to
 * mount, no pacstrap to wait for, and the root probe below would otherwise try
 * to mount / read-only. It reports the OS family and the host tools and stops.
 *
 * The target-root checks below read files inside ${ROOT_MNT}, but this step
 * runs before 10-mount.ts, so on a cold start that path is an empty directory
 * and every one of them fails for a reason that has nothing to do with the
 * machine. So the preflight mounts subvol=@ read-only itself, inspects it, and
 * unmounts before exiting.
 *
 * Anything already mounted is used where it is, and nothing is unmounted that
 * this step did not mount. That covers re-running after 10-mount.ts and running
 * from the booted system, and it is also what the ESP needs: it is vfat, and
 * mounting a vfat device a second time at another mountpoint is refused with
 * "already mounted on /boot/efi". On a Fedora host the ESP is always mounted,
 * so a probe that insisted on its own mountpoint could never work.
 *
 * The ESP is asked for free space through whichever mountpoint answers, rather
 * than by asking df about the block device. df resolves a device to wherever it
 * happens to be mounted, and fails outright when nothing has it mounted.
 */
import { $ } from "bun";
import { mkdtempSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import process from "node:process";
import {
  ARCH_UUID, ESP_UUID, KERNEL, LIVE, ROOT_MNT, SWAP_UUID, existsInArch, fail, main,
  note, ok, runningArch, say,
} from "./lib.ts";

/** The Arch root by UUID, which is how 10-mount.ts mounts it too. */
const ROOT_MNT_SOURCE = `/dev/disk/by-uuid/${ARCH_UUID}`;

const blkid = async (dev: string, field: string) =>
  (await $`blkid -s ${field} -o value ${dev}`.nothrow().quiet()).stdout.toString().trim();

async function up(): Promise<void> {
  let failures = 0;
  const ok = (msg: string) => console.log(`  ok    ${msg}`);
  const bad = (msg: string) => { console.log(`  FAIL  ${msg}`); failures++; };
  const note = (msg: string) => console.log(`  note  ${msg}`);
  const check = (label: string, condition: boolean) =>
    condition ? ok(label) : bad(label);

  say("block devices");
  if (LIVE) {
    say("live system: skipping the block-device and target-root probes");
    check("running an Arch-family system", await runningArch());
    for (const tool of ["blkid", "efibootmgr"]) {
      check(`${tool} on PATH`, (await $`command -v ${tool}`.nothrow().quiet()).exitCode === 0);
    }
    if (failures > 0) {
      say(`preflight FAILED (${failures}) - fix the items above before continuing`);
      process.exit(1);
    }
    say("preflight passed");
    return;
  }

  check("p5 is btrfs", (await blkid("/dev/nvme0n1p5", "TYPE")) === "btrfs");
  check("p1 is vfat (ESP)", (await blkid("/dev/nvme0n1p1", "TYPE")) === "vfat");

  const swapUuid = await blkid("/dev/nvme0n1p2", "UUID");
  if (swapUuid === SWAP_UUID) ok(`p2 swap UUID matches (${SWAP_UUID})`);
  else bad(`p2 swap UUID is '${swapUuid}', expected ${SWAP_UUID} - edit .env`);

  const espUuid = await blkid("/dev/nvme0n1p1", "UUID");
  if (espUuid === ESP_UUID) ok(`esp UUID matches (${ESP_UUID})`);
  else bad(`esp UUID is '${espUuid}', expected ${ESP_UUID} - edit .env`);

  const archUuid = await blkid("/dev/nvme0n1p5", "UUID");
  if (archUuid === ARCH_UUID) ok(`arch UUID matches (${ARCH_UUID})`);
  else bad(`arch UUID is '${archUuid}', expected ${ARCH_UUID} - edit .env`);

  // Mounted read-only by this step, and unmounted again before it returns.
  const mountedForProbe: string[] = [];

  // Where `source` can be read: an existing mountpoint when one exists, or a
  // read-only mount this step makes and will undo. Returns null on failure,
  // having already reported it via bad().
  //
  // Reusing an existing mount is not just tidiness. The ESP is vfat, and it
  // refuses a second mount whose read-only flag conflicts with the mount that
  // already exists: on a Fedora host the ESP is mounted read-write at
  // /boot/efi, so a read-only probe at another mountpoint fails with
  // "already mounted on /boot/efi". A second read-write mount is accepted,
  // which is why 10-mount.ts can mount it again - the difference is the flag,
  // not the device.
  const readableAt = async (
    source: string,
    opts: string,
    mountpoint?: string,
  ): Promise<string | null> => {
    const found = await $`findmnt -rno TARGET --source ${source}`.nothrow().quiet();
    const existing = found.stdout.toString().trim().split("\n").filter(Boolean)[0];
    if (existing) {
      say(`${source} already mounted at ${existing}`);
      return existing;
    }

    // Created only when we actually have to mount, so an already-mounted
    // source leaves no temporary directory behind.
    const target = mountpoint ?? mkdtempSync(join(tmpdir(), "sensible-probe-"));
    await $`mkdir -p ${target}`;
    const r = await $`mount -o ${opts} ${source} ${target}`.nothrow().quiet();
    if (r.exitCode !== 0) {
      // Remove the mountpoint again, so a failed probe does not leave a stray
      // directory behind. rmdir only succeeds when it is empty, which is the
      // case when we just created it.
      await $`rmdir ${target}`.nothrow().quiet();
      bad(`cannot mount ${target} read-only: ${r.stderr.toString().trim() || "mount failed"}`);
      return null;
    }
    mountedForProbe.push(target);
    return target;
  };

  say("target root");
  const rootAt = await readableAt(ROOT_MNT_SOURCE, "ro,subvol=@", ROOT_MNT);

  if (!rootAt) {
    note("is p5 the btrfs volume holding subvol @? see .env ARCH_UUID");
    note("if btrfs wants recovering, mount it read-write once and unmount cleanly");
  } else {
    const modules = await $`ls ${rootAt}/usr/lib/modules`.nothrow().quiet();
    if (modules.exitCode === 0 && modules.stdout.toString().trim()) {
      const trees = modules.stdout.toString().trim().split("\n");
      ok(`modules: ${trees.join(" ")}`);
      if (trees.some((t) => t.includes("zen"))) ok(`${KERNEL} module tree present`);
      else note(`no zen kernel tree yet; 40-packages installs ${KERNEL}`);
    } else {
      bad(`no kernel modules under ${rootAt}/usr/lib/modules (is pacstrap done?)`);
    }

    for (const [label, path] of [
      ["fstab", "/etc/fstab"],
      ["pacman", "/usr/bin/pacman"],
      ["mkinitcpio", "/usr/bin/mkinitcpio"],
    ] as const) {
      check(`${label} present`, await Bun.file(`${rootAt}${path}`).exists());
    }

    say("esp");
    // No mountpoint given, so a temporary one is made only if the ESP is not
    // already mounted somewhere. Free space belongs to the filesystem, so it
    // does not matter which mountpoint answers.
    const espAt = await readableAt(`/dev/disk/by-uuid/${ESP_UUID}`, "ro");
    if (espAt) {
      const free = await $`df -Pk ${espAt}`.nothrow().quiet();
      if (free.exitCode === 0) {
        const kib = Number(free.stdout.toString().trim().split("\n")[1].split(/\s+/)[3]);
        if (kib > 400_000) ok(`esp free: ${Math.round(kib / 1024)} MiB via ${espAt}`);
        else bad(`esp free: ${kib} KiB (need ~400 MiB for two kernel sets)`);
      } else {
        bad("cannot read esp free space");
      }
    }
  }

  // Undo the probe before reporting, so a failed preflight still leaves the
  // machine exactly as it was found: nothing mounted, no mountpoint created.
  for (const target of [...mountedForProbe].reverse()) {
    const r = await $`umount ${target}`.nothrow().quiet();
    if (r.exitCode === 0) {
      say(`unmounted probe: ${target}`);
      await $`rmdir ${target}`.nothrow().quiet();
    } else {
      say(`warning: could not unmount ${target}; it is still mounted read-only`);
    }
  }

  say("host tools");
  // Not bun: the runner re-execs itself with an absolute bun path, and spawns
  // each step with that same path, so root never needs it on PATH.
  for (const tool of ["arch-chroot", "pacstrap", "genfstab", "efibootmgr", "blkid"]) {
    check(`${tool} on PATH`, (await $`command -v ${tool}`.nothrow().quiet()).exitCode === 0);
  }

  if (failures > 0) {
    say(`preflight FAILED (${failures}) - fix the items above before 10-mount.ts`);
    process.exit(1);
  }
  say("preflight passed");
}

async function down(): Promise<void> {
  say("read-only step, nothing to undo");
}

async function verify(): Promise<void> {
  for (const tool of ["/usr/bin/pacman", "/usr/bin/mkinitcpio"]) {
    (await existsInArch(tool)) ? ok(`${tool} present`) : fail(`${tool} is missing`);
  }
  (await existsInArch("/etc/fstab")) ? ok("/etc/fstab present") : fail("/etc/fstab is missing");
}

await main({ up, down, verify });
