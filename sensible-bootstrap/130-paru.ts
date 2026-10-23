/**
 * ---
 * script: 130-paru.ts
 * desc: Installs paru (AUR helper) for the Arch account and refreshes the AUR view.
 * needs: 40-packages.ts up (git, base-devel), 50-user.ts up
 * up: installs rust, builds paru from source as ARCH_USER, installs it with pacman -U, checks it runs, removes rust again, then refreshes the AUR index
 * down: pacman -Rns paru
 * revisit: 2026-12-21
 * ---
 *
 * paru built from source, not paru-bin, and that is not a preference. paru links
 * libalpm directly, so a prebuilt binary only works while its soname matches the
 * pacman in the machine. paru-bin 2.1.0 needs libalpm.so.15; pacman 7.1 ships
 * .16, so every call to it died with "cannot open shared object file" - including
 * the -Sy at the end of this step, which failed quietly because it is treated as
 * non-fatal. paru's newest release is still 2.1.0, so there is no newer -bin to
 * wait for. A source build links against this system's own libalpm, which is
 * exactly what the alpm crate's build probe demands (atleast_version 16.0.0).
 *
 * The cost is a Rust toolchain. `rust` provides cargo, and the two cannot be
 * installed together, so one package covers it. It goes in as a dependency and
 * comes out again once paru is built and verified, so the finished system does
 * not carry ~324MB of compiler it will never use. A later paru rebuild will
 * fetch it again.
 *
 * makepkg runs WITHOUT -s, deliberately. `makepkg -s` and `-si` install
 * dependencies by shelling out to sudo, and sudo inside a chroot has no cached
 * credentials: it sits waiting for a password nobody can type. Dependencies are
 * installed here as root instead, so makepkg has nothing to fetch and never
 * reaches for sudo.
 *
 * The build directory is under /var/tmp, not /tmp, and that is load-bearing.
 * arch-chroot mounts a fresh tmpfs over the target's /tmp on every invocation
 * (chroot_add_mount in /usr/bin/arch-chroot). Building and installing are two
 * separate invocations here, so anything left in /tmp is destroyed before the
 * second one looks for it - which is what "makepkg produced no package file"
 * meant the first time this step ran.
 */
import process from "node:process";
import {
  ARCH_USER, ROOT_MNT, asUser, inArch, inArchSoft, main, needMount, say,
} from "./lib.ts";

const WORK = "/var/tmp/paru";

/** Build dependencies, installed as root and removed again at the end. */
const MAKEDEPS = ["rust"];

/**
 * The installed package that owns a file, or null when nothing does.
 *
 * Needed because `pacman -Q paru` and `pacman -R paru` do not agree about
 * names. -Q resolves provides, so it reports the paru-bin package as satisfying
 * "paru" and exits 0; -R takes only a real package name and answers "target not
 * found: paru". Asking who owns the file is right whichever package shipped it,
 * and it stays right for paru-git or anything else that provides paru later.
 */
async function ownerOf(path: string): Promise<string | null> {
  const found = await inArchSoft("pacman", "-Qo", path);
  if (found.exitCode !== 0) return null;
  // "usr/bin/paru is owned by paru-bin 2.1.0-1"
  return found.stdout.toString().match(/is owned by (\S+)/)?.[1] ?? null;
}

/**
 * Builds paru from source and installs the result, or exits on failure.
 */
