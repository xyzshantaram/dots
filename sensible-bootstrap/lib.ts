/**
 * lib.ts — shared constants and helpers for the sensible-bootstrap ladder.
 *
 * Every step imports from here so the paths, UUIDs and user name exist in one
 * place. Bun Shell escapes all interpolated values, so nothing below needs
 * manual quoting.
 */
import { $ } from "bun";
import { mkdir } from "node:fs/promises";
import { existsSync, readFileSync } from "node:fs";
import { basename, dirname, join } from "node:path";
import process from "node:process";

/**
 * Loads .env from the directory this file lives in, not from the cwd.
 *
 * The steps are run under sudo, often from another directory, and Bun's own
 * .env discovery is cwd-based. Read it explicitly so the same values apply
 * however a step is invoked. Real environment variables win over the file,
 * matching Bun's precedence.
 */
const ENV_FILE = join(import.meta.dir, ".env");

if (!existsSync(ENV_FILE)) {
  console.error(
    `lib: no .env at ${ENV_FILE}\n` +
      `lib: copy the template and fill it in: cp ${join(import.meta.dir, ".env.example")} ${ENV_FILE}`,
  );
  process.exit(1);
}

for (const raw of readFileSync(ENV_FILE, "utf8").split("\n")) {
  const line = raw.trim();
  if (!line || line.startsWith("#")) continue;
  const eq = line.indexOf("=");
  if (eq < 1) continue;
  const key = line.slice(0, eq).trim();
  let value = line.slice(eq + 1).trim();
  if (
    (value.startsWith('"') && value.endsWith('"')) ||
    (value.startsWith("'") && value.endsWith("'"))
  ) {
    value = value.slice(1, -1);
  }
  if (process.env[key] === undefined) process.env[key] = value;
}

function req(key: string): string {
  const value = process.env[key];
  if (value === undefined || value === "") {
    console.error(`lib: required key ${key} is missing from ${ENV_FILE}`);
    process.exit(1);
  }
  return value;
}

/**
 * Reads a key that is allowed to be absent, unlike req().
 *
 * The crossover tools in dualboot-utils/ use this for their own keys: the base
 * ladder has to run on a single-boot machine where those are unset, so nothing
 * there may hard-exit on a missing value.
 */
export function opt(key: string): string | undefined {
  const value = process.env[key];
  return value === undefined || value === "" ? undefined : value;
}

export const ROOT_MNT = req("ROOT_MNT");

export const ESP_UUID = req("ESP_UUID");
export const SWAP_UUID = req("SWAP_UUID");
export const ARCH_UUID = req("ARCH_UUID");

export const ARCH_USER = req("ARCH_USER");
export const ARCH_UID = Number.parseInt(req("ARCH_UID"), 10);

export const KERNEL = req("KERNEL");

/**
 * Where the ESP is mounted inside the target root.
 *
 * ArchWiki: /efi is the recommended mountpoint, and /boot/efi is "historical
 * and now discouraged". This machine's install used /boot/efi, so
 * 12-esp-efi.ts moves it to /efi, and everything here assumes /efi.
 */
export const ESP_MOUNT = req("ESP_MOUNT");

export const ESP_CURRENT = "/EFI/arch/current";
export const ESP_PREVIOUS = "/EFI/arch/previous";

export type Action = "up" | "down";

export type Actions = {
  up: () => Promise<void> | void;
  down: () => Promise<void> | void;
};

/** Command name for log prefixes: 10-mount.ts -> 10-mount */
export function tag(): string {
  return basename(process.argv[1] ?? "step").replace(/\.[^.]+$/, "");
}

/** Progress goes to stderr: stdout stays pipeable. */
export function say(...parts: unknown[]): void {
  console.error(`${tag()}: ${parts.join(" ")}`);
}

export function die(message: string): never {
  console.error(`${tag()}: error: ${message}`);
  process.exit(1);
}

/**
 * Entry point for every step.
 *
 *   bun run 10-mount.ts up      mount
 *   bun run 10-mount.ts down    unmount
 *
 * `up` and `down` rather than `do`/`undo` because `do` is a reserved word in
 * JavaScript and cannot name a function.
 */
export async function main(actions: Actions): Promise<void> {
  const verb = process.argv[2];
  if (verb !== "up" && verb !== "down") {
    console.error(`usage: ${basename(process.argv[1] ?? "step")} up|down`);
    process.exit(2);
  }
  needRoot();
  await actions[verb]();
}

