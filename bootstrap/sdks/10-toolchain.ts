/**
 * ---
 * script: 10-toolchain.ts
 * desc: Installs the software-development toolchain for the account: cmake, unzip and autoconf; fnm carrying the latest Node LTS, pnpm built from that npm, and Command Code from pnpm; rustup; and Zed.
 * needs: an installed Arch system — the account (50-user.ts) and base-devel (40-packages.ts) — and network
 * up: pacman-installs cmake/unzip/autoconf/fnm/zed, then as ARCH_USER runs fnm install --lts, npm install -g pnpm, pnpm add -g command-code and the rustup installer; writes the fish conf.d that puts them on PATH
 * down: removes the conf.d, the global npm and pnpm packages, rustup, fnm's data directory, pnpm's global directory and the packages
 * revisit: 2026-12-21
 * ---
 *
 * This is a ladder of its own because none of it is needed for a working niri
 * session: the main ladder builds a session, this one builds somewhere to write
 * code in it. It is optional, and the main ladder never depends on it.
 *
 *   bun run ladder sdks up
 *   bun run ladder sdks --only 10-toolchain up
 *
 * Rust comes from rustup, deliberately, and nothing here installs a distro
 * `rust`. rustup is also what 105-niri-gestures.ts builds the patched niri with;
 * that step calls the same lib.ts helper (ensureRustup) if this ladder has not
 * been run, which is what lets the main ladder stay self-contained without a
 * distro rust.
 *
 * Node arrives through fnm rather than the `nodejs` package, so the version is
 * the account's choice and can be switched per project. pnpm is installed with
 * npm *from that fnm node*, so pnpm is bound to the fnm-managed Node rather than
 * to a system-wide one, and Command Code comes from pnpm on top of that.
 *
 * Command Code is the npm package `command-code`. It ships four names for the
 * same entry point — `cmd`, `cmdc`, `commandcode` and `command-code` — and needs
 * Node 22 or newer, which the LTS release satisfies.
 *
 * PATH is wired through a fish conf.d snippet rather than through config.fish,
 * because 90-fish.ts in the main ladder owns that file and this ladder should be
 * removable without touching it.
 */
import process from "node:process";
import {
  ARCH_USER, asUser, at, ensureRustup, inArch, inArchSoft, main, needMount,
  removeArch, say, writeUserFile,
} from "../lib.ts";

const HOME = `/home/${ARCH_USER}`;

/** fnm's data directory, and the stable path to the node it selects. */
const FNM_DIR = `${HOME}/.local/share/fnm`;
const NODE_BIN = `${FNM_DIR}/aliases/default/bin`;
/** Where `pnpm add -g` puts its binaries, made explicit so it is predictable. */
const PNPM_HOME = `${HOME}/.local/share/pnpm`;
/** rustup's default: the toolchain and the shims live together. */
const CARGO_BIN = `${HOME}/.cargo/bin`;

const FISH_CONF = `${HOME}/.config/fish/conf.d/sdks.fish`;

/**
 * Packages from the repositories. autoconf is already in base-devel, and `--needed`
 * makes it a no-op; it is listed because this ladder's contract is "these are
 * installed", not "these were possibly already there".
 */
const PACMAN = ["cmake", "unzip", "autoconf", "fnm", "zed"];

/** Installed with npm from the fnm node, then with pnpm. */
const NPM_GLOBAL = ["pnpm"];
const PNPM_GLOBAL = ["command-code"];

/**
 * Runs one shell line as the account, with the toolchains this step installs on
 * PATH.
 *
 * Needed because the installs feed each other: npm has to be found before pnpm
 * exists, and pnpm before Command Code does. `runuser` is not a login shell, so
 * none of this comes from a shell rc file.
 */
function sdkShell(script: string) {
  // pnpm's global bin directory is $PNPM_HOME/bin, not $PNPM_HOME. Leaving it
  // out makes `pnpm add -g` refuse with ERR_PNPM_GLOBAL_BIN_DIR_NOT_IN_PATH
  // rather than install, which is how this was found.
  const path = [NODE_BIN, `${PNPM_HOME}/bin`, CARGO_BIN, "$PATH"].join(":");
  return asUser(
    "bash", "-lc",
    `export PNPM_HOME=${PNPM_HOME}\nexport PATH="${path}"\n${script}`,
  ).nothrow().quiet();
}

/** Reports a failed shell line and stops, printing what it actually said. */
function died(what: string, result: { exitCode: number; stderr: Buffer }): never {
  say(`${what} failed (exit ${result.exitCode}):`);
  process.stderr.write(result.stderr.toString());
  process.exit(1);
}

async function installPackages(): Promise<void> {
  say(`installing ${PACMAN.join(" ")}`);
  const result = await inArch("pacman", "-S", "--needed", "--noconfirm", ...PACMAN)
    .nothrow();
  if (result.exitCode !== 0) died(`pacman ${PACMAN.join(" ")}`, result);
  say("packages installed");
}

