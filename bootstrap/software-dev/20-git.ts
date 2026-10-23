/**
 * ---
 * script: 20-git.ts
 * desc: Installs the git presentation config — the stat and https-to-ssh aliases, delta as the pager with its colours, and the global ignore file — plus the git-delta and bat packages, and the account's identity and SSH commit signing from .env.
 * needs: 10-toolchain.ts up (base-devel carries git), network
 * up: pacman-installs git-delta and bat, composes ~/.config/git/config from files/git/config plus the .env identity, writes it alongside ~/.config/git/ignore, and validates the result with git config -f
 * down: restores or removes both files, and uninstalls the packages
 * revisit: 2026-12-21
 * ---
 *
 * The config lands in ~/.config/git/config, the XDG location, rather than
 * ~/.gitconfig. Git reads both and lets ~/.gitconfig win for single-valued
 * keys, so a hand-written ~/.gitconfig can sit beside this without either file
 * overwriting the other. It also keeps `down` to exactly two files.
 *
 * core.excludesFile is deliberately not set: git's default excludes path is
 * $XDG_CONFIG_HOME/git/ignore, which is where the ignore file goes.
 *
 * Identity is not in the vendored file. Name, email and signing key are person-
 * and machine-specific, so they come from .env — GIT_NAME, GIT_EMAIL,
 * GIT_SIGNING_KEY — and are appended at install time. With either of the first
 * two unset there is no [user] section at all, and signing is switched on by
 * GIT_SIGNING_KEY being set, with no separate toggle: a signing key with
 * signing off is a key that does nothing.
 *
 * The composed file is checked with `git config -f` before either real file is
 * touched, so a bad value in .env fails this step rather than every git command
 * afterwards.
 */
import process from "node:process";
import {
  ARCH_USER, asUserSoft, backupOnce, inArch, inArchSoft, main, needMount, opt,
  removeArch, restoreBackup, say, writeUserFile,
} from "../lib.ts";

const HOME = `/home/${ARCH_USER}`;
const CONFIG = `${HOME}/.config/git/config`;
const IGNORE = `${HOME}/.config/git/ignore`;
const SRC = `${import.meta.dir}/../files/git`;

/** Packages from the repositories, installed as root. */
const PACMAN = ["git-delta", "bat"];

/** Staged inside the target, so `git` can read it in either mode. */
const STAGE = "/var/tmp/software-dev-git-config";

/**
 * The [user], [gpg], [commit] and [tag] sections, from .env.
 *
 * Empty when there is no name or email: an existing identity is never written
 * over with half of one.
 */
function identity(): string {
  const name = opt("GIT_NAME");
  const email = opt("GIT_EMAIL");
  const key = opt("GIT_SIGNING_KEY");
  if (!name || !email) return "";

  const lines = ["", "[user]", `\tname = ${name}`, `\temail = ${email}`];
  if (key) {
    lines.push(
      `\tsigningkey = ${key}`,
      "[gpg]", "\tformat = ssh",
      "[commit]", "\tgpgsign = true",
      "[tag]", "\tgpgSign = true",
    );
  }
  return `${lines.join("\n")}\n`;
}

async function up(): Promise<void> {
  await needMount();

  say(`installing ${PACMAN.join(" ")}`);
  const installed = await inArch("pacman", "-S", "--needed", "--noconfirm", ...PACMAN)
    .nothrow();
  if (installed.exitCode !== 0) {
    say(`could not install ${PACMAN.join(" ")}; see above`);
    process.exit(installed.exitCode);
  }

  const vendored = await Bun.file(`${SRC}/config`).text();
  const content = vendored + identity();

  // Parse the whole composed file before writing either real one. --list reads
  // every section, so a malformed value anywhere fails here.
  await writeUserFile(STAGE, content);
  const parsed = await inArchSoft("git", "config", "-f", STAGE, "--list");
  if (parsed.exitCode !== 0) {
    say("the composed git config does not parse:");
    process.stderr.write(parsed.stderr.toString());
    say(`staged copy left at ${STAGE}`);
    process.exit(1);
  }
  await removeArch(STAGE);

  await backupOnce(CONFIG, ".software-dev-save");
  await backupOnce(IGNORE, ".software-dev-save");
  await writeUserFile(CONFIG, content);
  await writeUserFile(IGNORE, await Bun.file(`${SRC}/ignore`).text());
  say(`wrote ${CONFIG}`);
  say(`wrote ${IGNORE}`);

  // Read it back the way git will, with --global, which covers both
  // ~/.gitconfig and the XDG file.
  const visible = await asUserSoft("git", "config", "--global", "--get", "alias.stat");
  const value = visible.stdout.toString().trim();
  say(value ? `git sees alias.stat = ${value}` : "git does not report alias.stat");

  const signingKey = opt("GIT_SIGNING_KEY");
  if (!signingKey) {
    say("no GIT_SIGNING_KEY in .env; commit signing left off");
    return;
  }
  const readable = await inArchSoft("test", "-r", signingKey);
  say(
    readable.exitCode === 0
      ? `commit signing on, with ${signingKey}`
      : `warning: ${signingKey} is unreadable, so every signed commit will fail`,
  );
}

async function down(): Promise<void> {
  await needMount();

  for (const [rel, name] of [[CONFIG, "config"], [IGNORE, "ignore"]] as const) {
    if (await restoreBackup(rel, ".software-dev-save")) {
      say(`restored the original ~/.config/git/${name}`);
    } else {
      await removeArch(rel);
      say(`removed ~/.config/git/${name} (there was no original)`);
    }
  }

  await removeArch(STAGE);
  await inArchSoft("pacman", "-Rns", "--noconfirm", ...PACMAN);
  say(`removed ${PACMAN.join(" ")}`);
}

await main({ up, down });
