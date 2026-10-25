/**
 * ---
 * script: 15-agent-browser.ts
 * desc: Installs agent-browser, the browser automation CLI for AI agents, from the AUR.
 * needs: 40-packages.ts up in the main ladder (base-devel, for makepkg), and network
 * up: builds and installs agent-browser-bin through lib.ts's aurInstall
 * down: pacman -Rns agent-browser-bin
 * revisit: 2026-12-21
 * ---
 *
 * This is the CLI Command Code's browser skill drives: navigate, click, fill,
 * screenshot, and read a page back as text, from a shell rather than from a
 * person. It comes after 10-toolchain because it is the other half of that
 * install — the agent, and the browser it can see.
 *
 * The package is the upstream release binary for this architecture, so makepkg
 * downloads and symlinks rather than compiles. It still goes through `makepkg`,
 * which is why base-devel has to be there.
 *
 * A browser engine to drive is an optdepend, not a dependency: chromium is the
 * upstream default, google-chrome and lightpanda are alternatives, and ffmpeg is
 * only needed to record video. None of them is installed here — a browser is a
 * large choice and this step has no way to know which one is wanted.
 */
import { aurInstall, inArchSoft, main, needMount, say } from "../lib.ts";

const PKG = "agent-browser-bin";
const BIN = "agent-browser";

async function up(): Promise<void> {
  await needMount();

  if ((await inArchSoft("pacman", "-Qq", PKG)).exitCode === 0) {
    say(`${PKG} is already installed`);
  } else {
    await aurInstall(PKG);
    say(`installed ${PKG}`);
  }

  const binary = await inArchSoft("test", "-x", `/usr/bin/${BIN}`);
  say(
    binary.exitCode === 0
      ? `${BIN} is at /usr/bin/${BIN}`
      : `${BIN} did not land at /usr/bin/${BIN}`,
  );
  say("a browser to drive is an optdepend: chromium, google-chrome or lightpanda");
}

async function down(): Promise<void> {
  await needMount();

  const removed = await inArchSoft("pacman", "-Rns", "--noconfirm", PKG);
  say(removed.exitCode === 0 ? `removed ${PKG}` : `${PKG} was not installed`);
}

await main({ up, down });
