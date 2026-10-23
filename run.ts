/**
 * run.ts — the ladder runner. Lives at the repo root; the steps live in
 * bootstrap/.
 *
 *   bun run ladder list                        every step, with its description
 *   bun run ladder plan [from] [to]            what a range would run
 *   bun run ladder up [from] [to]              run them in numeric order
 *   bun run ladder down [from] [to]            run them in reverse order
 *   bun run ladder up --only <step>            exactly one step
 *   bun run ladder dualboot-utils up           another ladder, by name
 *   bun run ladder up --live                   ... into this system, not a target
 *
 * `bun run ladder` is the package.json script for this file, so no `sudo` is
 * needed on the command line: up and down escalate themselves, once, and
 * list/plan stay unprivileged.
 *
 * A ladder is a directory of numbered TypeScript steps. Each one takes `up` or
 * `down`, is idempotent on `up` and exact on `down`, and describes itself in its
 * frontmatter.
 *
 * The first argument names a ladder when it is not one of the four verbs. Names
 * are looked for at the repo root and then inside the main ladder, so both
 * `dualboot-utils` and `bootstrap` work. Only the steps directly inside
 * that directory are read: nothing is traversed, so the main ladder never picks
 * up the dualboot one, and that one never reaches back. `--ladder <dir>` is the
 * same thing as an explicit flag.
 *
 * With only `from` given the range runs to the last step, so `up 130-paru`
 * resumes there rather than running that one step alone. `--only` is how to ask
 * for a single step.
 *
 * `--live` sets ROOT_MNT=/ for the run, which points every step at the running
 * system instead of at a mounted target root. It is exactly the same as writing
 * ROOT_MNT=/ in .env, for one run; the steps themselves do not care which way
 * it was asked for.
 */
import { existsSync, readdirSync, readFileSync, statSync } from "node:fs";
import { isAbsolute, join, resolve } from "node:path";
import process from "node:process";
import { parseFrontmatter } from "./bootstrap/lib.ts";

const ROOT = import.meta.dir;
const MAIN_LADDER = join(ROOT, "bootstrap");

/** Lives in the main ladder but is a helper, not a phase of the build. */
const SKIP_IN_MAIN = new Set(["20-chroot.ts"]);

const VERBS = new Set(["list", "plan", "up", "down"]);

type Step = { file: string; num: number; meta: Record<string, string> };

type Args = {
  command?: string;
  ladder?: string;
  from?: string;
  to?: string;
  only?: string;
  live?: boolean;
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
 * Names are looked for at the repo root first, then inside the main ladder, so
 * `dualboot-utils` and `bootstrap` both work. Absolute paths are used
 * as given. No recursion either way.
 */
function resolveLadder(name?: string): string {
  if (name === undefined) return MAIN_LADDER;

  const candidates = isAbsolute(name) ? [name] : [join(ROOT, name), join(MAIN_LADDER, name)];

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
    const take = (flag: string): string => {
      const value = argv[++i];
      if (value === undefined) fail(`${flag} needs a value`);
      return value;
    };

    if (arg === "--ladder") args.ladder = take(arg);
    else if (arg.startsWith("--ladder=")) args.ladder = arg.slice("--ladder=".length);
    else if (arg === "--only") args.only = take(arg);
    else if (arg.startsWith("--only=")) args.only = arg.slice("--only=".length);
    else if (arg === "--live") args.live = true;
    else if (arg.startsWith("-")) fail(`unknown flag ${arg}`);
    else positional.push(arg);
  }

  // A leading word that is not a verb has to be a ladder name.
  if (positional.length > 0 && !VERBS.has(positional[0])) {
    if (args.ladder !== undefined) fail("two ladders named; use one or the other");
    args.ladder = positional.shift();
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
  // process.execPath is this bun binary, so the child keeps working even when
  // sudo's secure_path does not include the one that started this.
  const proc = Bun.spawn([process.execPath, "run", join(dir, step.file), action], {
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

// --live points every step at the running system. Set on this process's
// environment, which both the escalation re-exec below and each step spawn
// inherit, so nothing has to be threaded through argv.
if (args.live) {
  process.env.ROOT_MNT = "/";
  console.error("run: --live: the target is this system (ROOT_MNT=/)");
}

// up and down touch the disk, and every step asserts root, so escalate once
// here instead of making the caller remember. list and plan are read-only, so
// they stay unprivileged and answer without a password prompt.
if ((args.command === "up" || args.command === "down") && process.getuid?.() !== 0) {
  const raised = Bun.spawn(
    ["sudo", process.execPath, "run", import.meta.path, ...process.argv.slice(2)],
    { stdin: "inherit", stdout: "inherit", stderr: "inherit", env: process.env },
  );
  process.exit(await raised.exited);
}

const dir = resolveLadder(args.ladder);

/** The skip list belongs to the main ladder, not to any other directory. */
const skip = dir === resolve(MAIN_LADDER) ? SKIP_IN_MAIN : new Set<string>();
const usage =
  "usage: bun run ladder [ladder] list|plan|up|down [from] [to] [--only step] [--live]";

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
    console.log(dir);
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
