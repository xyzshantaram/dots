/**
 * ---
 * script: drawer-export.ts
 * desc: Copies chosen files out of the drawer into the target account.
 * needs: drawer-mount.ts up, 50-user.ts up
 * up: rsyncs DRAWER_EXPORTS paths from the drawer home into /home/$ARCH_USER, then chowns them
 * down: removes exactly what it copied, leaving pre-existing files alone
 * revisit: 2026-12-21
 * ---
 *
 * Deliberately narrow by default. Private keys are NOT exported: the tofu here
 * is config and known_hosts, which carry no secrets, and anything else has to
 * be named in DRAWER_EXPORTS on purpose.
 *
 * A browser profile is the one exception worth automating, and it is gated
 * behind EXPORT_BROWSER=1 for two real reasons:
 *
 *   1. A profile copied from a running session is mid-write and may be
 *      unusable. The other OS must be shut down, not hibernated.
 *   2. Firefox tolerates a profile move between Linux distributions, but it is
 *      not designed for it. Start it once with `-ProfileManager` afterwards.
 *
 * Existing files are never overwritten. That makes `up` safe to re-run and
 * means a second attempt after a partial failure is a no-op rather than a
 * clobber.
 */
import { $ } from "bun";
import process from "node:process";
import { ARCH_UID, ARCH_USER, ROOT_MNT, main, opt, say } from "../lib.ts";

const HOME = `/home/${ARCH_USER}`;

/** Relative paths under the drawer home. No secrets. */
const DEFAULT_EXPORTS = [".ssh/config", ".ssh/known_hosts"];

function drawerHome(): { mount: string; user: string } | null {
  const mount = opt("DRAWER_MOUNT") ?? "/mnt/drawer";
  const user = opt("DRAWER_USER");
  if (!opt("DRAWER_UUID") || !user) {
    say("DRAWER_UUID / DRAWER_USER unset; nothing to export from");
    return null;
  }
  return { mount, user };
}

async function copies(): Promise<string[]> {
  const configured = opt("DRAWER_EXPORTS");
  const list = configured
    ? configured.split(/\s+/).filter(Boolean)
    : [...DEFAULT_EXPORTS];
  if (process.env.EXPORT_BROWSER === "1") list.push(".mozilla/firefox");
  return list;
}

async function up(): Promise<void> {
  const drawer = drawerHome();
  if (drawer === null) return;
  const { mount, user } = drawer;
  const source = `${mount}/${user}`;

  const mounted = await $`mountpoint -q ${mount}`.nothrow().quiet();
  if (mounted.exitCode !== 0) {
    say(`${mount} is not mounted; run drawer-mount.ts up first`);
    process.exit(1);
  }

  const list = await copies();
  say(`exporting ${list.length} path(s) from ${source}`);

  let copied = 0;
  for (const rel of list) {
    const from = `${source}/${rel}`;
    const to = `${ROOT_MNT}${HOME}/${rel}`;

    if ((await $`test -e ${from}`.nothrow().quiet()).exitCode !== 0) {
      say(`  skip  ${rel} (not in the drawer)`);
      continue;
    }
    // Never clobber: an existing file means either this ran already or the
    // target has something deliberate in that place.
    if ((await $`test -e ${to}`.nothrow().quiet()).exitCode === 0) {
      say(`  keep  ${rel} (already exists in the target)`);
      continue;
    }

    await $`mkdir -p ${`${ROOT_MNT}${HOME}`}/${rel.split("/").slice(0, -1).join("/")}`
      .nothrow().quiet();
    const result = await $`cp -aL ${from} ${to}`.nothrow();
    if (result.exitCode !== 0) {
      say(`  FAIL  ${rel}`);
      process.stderr.write(result.stderr.toString());
      continue;
    }
    await $`chown -R ${ARCH_UID}:${ARCH_UID} ${to}`.nothrow().quiet();
    say(`  ok    ${rel}`);
    copied++;
  }

  if (process.env.EXPORT_BROWSER === "1") {
    say("browser profile copied: start firefox with -ProfileManager");
    say("the other OS must have been shut down, not hibernated, for this to be sane");
  }
  say(`${copied} path(s) exported into ${HOME}`);
}

async function down(): Promise<void> {
  const drawer = drawerHome();
  if (drawer === null) return;

  const list = await copies();
  for (const rel of list) {
    await $`rm -rf ${`${ROOT_MNT}${HOME}`}/${rel}`.nothrow().quiet();
  }
  say(`removed ${list.length} exported path(s); pre-existing files were never touched`);
}

await main({ up, down });