async function buildAndInstall(): Promise<void> {
  say(`installing build dependencies: ${MAKEDEPS.join(" ")}`);
  const installed = await inArch("pacman", "-S", "--asdeps", "--noconfirm", ...MAKEDEPS).nothrow();
  if (installed.exitCode !== 0) {
    say("could not install the build dependencies; see above");
    process.exit(installed.exitCode);
  }

  say(`building paru from source as ${ARCH_USER}`);
  const build = await asUser(
    "bash", "-lc",
    `rm -rf ${WORK} && git clone --depth 1 https://aur.archlinux.org/paru.git ${WORK} ` +
      `&& cd ${WORK} && makepkg --noconfirm`,
  ).nothrow();
  if (build.exitCode !== 0) {
    say("paru build failed; see above");
    say(`the work directory is left at ${WORK} for inspection`);
    process.exit(build.exitCode);
  }

  // makepkg leaves the package in the work directory. Install it as root: no
  // sudo, no prompt.
  //
  // Listed and filtered here rather than with a shell glob: makepkg also emits a
  // -debug package, and `ls | head -1` selects whichever sorts first. Bun Shell
  // also expands globs written directly in a command template and fails the
  // whole command when one matches nothing.
  const listing = await inArchSoft("ls", "-1", WORK);
  const candidates = listing.stdout
    .toString()
    .split("\n")
    .map((line) => line.trim())
    .filter((name) => /^paru-.*\.pkg\.tar\.(zst|xz|gz)$/.test(name))
    .filter((name) => !name.includes("-debug-"))
    .sort();
  const name = candidates[candidates.length - 1];
  if (!name) {
    say(`makepkg left no paru package in ${WORK}`);
    const saw = listing.stdout.toString().trim();
    say(saw ? `contents: ${saw.split("\n").join(" ")}` : "the directory is empty");
    say("left in place for inspection; re-run this step once it is understood");
    process.exit(1);
  }

  const install = await inArch("pacman", "-U", "--noconfirm", `${WORK}/${name}`).nothrow();
  if (install.exitCode !== 0) {
    say("installing the built package failed; see above");
    process.exit(install.exitCode);
  }
  say(`installed ${name}`);
}

async function up(): Promise<void> {
  await needMount();

  // Decide from whether paru RUNS, not from whether it is installed. A broken
  // paru-bin from before this change is installed and useless, and a re-run has
  // to replace it rather than skip the build.
  if ((await inArchSoft("paru", "--version")).exitCode === 0) {
    say("paru is installed and runs");
  } else {
    const owner = await ownerOf("/usr/bin/paru");
    if (owner) {
      say(`${owner} is installed but paru does not run; replacing it`);
      const removed = await inArch("pacman", "-Rdd", "--noconfirm", owner).nothrow();
      if (removed.exitCode !== 0) {
        say(`could not remove ${owner}; see above`);
        process.exit(removed.exitCode);
      }
    }
    await buildAndInstall();
  }

  // paru links libalpm, so it only runs when it was built against the soname
  // this pacman ships. Check that here: a mismatch is silent everywhere else,
  // and the next step just reports a bare exit code 127.
  const version = await inArchSoft("paru", "--version");
  if (version.exitCode !== 0) {
    say("paru is installed but will not run:");
    process.stderr.write(version.stderr.toString());
    say("it links libalpm, so it must be built against this system's pacman");
    say(`check with: arch-chroot ${ROOT_MNT} ldd /usr/bin/paru | grep alpm`);
    process.exit(1);
  }
  say(version.stdout.toString().split("\n")[0] ?? "paru installed");

  // Drop the toolchain again. Best effort: worth saying, not worth failing over.
  const dropped = await inArchSoft("pacman", "-Rns", "--noconfirm", ...MAKEDEPS);
  say(
    dropped.exitCode === 0
      ? `removed ${MAKEDEPS.join(" ")} again`
      : `could not remove ${MAKEDEPS.join(" ")}; remove it by hand if you want it gone`,
  );

  await inArchSoft("rm", "-rf", WORK);

  // -Sy only refreshes the AUR index; it needs no root.
  const refresh = await asUser("paru", "-Sy", "--noconfirm").nothrow();
  if (refresh.exitCode === 0) {
    say("AUR index refreshed");
  } else {
    // Print what paru said rather than what the failure probably means. This
    // line used to read "the AUR may be unreachable", and that was wrong every
    // time it fired here: paru was not running at all, because the paru-bin
    // binary it came from needed a libalpm this system does not have. The
    // reason had been on stderr the whole time and was being discarded.
    say("paru -Sy failed; the AUR index is stale. Not fatal.");
    process.stderr.write(refresh.stderr.toString());
  }
}

async function down(): Promise<void> {
  await needMount();
  // Ask who owns the binary rather than naming "paru": a machine that still has
  // paru-bin installed, or paru-git, would otherwise be left with it.
  const owner = await ownerOf("/usr/bin/paru");
  if (owner) {
    await inArchSoft("pacman", "-Rns", "--noconfirm", owner);
    say(`removed ${owner}`);
  } else {
    say("no package owns /usr/bin/paru; nothing to remove");
  }
  await inArchSoft("rm", "-rf", WORK);
}

await main({ up, down });
