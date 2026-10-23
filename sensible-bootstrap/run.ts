/**
 * run.ts — the ladder runner.
 *
 *   bun run run.ts list                     every step, with its description
 *   bun run run.ts plan [from] [to]         what a range would run, no execution
 *   bun run run.ts up [from] [to]           run them in numeric order
 *   bun run run.ts down [from] [to]         run them in reverse order
 *   bun run run.ts up --only <step>         run exactly one step
 *   bun run run.ts --ladder dualboot-utils up
 *
 * A ladder is a directory of numbered TypeScript steps. Each one takes `up` or
 * `down`, is idempotent on `up` and exact on `down`, and describes itself in its
 * frontmatter.
 *
 * --ladder picks one directory and looks only at the steps directly inside it.
 * Nothing is traversed, so the main ladder never picks up dualboot-utils/, and
 * that stays true however the flag is spelled.
 *
 * With only `from` given the range runs to the last step, so `up 130-paru`
 * resumes there rather than running that one step alone. --only is how to ask
 * for a single step.
 */
import { existsSync, readdirSync, readFileSync, statSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import process from "node:process";
import { parseFrontmatter } from "./lib.ts";

const HERE = import.meta.dir;

/** Lives in the main ladder but is a helper, not a phase of the build. */
const SKIP_IN_RUN = new Set(["20-chroot.ts"]);

type Step = { file: string; num: number; meta: Record<string, string> };

type Args = {
  command?: string;
  ladder?: string;
  from?: string;
  to?: string;
  only?: string;
};

function fail(message: string): never {
  console.error(`run: ${message}`);
  process.exit(2);
}

/** Every numbered step directly inside a directory, in numeric order. */
function stepsIn(dir: string): Step[] {
  return readdirSync(dir)
    .filter((f) => /^\d+-.+\.ts$/.test(f))
    .map((file) => ({
      file,
      num: Number.parseInt(file, 10),
      meta: parseFrontmatter(readFileSync(join(dir, file), "utf8")),
    }))
    .sort((a, b) => a.num - b.num);
}

/**
 * Finds the ladder directory.
 *
 * Relative names are looked for beside this script first, then beside its
 * parent, so both `--ladder dualboot-utils` and `--ladder sensible-bootstrap`
 * work when run from the repo root. No recursion either way.
 */
function resolveLadder(name?: string): string {
  if (name === undefined) return resolve(HERE);

  const candidates = [join(HERE, name), join(dirname(HERE), name)];
  for (const candidate of candidates) {
    if (existsSync(candidate) && statSync(candidate).isDirectory()) return resolve(candidate);
  }

  console.error(`run: no ladder directory ${name}`);
  console.error(`run: looked in ${candidates.join(" and ")}`);
  process.exit(2);
}

function parseArgs(argv: string[]): Args {
  const args: Args = {};
  const positional: string[] = [];

  for (let i = 0; i < argv.length; i++) {
    const arg = argv[i];
    const take = (name: string): string => {
      const value = argv[++i];
      if (value === undefined) fail(`${name} needs a value`);
      return value;
    };

    if (arg === "--ladder") args.ladder = take(arg);
    else if (arg.startsWith("--ladder=")) args.ladder = arg.slice("--ladder=".length);
    else if (arg === "--only") args.only = take(arg);
    else if (arg.startsWith("--only=")) args.only = arg.slice("--only=".length);
    else if (arg.startsWith("-")) fail(`unknown flag ${arg}`);
    else positional.push(arg);
  }

  [args.command, args.from, args.to] = positional;
  if (args.only !== undefined && (args.from !== undefined || args.to !== undefined)) {
    fail("--only takes no other step arguments");
  }
  return args;
}

function selectSteps(dir: string, skip: Set<string>, args: Args): Step[] {
  const all = stepsIn(dir).filter((s) => !skip.has(s.file));

  const index = (needle: string): number => {
    const i = all.findIndex((s) => s.file === needle || s.file.startsWith(needle));
    if (i < 0) fail(`no step matches ${needle}`);
    return i;
  };

  if (args.only !== undefined) return [all[index(args.only)]];

  const start = args.from ? index(args.from) : 0;
  const end = args.to ? index(args.to) : all.length - 1;
  if (end < start) fail("'to' is before 'from'");
  return all.slice(start, end + 1);
}

async function runStep(dir: string, step: Step, action: "up" | "down"): Promise<void> {
  console.error(`\n=== ${step.file} (${action}) ${step.meta.desc ?? ""}`);
  const proc = Bun.spawn(["bun", "run", join(dir, step.file), action], {
    stdout: "inherit",
    stderr: "inherit",
    stdin: "inherit",
    env: process.env,
  });
  const code = await proc.exited;
  if (code !== 0) {
    console.error(`run: ${step.file} ${action} failed with exit ${code}`);
    console.error("run: stopping. fix it, then re-run the same command.");
    process.exit(code);
  }
}

const args = parseArgs(process.argv.slice(2));
const dir = resolveLadder(args.ladder);

/** The skip list belongs to the main ladder, not to any other directory. */
const skip = dir === resolve(HERE) ? SKIP_IN_RUN : new Set<string>();
const usage = "usage: bun run run.ts list|plan|up|down [from] [to] [--only step] [--ladder dir]";

switch (args.command) {
  case "list": {
    for (const s of stepsIn(dir)) {
      const marker = skip.has(s.file) ? " (helper)" : "";
      console.log(`${s.file.padEnd(24)} ${(s.meta.desc ?? "").slice(0, 72)}${marker}`);
    }
    break;
  }
  case "plan": {
    // Read-only: nothing is spawned, and no root is needed.
    const chosen = selectSteps(dir, skip, args);
    console.log(`${dir}`);
    console.log(`${chosen.length} step(s), in this order:`);
    chosen.forEach((s, i) => {
      console.log(`${String(i + 1).padStart(2)}. ${s.file.padEnd(24)} ${s.meta.desc ?? ""}`);
    });
    console.log("\n`up` runs them in this order; `down` runs them in reverse.");
    break;
  }
  case "up":
  case "down": {
    const chosen = selectSteps(dir, skip, args);
    const ordered = args.command === "up" ? chosen : [...chosen].reverse();
    for (const step of ordered) await runStep(dir, step, args.command);
    console.error(`\nrun: ${ordered.length} step(s) ${args.command} complete`);
    break;
  }
  default:
    console.error(usage);
    process.exit(2);
}
