/**
 * ---
 * script: 115-pam-fpr.ts
 * desc: Fingerprint login at the console and fingerprint-first sudo, plus asterisks while typing a sudo password.
 * needs: 40-packages.ts up (fprintd), 50-user.ts up
 * up: adds `auth sufficient pam_fprintd.so` to system-local-login and a bounded pam_fprintd line to sudo, and writes /etc/sudoers.d/10-pwfeedback
 * down: restores both PAM files from their .pam-save copies and removes the sudoers drop-in
 * revisit: 2026-12-21
 * ---
 *
 * pam_fprintd.so as `sufficient` only prompts for a finger when this user has
 * an enrolment, and pam_unix stays below it, so a dead sensor falls back to the
 * password rather than locking anyone out.
 *
 * Known trade, accepted by the user: fingerprint auth in sudo means a
 * background process can provoke a prompt and get approved by an unintended
 * touch (CVE-2024-37408). max-tries=3 timeout=30 is roomier than a single
 * 10-second attempt: the sensor takes a moment to wake, and a prompt that
 * gives up mid-reach leaves you typing the password anyway. It also widens
 * the window that trade is about, which is the deliberate half.
 *
 * pwfeedback shows one asterisk per typed character. That leaks password
 * length to anyone watching the terminal; it is also what makes the prompt
 * behave like a normal password field.
 *
 * Enrolment is per machine: Fedora's /var/lib/fprint does not carry over.
 * After the first boot, shan runs `fprintd-enroll` once.
 */
import process from "node:process";
import {
  ARCH_USER, backupOnce, fail, inArch, inArchSoft, main, needMount, ok, readArch, removeArch,
  restoreBackup, say, writeArch,
} from "./lib.ts";

const LOCAL_LOGIN = "/etc/pam.d/system-local-login";
const SUDO = "/etc/pam.d/sudo";
const PWFEEDBACK = "/etc/sudoers.d/10-pwfeedback";

const LOCAL_LOGIN_LINE = "auth       sufficient   pam_fprintd.so";
const SUDO_LINE = "auth       sufficient   pam_fprintd.so max-tries=3 timeout=30";

/** Any existing fprintd auth line, whatever options it carries. */
const FPR_LINE = /^\s*auth\s+sufficient\s+pam_fprintd\.so\b/;

/** Puts the fprintd line at the top of a PAM file, keeping the #%PAM-1.0 header first.
 *
 * Rewrites an existing fprintd line instead of adding another. The options on
 * that line are the thing being tuned, and matching only the exact new line
 * meant a changed max-tries stacked a second `sufficient pam_fprintd` above
 * the old one, where the first would answer the prompt and the second never
 * run.
 */
async function prepend(rel: string, line: string): Promise<void> {
  const current = await readArch(rel);
  if (current === null) {
    say(`${rel} does not exist in the target; skipping`);
    return;
  }

  const lines = current.split("\n");
  const existing = lines.findIndex((l) => FPR_LINE.test(l));
  if (existing !== -1) {
    if (lines[existing].trim() === line.trim()) {
      say(`${rel} already has the fprintd line`);
      return;
    }
    await backupOnce(rel);
    lines[existing] = line;
    await writeArch(rel, lines.join("\n"));
    say(`updated the fprintd line in ${rel}`);
    return;
  }

  await backupOnce(rel);
  const body = current.startsWith("#%PAM-1.0")
    ? current.replace(/(#%PAM-1\.0\n)/, `$1${line}\n`)
    : `${line}\n${current}`;
  await writeArch(rel, body);
  say(`added pam_fprintd to ${rel}`);
}

async function up(): Promise<void> {
  await needMount();

  await prepend(LOCAL_LOGIN, LOCAL_LOGIN_LINE);
  await prepend(SUDO, SUDO_LINE);

  await writeArch(
    PWFEEDBACK,
    "# Show asterisks while typing a sudo password.\nDefaults pwfeedback\n",
    0o440,
  );

  const check = await inArchSoft("visudo", "-cf", PWFEEDBACK);
  if (check.exitCode !== 0) {
    say("visudo rejected 10-pwfeedback:");
    process.stderr.write(check.stderr.toString());
    process.exit(1);
  }
  say("pwfeedback enabled");

  await writeArch(
    "/usr/local/bin/fpr-led",
    await Bun.file(`${import.meta.dir}/files/fpr/fpr-led`).text(),
    0o755,
  );
  await writeArch(
    "/etc/systemd/system/fpr-led.service",
    await Bun.file(`${import.meta.dir}/files/fpr/fpr-led.service`).text(),
  );
  await inArch("systemctl", "enable", "--now", "fpr-led.service");
  say("fpr-led lights the power button while the reader waits");

  say(`after first boot, as ${ARCH_USER}: fprintd-enroll`);
}

async function down(): Promise<void> {
  await needMount();

  await inArchSoft("systemctl", "disable", "--now", "fpr-led.service");
  for (const rel of ["/usr/local/bin/fpr-led", "/etc/systemd/system/fpr-led.service"]) {
    await removeArch(rel);
  }

  for (const file of [LOCAL_LOGIN, SUDO]) {
    say(
      (await restoreBackup(file))
        ? `restored ${file}`
        : `no backup for ${file}; left as is`,
    );
  }
  await removeArch(PWFEEDBACK);
  say("removed pwfeedback drop-in");
}

async function verify(): Promise<void> {
  for (const f of [LOCAL_LOGIN, SUDO]) {
    ((await readArch(f)) ?? "").includes("pam_fprintd.so")
      ? ok(`${f} has pam_fprintd`) : fail(`${f} has no pam_fprintd`);
  }
  ((await readArch(PWFEEDBACK)) ?? "").includes("pwfeedback")
    ? ok("pwfeedback enabled") : fail("pwfeedback missing");
  (await readArch("/usr/local/bin/fpr-led")) !== null
    ? ok("fpr-led installed") : fail("fpr-led missing");
  const enabled = await inArchSoft("systemctl", "is-enabled", "fpr-led.service");
  enabled.exitCode === 0 ? ok("fpr-led enabled") : fail("fpr-led not enabled");
}

await main({ up, down, verify });