async function installNode(): Promise<void> {
  say("installing the latest Node LTS through fnm");
  const result = await sdkShell("fnm install --lts && fnm default lts-latest");
  if (result.exitCode !== 0) died("fnm install --lts", result);

  // fnm's aliases/default is a symlink to the version it settled on, so this is
  // stable across LTS bumps and is what the fish snippet and this step both
  // read. Checked rather than assumed.
  if ((await inArchSoft("test", "-x", `${NODE_BIN}/node`)).exitCode !== 0) {
    say(`no node at ${NODE_BIN}; fnm's default alias may be named differently`);
    const versions = await inArchSoft("ls", "-1", `${FNM_DIR}/node-versions`);
    say(`versions present: ${versions.stdout.toString().trim().split("\n").join(" ")}`);
    process.exit(1);
  }
  say("node LTS installed, and selected as the default");
}

async function installPnpm(): Promise<void> {
  say("installing pnpm with npm from that node");
  const result = await sdkShell("npm install --global pnpm");
  if (result.exitCode !== 0) died("npm install -g pnpm", result);

  if ((await inArchSoft("test", "-x", `${NODE_BIN}/pnpm`)).exitCode !== 0) {
    say(`npm reported success but there is no pnpm at ${NODE_BIN}/pnpm`);
    process.exit(1);
  }
  say("pnpm installed");
}

async function installCommandCode(): Promise<void> {
  say("installing Command Code with pnpm");
  const result = await sdkShell("pnpm add --global command-code");
  if (result.exitCode !== 0) died("pnpm add -g command-code", result);

  if ((await inArchSoft("test", "-x", `${PNPM_HOME}/bin/command-code`)).exitCode !== 0) {
    say(`pnpm reported success but there is no command-code in ${PNPM_HOME}/bin`);
    process.exit(1);
  }
  say(`command-code installed into ${PNPM_HOME}/bin`);
}

async function installFishPath(): Promise<void> {
  await writeUserFile(
    FISH_CONF,
    `# Developer toolchains, installed by the bootstrap sdks ladder.
#
# A conf.d snippet rather than config.fish, so removing this ladder does not
# mean editing a file the main ladder owns.

# rustup
if test -d $HOME/.cargo/bin
    fish_add_path --move --prepend $HOME/.cargo/bin
end

# pnpm's global binaries. They live in $PNPM_HOME/bin, not $PNPM_HOME; pnpm
# itself refuses a global add when that directory is not on PATH.
set -gx PNPM_HOME $HOME/.local/share/pnpm
if test -d $PNPM_HOME/bin
    fish_add_path --move --prepend $PNPM_HOME/bin
end

# node, through fnm. Sets PATH for the default version, and re-sets it when you
# cd into a project with a .node-version or .nvmrc.
if type -q fnm
    fnm env --use-on-cd --shell fish | source
end
`,
  );
  say(`wrote ${FISH_CONF}`);

  const syntax = await inArchSoft("fish", "--no-execute", FISH_CONF);
  if (syntax.exitCode !== 0) {
    say("fish rejected the snippet:");
    process.stderr.write(syntax.stderr.toString());
    process.exit(1);
  }
  say("the fish snippet parses");
}

async function up(): Promise<void> {
  await needMount();

  await installPackages();
  await installNode();
  await installPnpm();
  await installCommandCode();
  await ensureRustup();
  await installFishPath();

  say(`node:  ${NODE_BIN}/node  (fnm default)`);
  say(`pnpm:  ${NODE_BIN}/pnpm, globals in ${PNPM_HOME}/bin`);
  say(`rust:  ${CARGO_BIN}/cargo  (rustup)`);
  say("open a new shell for PATH; this step does not touch the running one");
}

async function down(): Promise<void> {
  await needMount();

  await removeArch(FISH_CONF);
  say(`removed ${FISH_CONF}`);

  // While node and the package managers still exist, remove what they added.
  for (const pkg of PNPM_GLOBAL) {
    const r = await sdkShell(`pnpm remove --global ${pkg}`);
    say(r.exitCode === 0 ? `removed ${pkg}` : `${pkg} was not installed`);
  }
  for (const pkg of NPM_GLOBAL) {
    const r = await sdkShell(`npm uninstall --global ${pkg}`);
    say(r.exitCode === 0 ? `removed ${pkg}` : `${pkg} was not installed`);
  }

  // rustup uninstalls itself: ~/.cargo and ~/.rustup both go.
  const rustupUninstall = await sdkShell("rustup self uninstall -y");
  say(
    rustupUninstall.exitCode === 0
      ? "ran rustup self uninstall"
      : "rustup was not installed",
  );

  await removeArch(FNM_DIR);
  await removeArch(PNPM_HOME);
  say("removed fnm's node versions and pnpm's global directory");

  await inArchSoft("pacman", "-Rns", "--noconfirm", ...PACMAN);
  say(`removed ${PACMAN.join(" ")}`);
}

await main({ up, down });
