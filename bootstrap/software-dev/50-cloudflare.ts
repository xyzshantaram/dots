/**
 * ---
 * script: 50-cloudflare.ts
 * desc: Installs cf, the Cloudflare CLI, as a pnpm global for the Arch account.
 * needs: 10-toolchain.ts up (pnpm), network
 * up: pnpm add --global cf, then checks that cf resolves on PATH
 * down: pnpm remove -g cf
 * revisit: 2026-12-21
 * ---
 *
 * The npm package cf is Cloudflare's own, not a squat: it declares
 * github.com/cloudflare/cf as its repository and installs two bins, `cf` and
 * `cloudflare`. It is still 1.0.0-beta, so the command surface can move between
 * releases — worth knowing before anything scripts against it.
 *
 * Not the packages in extra. cloudflared there is the Tunnel client and wrangler
 * is the Workers tool; neither is this CLI, and installing one of them instead
 * would look right until the first command that does not exist.
 *
 * pnpm rather than a curl-to-shell installer for the same reason as
 * 30-brave-search: a script piped into a login shell is a step nobody can review
 * or undo, and pnpm gives the same binary a removal path.
 *
 * The bin is named `cf`, which collides with nothing installed here, but it does
 * collide with the Cloud Foundry CLI if that ever appears.
 *
 * Authentication is by hand, with `cf auth login`. The CLI keeps profiles under
 * ~/.config/cloudflare, which is also the one place worth knowing about if the
 * machine is ever shared, and a token committed to a repository is a leaked
 * token.
 */
import { asUser, asUserSoft, main, needMount, say } from "../lib.ts";

const PKG = "cf";

async function up(): Promise<void> {
  await needMount();

  const result = await asUser("pnpm", "add", "--global", PKG).nothrow();
  if (result.exitCode !== 0) {
    say("pnpm add --global cf failed; see above");
    return;
  }

  const which = await asUserSoft("sh", "-lc", "command -v cf");
  say(
    which.exitCode === 0
      ? `installed; cf is at ${which.stdout.toString().trim()}`
      : "installed, but cf is not on PATH — check pnpm's global bin is exported",
  );
}

async function down(): Promise<void> {
  await needMount();
  const removed = await asUser("pnpm", "remove", "--global", PKG).nothrow();
  say(removed.exitCode === 0 ? "removed cf" : "cf was not installed");
}

await main({ up, down });
