/**
 * ---
 * script: 157-power-critical.ts
 * desc: Hibernates at 5% battery instead of at UPower's default 2%, using the battery percentage rather than a time estimate.
 * needs: 145-hibernate.ts up (there has to be a swap to hibernate into), 155-battery.ts up
 * up: edits /etc/UPower/UPower.conf in place: percentage policy, 5% critical, hibernate as the action
 * down: puts the three keys back to UPower's defaults
 * revisit: 2026-12-21
 * ---
 *
 * Three keys, edited in place rather than by writing a whole UPower.conf. The
 * file ships with every key commented out at its default, so replacing it
 * wholesale would freeze this machine at whatever upstream's defaults were on
 * the day this ran; sed-ing the three keys means the other forty keep tracking
 * the package.
 *
 * UsePercentageForPolicy=true is the important one. Without it UPower decides
 * from a *time* estimate, and a machine that has been draining hard reports
 * minutes rather than percent — so the trigger is late exactly when it matters.
 * PercentageCritical=5 is the ask; the upstream default is 2.
 *
 * CriticalPowerAction=Hibernate, not HybridSleep or PowerOff: 145-hibernate.ts
 * makes hibernation the only suspend this machine does, and landing at 5% to
 * find it suspended into RAM with the battery still draining is the failure
 * this avoids.
 *
 * UPower also emits a warning at PercentageLow (20% by default) and nothing
 * draws it — a bar that showed it would be the thing to add, and this step
 * deliberately does not invent a second notifier.
 */
import { inArch, inArchSoft, main, needMount, say } from "./lib.ts";

const CONF = "/etc/UPower/UPower.conf";

/** Key, our value, and what upstream ships, so down is a real undo. */
const KEYS: [string, string, string][] = [
  ["UsePercentageForPolicy", "true", "true"],
  ["PercentageCritical", "5", "2"],
  ["CriticalPowerAction", "Hibernate", "PowerOff"],
];

async function setKey(key: string, value: string): Promise<boolean> {
  const result = await inArch(
    "sed", "-E", "-i",
    `s/^#?${key}=.*/${key}=${value}/`,
    CONF,
  ).nothrow();
  return result.exitCode === 0;
}

async function up(): Promise<void> {
  await needMount();

  for (const [key, value] of KEYS) {
    if (!(await setKey(key, value))) {
      say(`could not set ${key}; ${CONF} may not exist`);
      return;
    }
  }

  const check = await inArchSoft("grep", "-E",
    "^#?(UsePercentageForPolicy|PercentageCritical|CriticalPowerAction)=", CONF);
  say(check.stdout.toString().trim() || "no such keys in UPower.conf");
  say("upower reads this at start; restart it to apply without a reboot");
}

async function down(): Promise<void> {
  await needMount();

  for (const [key, , upstream] of KEYS) {
    await setKey(key, upstream);
  }
  say("restored UPower's defaults for the three keys");
}

await main({ up, down });