export function needRoot(): void {
  if (process.getuid?.() !== 0) die("run as root (sudo)");
}

export async function isMounted(path: string): Promise<boolean> {
  const r = await $`mountpoint -q ${path}`.nothrow().quiet();
  return r.exitCode === 0;
}

export async function needMount(): Promise<void> {
  if (!(await isMounted(ROOT_MNT))) {
    die(`${ROOT_MNT} is not mounted; run ./10-mount.ts do first`);
  }
}

/** Runs a command inside the target root via arch-chroot. */
export function inArch(...args: (string | number)[]) {
  return $`arch-chroot ${ROOT_MNT} ${args}`;
}

/** Runs a command inside the target root, never throwing. */
export function inArchSoft(...args: (string | number)[]) {
  return $`arch-chroot ${ROOT_MNT} ${args}`.nothrow().quiet();
}

/**
 * Runs a command inside the target as ARCH_USER, with HOME and the session
 * variables set explicitly.
 *
 * `runuser -u` without `-l` does not reliably set HOME, so an AUR helper would
 * write its cache to /root/.cache and fail, or worse, succeed into the wrong
 * home. Passing HOME explicitly avoids the whole question.
 */
export function asUser(...args: (string | number)[]) {
  return $`arch-chroot ${ROOT_MNT} runuser -u ${ARCH_USER} -- env HOME=/home/${ARCH_USER} USER=${ARCH_USER} LOGNAME=${ARCH_USER} ${args}`;
}

/** Same, never throwing. */
export function asUserSoft(...args: (string | number)[]) {
  return asUser(...args).nothrow().quiet();
}

/**
 * Where AUR packages are cloned and built.
 *
 * Not /tmp: arch-chroot mounts a fresh tmpfs over the target's /tmp on every
 * invocation, and cloning, building and installing are separate invocations.
 * Anything left in /tmp is gone before the next call looks for it.
 */
const AUR_WORK = "/var/tmp/aur";
const AUR_URL = "https://aur.archlinux.org";

/** Pulls the `key = value` arrays out of a package's .SRCINFO. */
function srcinfoField(srcinfo: string, field: string): string[] {
  const out: string[] = [];
  for (const line of srcinfo.split("\n")) {
    const m = line.match(/^\s*([a-z]+)\s*=\s*(.+)$/);
    if (m && m[1] === field) out.push(...m[2].trim().split(/\s+/));
  }
  return out;
}

/** Last non-empty line of captured output, for one-line reporting. */
function lastLine(text: string): string {
  const lines = text.split("\n").map((line) => line.trim()).filter(Boolean);
  return lines[lines.length - 1] ?? "(no output)";
}

/**
 * Imports a PKGBUILD's accepted signing keys into ARCH_USER's keyring.
 *
 * makepkg verifies a source's signature when the PKGBUILD ships one, and will
 * not build when the signing key is unknown:
 *
 *   voxtype-1.1.1.tar.gz ... FAILED (unknown public key A3FC9F33FD209279)
 *   ==> ERROR: One or more PGP signatures could not be verified!
 *
 * A PKGBUILD lists the fingerprints it accepts in validpgpkeys, but listing
 * them does not fetch them, and an AUR helper is what normally does that step.
 *
 * The keys are fetched as plain HTTPS GETs and imported as files, rather than
 * through gpg's own keyserver protocol. Fetching a key is just a download, and
 * the keyserver route goes through dirmngr, which failed here - quietly, since
 * the call was `.quiet()`, so all that showed up was the summary line and none
 * of the reason. One less daemon and one fewer silent failure:
 *
 *   https://keyserver.ubuntu.com/pks/lookup?op=get&search=0x<fingerprint>
 *   https://keys.openpgp.org/vks/v1/by-fingerprint/<fingerprint>
 *
 * Both answer application/pgp-keys with an armored block that `gpg --import`
 * accepts directly.
 *
 * The key only has to be *present*: makepkg checks the signing fingerprint
 * against validpgpkeys itself and never asks whether the key is trusted, so
 * there is no need to sign it locally and no reason to skip the check instead.
 *
 * A failure here is not fatal on its own, because a PKGBUILD may list keys
 * without shipping any signatures. makepkg gives the authoritative verdict -
 * but whatever went wrong is printed rather than guessed at.
 */
