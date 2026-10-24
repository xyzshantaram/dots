/**
 * ---
 * script: 60-spotify.ts
 * desc: Installs Spotify from Flathub, and adds the Flathub remote if it is missing.
 * needs: 40-packages.ts up (flatpak), and network
 * up: flatpak remote-add flathub, then flatpak install com.spotify.Client
 * down: flatpak uninstall com.spotify.Client; the remote is left in place
 * revisit: 2026-12-21
 * ---
 *
 * Flatpak rather than the AUR. Spotify publishes a Debian package and no Arch
 * one, so the AUR options are repackagings that have historically gone stale
 * between upstream releases; Flathub is the vendor-approved channel and the one
 * that gets updated. It is also sandboxed, which is why the package is
 * com.spotify.Client and not "spotify".
 *
 * The remote is added here rather than in the packages step because flatpak can
 * be installed without any remote configured, and a remote is a decision about
 * where software comes from — worth stating in the step that uses it. It is
 * left in place on the way down: removing it would break every other flatpak
 * anybody installed by hand.
 */
import { inArch, inArchSoft, main, needMount, say } from "../lib.ts";

const REMOTE = "flathub";
const REPO = "https://dl.flathub.org/repo/flathub.flatpakrepo";
const APP = "com.spotify.Client";

async function up(): Promise<void> {
  await needMount();

  const remote = await inArch(
    "flatpak", "remote-add", "--if-not-exists", "--system", REMOTE, REPO,
  ).nothrow();
  say(remote.exitCode === 0 ? `remote ${REMOTE} present` : "could not add the remote");

  const install = await inArch(
    "flatpak", "install", "--system", "--noninteractive", REMOTE, APP,
  ).nothrow();
  say(
    install.exitCode === 0
      ? `installed ${APP}`
      : `${APP} did not install — see above; an existing install reports as an error`,
  );
}

async function down(): Promise<void> {
  await needMount();
  const removed = await inArchSoft(
    "flatpak", "uninstall", "--system", "--noninteractive", APP,
  );
  say(
    removed.exitCode === 0
      ? `removed ${APP}`
      : `${APP} was not installed; left the ${REMOTE} remote alone`,
  );
}

await main({ up, down });
