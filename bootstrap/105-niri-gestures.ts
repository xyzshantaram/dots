/**
 * ---
 * script: 105-niri-gestures.ts
 * desc: Rebuilds niri with the configurable touch-gesture patch set (niri-wm/niri#3771), so three-finger and four-finger touchpad gestures can be bound in config.kdl.
 * needs: 40-packages.ts up (niri, base-devel), network
 * up: installs clang, ensures rustup, builds the vendored PKGBUILD as ARCH_USER with rustup's cargo, and installs the result with pacman -U, replacing the stock niri
 * down: removes the patch build and reinstalls the official niri package
 * revisit: 2026-12-21
 * ---
 *
 * niri's touchpad gestures are hardcoded: three fingers switch workspaces and
 * scroll the view, four open the overview, and none of it is configurable.
 * This repo wants three fingers for the overview and four for navigation,
 * which needs niri-wm/niri#3771. That series is vendored under
 * files/niri-gestures/ and applied to the upstream commit it was rebased onto.
 *
 * A package, not `cargo install`: the stock niri owns /usr/bin/niri, so a
 * hand-installed binary would be silently overwritten by the next niri update
 * and pacman would not know about it. A package with provides/conflicts
 * replaces the stock one cleanly and stays visible to `pacman -Q`.
 *
 * There is a real trap in building this with rustup's rustc, recorded so it is
 * not rediscovered. makepkg's `lto` option puts -flto=auto into CFLAGS, which
 * turns libspa's C shim into GCC LTO bytecode; rust-lld — which rustup's rustc
 * links with — understands LLVM bitcode but not GCC's, so the C archive becomes
 * unlinkable and the build dies with `undefined symbol: libspa_rs_type_video_format`
 * and friends. The PKGBUILD sets options=('!lto') for exactly this; its comment
 * has the failure verbatim.
 *
 * Rust comes from rustup, not from a distro `rust` package, for the reason the
 * sdks ladder gives: the toolchain is the account's, and makepkg could not see
 * it in makedepends anyway. ensureRustup() is what makes that true.
 *
 * Runs before 110-niri.ts on purpose: config.kdl binds `TouchpadSwipe`, and
 * only this build understands that trigger, so `niri validate` would reject the
 * config on the stock package.
 */
import process from "node:process";
import { $ } from "bun";
import {
  ARCH_USER, asUser, at, ensureRustup, inArch, inArchSoft, main, needMount, say,
} from "./lib.ts";

const PKG = "niri-gestures";
const WORK = `/var/tmp/${PKG}`;
const SRC = `${import.meta.dir}/files/niri-gestures`;

/**
 * Build dependency installed as root and removed again afterwards. It is not in
 * 40-packages.ts, so dropping it touches nothing else; `git` and `patch` come
 * with base-devel.
 *
 * `rust` is deliberately absent: niri is built with rustup's cargo from the
 * account, not with a distro package. makedepends is therefore a package list
 * makepkg can check, and the PKGBUILD puts ~/.cargo/bin on PATH itself.
 */
const MAKEDEPS = ["clang"];

/** True when the patched package is what is installed. */
async function installed(): Promise<boolean> {
  return (await inArchSoft("pacman", "-Q", PKG)).exitCode === 0;
}

async function up(): Promise<void> {
  await needMount();

  if (await installed()) {
    say(`${PKG} is already installed`);
    return;
  }

  // Before makepkg, not after: the PKGBUILD's build() expects ~/.cargo/bin.
  await ensureRustup();

  say(`installing build dependencies: ${MAKEDEPS.join(" ")}`);
  const deps = await inArch("pacman", "-S", "--asdeps", "--needed", "--noconfirm", ...MAKEDEPS)
    .nothrow();
  if (deps.exitCode !== 0) {
    say("could not install the build dependencies; see above");
    process.exit(deps.exitCode);
  }

  // /var/tmp, not /tmp: arch-chroot mounts a fresh tmpfs over the target's /tmp
  // on every invocation, and building and installing are separate ones.
  say(`staging the PKGBUILD in ${WORK}`);
  await inArchSoft("rm", "-rf", WORK);
  const made = await inArch("mkdir", "-p", WORK).nothrow();
  if (made.exitCode !== 0) {
    say(`could not create ${WORK}`);
    process.exit(made.exitCode);
  }
  await $`cp -a ${SRC}/. ${at(WORK)}/`.quiet();
  await inArch("chown", "-R", `${ARCH_USER}:${ARCH_USER}`, WORK);

  say(`building ${PKG} as ${ARCH_USER}; niri is a large Rust build, expect a wait`);
  const build = await asUser("bash", "-lc", `cd ${WORK} && makepkg --noconfirm`).nothrow();
  if (build.exitCode !== 0) {
    say(`${PKG} failed to build; see above`);
    say(`the work directory is left at ${WORK}`);
    process.exit(build.exitCode);
  }

  // Listed and filtered in JS rather than with a shell glob: makepkg also emits
  // a -debug package, and Bun Shell fails a glob that matches nothing.
  const listing = await inArchSoft("ls", "-1", WORK);
  const built = listing.stdout
    .toString()
    .split("\n")
    .map((line) => line.trim())
    .filter((name) => new RegExp(`^${PKG}-.*\\.pkg\\.tar\\.(zst|xz|gz)$`).test(name))
    .filter((name) => !name.includes("-debug-"))
    .sort()
    .pop();
  if (!built) {
    say(`makepkg left no ${PKG} package in ${WORK}`);
    say(`contents: ${listing.stdout.toString().trim().split("\n").join(" ")}`);
    say("left in place for inspection; re-run this step once it is understood");
    process.exit(1);
  }

  say(`installing ${built}, replacing the stock niri`);
  const install = await inArch("pacman", "-U", "--noconfirm", `${WORK}/${built}`).nothrow();
  if (install.exitCode !== 0) {
    say("installing the built package failed; see above");
    process.exit(install.exitCode);
  }

  // Being installed says nothing about whether it runs, and a compositor that
  // does not start is only discovered at the next login.
  const version = await inArchSoft("niri", "--version");
  if (version.exitCode !== 0) {
    say("niri-gestures is installed but will not run:");
    process.stderr.write(version.stderr.toString());
    process.exit(1);
  }
  say(version.stdout.toString().split("\n")[0] ?? `${PKG} installed`);

  const dropped = await inArchSoft("pacman", "-Rns", "--noconfirm", ...MAKEDEPS);
  say(
    dropped.exitCode === 0
      ? `removed ${MAKEDEPS.join(" ")} again`
      : `could not remove ${MAKEDEPS.join(" ")}; remove it by hand if you want it gone`,
  );

  await inArchSoft("rm", "-rf", WORK);
  say("niri can now bind touchpad gestures; 110-niri.ts is what binds them");
  say("when #3771 lands upstream, drop this step — see files/niri-gestures/PKGBUILD");
}

async function down(): Promise<void> {
  await needMount();

  if (await installed()) {
    // The official package does not conflict with this one, so remove ours
    // first; installing niri over the top would leave both owning /usr/bin/niri.
    await inArchSoft("pacman", "-R", "--noconfirm", PKG);
    const restored = await inArch("pacman", "-S", "--noconfirm", "niri").nothrow();
    say(
      restored.exitCode === 0
        ? "reinstalled the official niri package"
        : "could not reinstall niri; run: pacman -S niri",
    );
  } else {
    say(`${PKG} is not installed`);
  }
  await inArchSoft("rm", "-rf", WORK);
}

await main({ up, down });