async function importSigningKeys(keys: string[]): Promise<void> {
  for (const key of keys) {
    if ((await asUserSoft("gpg", "--list-keys", key)).exitCode === 0) continue;

    say(`importing signing key ${key}`);
    const file = `${AUR_WORK}/${key}.asc`;
    let imported = false;

    for (const url of [
      `https://keyserver.ubuntu.com/pks/lookup?op=get&search=0x${key}`,
      `https://keys.openpgp.org/vks/v1/by-fingerprint/${key}`,
    ]) {
      const host = new URL(url).host;

      const got = await inArchSoft("curl", "-sSf", "-o", file, url);
      if (got.exitCode !== 0) {
        say(`${host}: ${lastLine(got.stderr.toString())}`);
        continue;
      }

      // As ARCH_USER: the keyring that matters is the one makepkg verifies
      // against, and makepkg runs unprivileged.
      const add = await asUserSoft("gpg", "--import", file);
      if (add.exitCode !== 0) {
        say(`${host}: gpg --import: ${lastLine(add.stderr.toString())}`);
        continue;
      }

      say(`imported from ${host}`);
      imported = true;
      break;
    }

    await inArchSoft("rm", "-f", file);
    if (!imported) {
      say(`could not import ${key}; if a source ships a signature, makepkg`);
      say("will report it as an unknown public key and stop");
    }
  }
}

/**
 * Builds AUR packages from source and installs them: clone as ARCH_USER,
 * prepare build dependencies as root, build as ARCH_USER, install as root.
 *
 * This is what an AUR helper would do, minus the helper. A helper installs
 * through `sudo pacman -U`, which stops and waits for a password. That prompt
 * is answerable even here — arch-chroot mounts a fresh devtmpfs on /dev, and
 * /dev/tty still resolves to the terminal that started the run — but it needs
 * someone sitting there to answer it. Every other step runs unattended, and
 * this one should too.
 *
 * makepkg is deliberately NOT given -s or -si for the same reason: both install
 * dependencies by shelling out to sudo. Dependencies are read out of the
 * package's own .SRCINFO and installed here as root instead, so makepkg has
 * nothing to fetch and never reaches for sudo. Signing keys are imported here
 * for a related reason: a PKGBUILD lists the keys it accepts but nothing
 * fetches them, and an AUR helper is what normally does that.
 *
 * The work directory is left in place when something fails, so the cause is
 * still there to read.
 */
export async function aurInstall(...packages: string[]): Promise<void> {
  for (const pkg of packages) {
    const dir = `${AUR_WORK}/${pkg}`;

    say(`cloning ${pkg} from the AUR`);
    const cloned = await asUser(
      "bash", "-lc", `rm -rf ${dir} && git clone --depth 1 ${AUR_URL}/${pkg}.git ${dir}`,
    ).nothrow();
    if (cloned.exitCode !== 0) {
      say(`could not clone ${pkg}; see above`);
      process.exit(cloned.exitCode);
    }

    // .SRCINFO sits next to the PKGBUILD and holds exactly what
    // `makepkg --printsrcinfo` would print, so read the file instead of running
    // a subprocess as ARCH_USER to regenerate it. The AUR regenerates it on
    // every push and serves it to the web interface, so it matches the clone.
    const meta = await readArch(`${dir}/.SRCINFO`);
    if (meta === null) {
      say(`${pkg} has no .SRCINFO; every AUR package ships one`);
      process.exit(1);
    }
    const wanted = [
      ...srcinfoField(meta, "makedepends"),
      ...srcinfoField(meta, "checkdepends"),
    ].map((dep) => dep.replace(/[<>=].*$/, ""));

    if (wanted.length > 0) {
      say(`build dependencies: ${[...new Set(wanted)].join(" ")}`);
      // --needed skips what is already installed. pacman -S resolves provides,
      // so a dependency named `cargo` finds the rust package providing it.
      const deps = await inArch(
        "pacman", "-S", "--asdeps", "--needed", "--noconfirm", ...[...new Set(wanted)],
      ).nothrow();
      if (deps.exitCode !== 0) {
        say(`could not install ${pkg}'s build dependencies; see above`);
        process.exit(deps.exitCode);
      }
    }

    await importSigningKeys(srcinfoField(meta, "validpgpkeys"));

    say(`building ${pkg}`);
    const built = await asUser("bash", "-lc", `cd ${dir} && makepkg --noconfirm`).nothrow();
    if (built.exitCode !== 0) {
      say(`${pkg} failed to build; see above`);
      say(`the work directory is left at ${dir}`);
      process.exit(built.exitCode);
    }

    // Listed and filtered in JS rather than with a shell glob: makepkg also
    // emits a -debug package, and Bun Shell fails the whole command when a glob
    // written into the template matches nothing.
    const listing = await inArchSoft("ls", "-1", dir);
    const files = listing.stdout
      .toString()
      .split("\n")
      .map((line) => line.trim())
      .filter((name) => /\.pkg\.tar\.(zst|xz|gz)$/.test(name))
      .filter((name) => !name.includes("-debug-"))
      .map((name) => `${dir}/${name}`);
    if (files.length === 0) {
      say(`makepkg left no package in ${dir}`);
      process.exit(1);
    }

    const installed = await inArch("pacman", "-U", "--noconfirm", ...files).nothrow();
    if (installed.exitCode !== 0) {
      say(`installing ${pkg} failed; see above`);
      process.exit(installed.exitCode);
    }
    say(`installed ${files.map((file) => basename(file)).join(" ")}`);

    await inArchSoft("rm", "-rf", dir);
  }
}

