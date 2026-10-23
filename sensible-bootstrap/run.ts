/**
 * run.ts — the ladder runner.
 *
 *   bun run run.ts list                 show every step, its description
 *   bun run run.ts plan [from] [to]     show what up/down would run, no execution
 *   bun run run.ts up [from] [to]       run steps in numeric order
 *   bun run run.ts down [from] [to]     run steps in reverse order
 *   bun run dualboot-utils/drawer-mount.ts up    (optional tools run standalone)
 *
 * With only `from` given, the range runs to the last step, so `up 130-paru`
 * resumes from there rather than running that one step alone. Use `plan` to see
 * the selection before committing to it.
 *
 * Interactive steps (20-chroot) are skipped by the runner: it is a helper,
 * not a phase of the build. Everything else is non-interactive except
 * 50-user, which prompts for a password.
 *
 * README: the ladder is designed so any step can be re-run. Each one is
 * idempotent on `do` and exact on `undo`.
 */
import { readdirSync, readFileSync } from "node:fs";
import process from "node:process";
import { parseFrontmatter } from "./lib.ts";

const HERE = import.meta.dir;
const SKIP_IN_RUN = new Set(["20-chroot.ts"]);

type Step = { file: string; num: number; meta: Record<string, string> };

function steps(): Step[] {
  return readdirSync(HERE)
    .filter((f) => /^\d+-.+\.ts$/.test(f))
    .map((file) => ({
      file,
      num: Number.parseInt(file, 10),
      meta: parseFrontmatter(readFileSync(`${HERE}/${file}`, "utf8")),
    }))
    .sort((a, b) => a.num - b.num);
}

function selectSteps(from?: string, to?: string): Step[] {
  const all = steps().filter((s) => !SKIP_IN_RUN.has(s.file));
  const index = (needle: string) => {
    const i = all.findIndex((s) => s.file === needle || s.file.startsWith(needle));
    if (i < 0) {
      console.error(`run: no step matches ${needle}`);
      process.exit(2);
    }
    return i;
  };
  const start = from ? index(from) : 0;
  const end = to ? index(to) : all.length - 1;
  if (end < start) {
    console.error("run: 'to' is before 'from'");
    process.exit(2);
  }
  return all.slice(start, end + 1);
}

async function runStep(step: Step, action: "up" | "down"): Promise<void> {
  console.error(`\n=== ${step.file} (${action}) ${step.meta.desc ?? ""}`);
  const proc = Bun.spawn(["bun", "run", `${HERE}/${step.file}`, action], {
    stdout: "inherit",
    stderr: "inherit",
    stdin: "inherit",
    env: process.env,
  });
  const code = await proc.exited;
  if (code !== 0) {
    console.error(`run: ${step.file} ${action} failed with exit ${code}`);
    console.error(`run: stopping. fix it, then re-run the same command.`);
    process.exit(code);
  }
}

const [command, ...rest] = process.argv.slice(2);

switch (command) {
  case "list": {
    for (const s of steps()) {
      const marker = SKIP_IN_RUN.has(s.file) ? " (helper)" : "";
      console.log(`${s.file.padEnd(24)} ${(s.meta.desc ?? "").slice(0, 72)}${marker}`);
    }
    break;
  }
  case "plan": {
    // Shows what a range would do without doing it. Read-only: no step is
    // spawned, no root needed.
    const chosen = selectSteps(rest[0], rest[1]);
    console.log(`${chosen.length} step(s), in this order:`);
    chosen.forEach((s, i) => {
      console.log(`${String(i + 1).padStart(2)}. ${s.file.padEnd(24)} ${s.meta.desc ?? ""}`);
    });
    console.log("\n`up` runs them in this order; `down` runs them in reverse.");
    break;
  }
  case "up":
  case "down": {
    const chosen = selectSteps(rest[0], rest[1]);
    const ordered = command === "up" ? chosen : [...chosen].reverse();
    for (const step of ordered) await runStep(step, command);
    console.error(`\nrun: ${ordered.length} step(s) ${command} complete`);
    break;
  }
  default:
    console.error("usage: bun run run.ts list|plan|up|down [from] [to]");
    process.exit(2);
}
