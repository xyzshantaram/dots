/**
 * ---
 * script: 90-fish.ts
 * desc: Installs a minimal fish config for the Arch account: prompt, fortune greeting, git prompt colours.
 * needs: 50-user.ts up, 40-packages.ts up (fish, fortune-mod, cowsay)
 * up: writes config.fish, functions/fish_prompt.fish, functions/fish_greeting.fish, conf.d/git_prompt.fish into /home/ARCH_USER/.config/fish
 * down: removes those four files, nothing else on the account
 * revisit: 2026-12-21
 * ---
 *
 * Deliberately minimal: the prompt and the fortune greeting. Aliases,
 * abbreviations and whatever PATH blocks your other shell accumulated are not
 * copied. Add them as they are wanted.
 */
import process from "node:process";
import {
  ARCH_USER, inArch, inArchSoft, main, needMount, removeArch, say, writeUserFile,
} from "./lib.ts";

const BASE = `/home/${ARCH_USER}/.config/fish`;

/** Vendored file -> destination relative to the target root. */
const FILES: [string, string][] = [
  ["config.fish", `${BASE}/config.fish`],
  ["functions/fish_prompt.fish", `${BASE}/functions/fish_prompt.fish`],
  ["functions/fish_greeting.fish", `${BASE}/functions/fish_greeting.fish`],
  ["conf.d/git_prompt.fish", `${BASE}/conf.d/git_prompt.fish`],
];

async function up(): Promise<void> {
  await needMount();

  for (const [source, dest] of FILES) {
    const content = await Bun.file(`${import.meta.dir}/files/fish/${source}`).text();
    await writeUserFile(dest, content);
    say(`installed ${dest}`);
  }

  const syntax = await inArchSoft(
    "fish", "--no-execute", `${BASE}/config.fish`,
  );
  if (syntax.exitCode !== 0) {
    say("fish reported a syntax error in config.fish");
    process.stderr.write(syntax.stderr.toString());
    process.exit(1);
  }
  say("config.fish parses");

  const passwd = (await inArch("getent", "passwd", ARCH_USER).text()).trim();
  say(passwd.includes("/usr/bin/fish") ? "login shell is fish" : `unexpected: ${passwd}`);
  say("note  fish_variables stays absent until first login, so setup runs then");
}

async function down(): Promise<void> {
  await needMount();
  for (const [, dest] of FILES) await removeArch(dest);
  say("removed the four fish files; the account is otherwise untouched");
}

await main({ up, down });