/** True when a path exists inside the target root. */
export async function existsInArch(rel: string): Promise<boolean> {
  const r = await $`test -e ${ROOT_MNT + rel}`.nothrow().quiet();
  return r.exitCode === 0;
}

/**
 * Writes a file inside the target root. Bypasses the shell entirely, so
 * content with quotes, dollar signs or newlines is safe.
 */
export async function writeArch(
  rel: string,
  content: string | ArrayBuffer,
  mode = 0o644,
  owner: { uid: number; gid: number } = { uid: 0, gid: 0 },
): Promise<string> {
  const dest = `${ROOT_MNT}${rel}`;
  await mkdir(dirname(dest), { recursive: true });
  await Bun.write(dest, content);
  await $`chmod ${mode.toString(8)} ${dest}`.quiet();
  await $`chown ${owner.uid}:${owner.gid} ${dest}`.quiet();
  return dest;
}

/** Writes a file owned by the target user instead of root. Accepts binaries. */
export function writeUserFile(rel: string, content: string | ArrayBuffer, mode = 0o644) {
  return writeArch(rel, content, mode, { uid: ARCH_UID, gid: ARCH_UID });
}

/** Removes a path inside the target root if present. */
export async function removeArch(rel: string): Promise<boolean> {
  const r = await $`rm -rf ${ROOT_MNT + rel}`.nothrow().quiet();
  return r.exitCode === 0;
}

/** Reads a file inside the target root, or null when absent. */
export async function readArch(rel: string): Promise<string | null> {
  const file = Bun.file(`${ROOT_MNT}${rel}`);
  return (await file.exists()) ? file.text() : null;
}

/** Appends a line to a target file unless the line is already present. */
export async function appendOnce(rel: string, line: string): Promise<boolean> {
  const current = (await readArch(rel)) ?? "";
  if (current.split("\n").some((l) => l.trim() === line.trim())) return false;
  await writeArch(rel, current.endsWith("\n") || current === "" ? current + line + "\n" : current + "\n" + line + "\n");
  return true;
}

/**
 * Backs up a target file next to itself before the first modification, so a
 * step's undo can restore it without keeping its own copy of the contents.
 */
export async function backupOnce(rel: string, suffix = ".pam-save"): Promise<void> {
  const dest = `${ROOT_MNT}${rel}`;
  if (!(await Bun.file(dest).exists())) return;
  const backup = `${dest}${suffix}`;
  if (await Bun.file(backup).exists()) return;
  await $`cp -a ${dest} ${backup}`.quiet();
}

export async function restoreBackup(rel: string, suffix = ".pam-save"): Promise<boolean> {
  const dest = `${ROOT_MNT}${rel}`;
  const backup = `${dest}${suffix}`;
  if (!(await Bun.file(backup).exists())) return false;
  await $`cp -a ${backup} ${dest}`.quiet();
  await $`rm -f ${backup}`.quiet();
  return true;
}

/** Reads the frontmatter block at the top of a step file. */
export function parseFrontmatter(source: string): Record<string, string> {
  const block = source.match(/\/\*\*([\s\S]*?)\*\//);
  if (!block) return {};
  const out: Record<string, string> = {};
  let key = "";
  for (const raw of block[1].split("\n")) {
    const line = raw.replace(/^\s*\*?\s?/, "").trimEnd();
    if (!line || line === "---") continue;
    const m = line.match(/^([a-z][a-z-]*):\s*(.*)$/);
    if (m) {
      key = m[1];
      out[key] = m[2];
    } else if (key) {
      out[key] = `${out[key]} ${line.trim()}`.trim();
    }
  }
  return out;
}
