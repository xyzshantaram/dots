/**
 * ---
 * script: 30-brave-search.ts
 * desc: Installs bx, the Brave Search CLI, as a pnpm global for the Arch account.
 * needs: 10-toolchain.ts up (pnpm), 20-git.ts up, and network
 * up: pnpm install -g @brave/brave-search-cli as ARCH_USER
 * down: pnpm remove -g @brave/brave-search-cli
 * revisit: 2026-12-21
 * ---
 *
 * Not in the AUR, which is why this is a package manager install rather than an
 * aurInstall: the AUR has brave-bin, the browser, and nothing for the search
 * CLI. There is a curl-to-shell installer in the project's README and this
 * deliberately does not use it — a script piped into a login shell is a step
 * nobody can review or undo, and pnpm gives the same binary a removal path.
 *
 * What pnpm installs is a launcher around a ~2MB Rust binary the package ships,
 * so there is no cargo build here and no Rust toolchain to keep. Its exit code
 * 127 is "the launcher could not start the binary", which is the failure to
 * expect if the platform-specific payload is ever missing.
 *
 * The API key is not installed by this step and cannot be: it is an account
 * credential, and a key written into a git repository is a key that has been
 * leaked. Run `bx config set-key` once by hand, or export
 * BRAVE_SEARCH_API_KEY. The config lands in ~/.config/brave-search/config.json
 * with the directory at 0700 and the file at 0600.
 */
import { asUser, inArchSoft, main, needMount, say } from "../lib.ts";

const PKG = "@brave/brave-search-cli";

async function up(): Promise<void> {
  await needMount();

  const result = await asUser("pnpm", "install", "-g", PKG).nothrow();
  if (result.exitCode !== 0) {
    say("pnpm install failed; see above");
    return;
  }

  const which = await asUser("sh", "-lc", "command -v bx").nothrow().quiet();
  say(
    which.exitCode === 0
      ? `installed; bx is at ${which.stdout.toString().trim()}`
      : "installed, but bx is not on PATH — check pnpm's global bin is exported",
  );
}

async function down(): Promise<void> {
  await needMount();
  const removed = await asUser("pnpm", "remove", "-g", PKG).nothrow();
  say(removed.exitCode === 0 ? `removed ${PKG}` : `${PKG} was not installed`);
}

await main({ up, down });
