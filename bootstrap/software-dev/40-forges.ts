/**
 * ---
 * script: 40-forges.ts
 * desc: Installs the GitHub and GitLab CLIs from the repositories, so gh and glab are on PATH for the Arch account.
 * needs: 10-toolchain.ts up, 20-git.ts up, network
 * up: pacman -S --needed github-cli glab, then checks that both binaries resolve
 * down: removes both packages, leaving their stored logins alone
 * revisit: 2026-12-21
 * ---
 *
 * Both are in extra, so there is no AUR build and nothing to pin. They are one
 * step because everything about them is the same: same source, same install,
 * same hand-over to a login that cannot happen here.
 *
 * Logging in is deliberately not done by this step. `gh auth login` and
 * `glab auth login` write OAuth tokens to ~/.config/gh/hosts.yml and
 * ~/.config/glab-cli/config.yml, and a token in a repository is a leaked token
 * even when the file is gitignored. `down` removes the packages and leaves those
 * files, because a credential is the one thing in this step that cannot be
 * re-derived from the repository.
 *
 * Neither needs anything from the shell: both are plain binaries in /usr/bin, so
 * there is no PATH or fish snippet to keep in sync.
 */
import { asUserSoft, inArch, inArchSoft, main, needMount, say } from "../lib.ts";

const PKGS = ["github-cli", "glab"];

/** The binaries the packages are supposed to provide, checked after install. */
const BINS = ["gh", "glab"];

async function up(): Promise<void> {
  await needMount();

  const installed = await inArch(
    "pacman", "-S", "--needed", "--noconfirm", ...PKGS,
  ).nothrow();

  if (installed.exitCode !== 0) {
    say(`could not install ${PKGS.join(" ")}; see above`);
    return;
  }
  say(`installed ${PKGS.join(" ")}`);

  // Resolved through a login shell, because that is where the user will look
  // for them. A package that installs but does not resolve is the failure worth
  // catching here rather than at the first `gh pr` of the day.
  for (const bin of BINS) {
    const which = await asUserSoft("sh", "-lc", `command -v ${bin}`);
    say(
      which.exitCode === 0
        ? `${bin} is at ${which.stdout.toString().trim()}`
        : `${bin} did not land on PATH`,
    );
  }

  say("log in by hand: gh auth login, then glab auth login");
}

async function down(): Promise<void> {
  await needMount();

  const removed = await inArchSoft("pacman", "-Rns", "--noconfirm", ...PKGS);
  say(
    removed.exitCode === 0
      ? `removed ${PKGS.join(" ")}`
      : `${PKGS.join(" ")} were not installed`,
  );
  say("left ~/.config/gh and ~/.config/glab-cli alone: they hold the login");
}

await main({ up, down });
