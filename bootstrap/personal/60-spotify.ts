/**
 * ---
 * script: 60-spotify.ts
 * desc: Installs spotify-launcher, the native client that tracks Spotify's own apt repository.
 * needs: 40-packages.ts up (base-devel, curl), and network on first launch
 * up: pacman -S --needed spotify-launcher
 * down: removes the package and the downloaded build under ~/.cache
 * revisit: 2026-12-21
 * ---
 *
 * Not the flatpak, and not aur/spotify.
 *
 * The flatpak is fully sandboxed, which is normally the point — but it also
 * cannot preload a shared object, and the only fix for Spotify's white CEF
 * title bar on a tiling Wayland compositor is an LD_PRELOAD shim (see
 * AlpSha/spotify-no-titlebar). CEF draws that bar from inside its own browser
 * process, so no compositor rule reaches it, and the sandbox is exactly what
 * blocks the one mechanism that does. Two attempts at forcing it through
 * XWayland did not help either, which is what that project's own notes predict.
 *
 * The AUR's spotify is a repackaging of Spotify's Debian build, and
 * repackagings go stale between upstream releases. spotify-launcher is in the
 * repositories and is neither: it is a small Rust client for Spotify's official
 * apt repository, so the first launch downloads the vendor build and later
 * launches keep it current. That is why it is preferred over the AUR here, and
 * it is a reversal of the reasoning in an earlier version of this step.
 *
 * The first launch downloads about 100MB into ~/.cache/spotify-launcher, so it
 * needs network and takes a moment. The shim is not installed by this step: it
 * is a third-party build that writes a per-user .desktop, and keeping it out of
 * the ladder means a rebuild does not silently pull a C API interposer along
 * with a music player.
 */
import { ARCH_USER, inArchSoft, main, needMount, removeArch, say } from "../lib.ts";

const PKG = "spotify-launcher";
const CACHE = `/home/${ARCH_USER}/.cache/spotify-launcher`;

async function up(): Promise<void> {
  await needMount();

  if ((await inArchSoft("pacman", "-Qq", PKG)).exitCode === 0) {
    say(`${PKG} is already installed`);
    return;
  }

  const installed = await inArchSoft(
    "pacman", "-S", "--needed", "--noconfirm", PKG,
  );

  if (installed.exitCode !== 0) {
    say(`could not install ${PKG}; see above`);
    return;
  }

  say(`installed ${PKG}`);
  say("the first launch downloads the Spotify build from Spotify's apt repository");
  say("run it once from the app launcher, then the titlebar shim can preload into it");
}

async function down(): Promise<void> {
  await needMount();

  const removed = await inArchSoft("pacman", "-Rns", "--noconfirm", PKG);
  say(removed.exitCode === 0 ? `removed ${PKG}` : `${PKG} was not installed`);

  await removeArch(CACHE);
  say("removed the downloaded build; it is re-fetched on the next install");
}

await main({ up, down });
