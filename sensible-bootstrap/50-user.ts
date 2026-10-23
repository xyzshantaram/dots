/**
 * ---
 * script: 50-user.ts
 * desc: Creates the Arch account with fish as login shell, uid 1000, and wheel sudo.
 * needs: 40-packages.ts up (fish, sudo)
 * up: useradd -u ARCH_UID -G wheel,input,uucp,video -s /usr/bin/fish, prompts for a password, writes /etc/sudoers.d/10-wheel
 * down: userdel -r and removes the sudoers drop-in
 * revisit: 2026-12-21
 * ---
 *
 * ARCH_UID 1000 is the convention for the first real account, and it is also
 * the number another distro's /home will have been recorded under. Matching it
 * is what makes a read-only drawer onto such a home readable without uid
 * remapping. Nothing is shared: /home/$ARCH_USER stays its own directory.
 */
import process from "node:process";
import {
  ARCH_UID, ARCH_USER, inArch, inArchSoft, main, needMount, removeArch, say,
  writeArch,
} from "./lib.ts";

const SUDOERS = "/etc/sudoers.d/10-wheel";

/**
 * video is not optional: brightnessctl's udev rules hand the backlight device
 * to group video, so without it the XF86MonBrightness keys fail silently in
 * niri. input is for reading input devices (/dev/input/event*), which the
 * dictation modifier watcher and tools/measure-taps.py both need.
 *
 * uucp, not dialout. Serial ports sit in dialout on Fedora and Debian, but
 * Arch's own 50-udev-default.rules assign tty[A-Z]*[0-9] to uucp, and there is
 * no dialout group at all - useradd exits 6 with "group 'dialout' does not
 * exist" rather than skipping it.
 */
const GROUPS = "wheel,input,uucp,video";

const userExists = async () => (await inArchSoft("id", ARCH_USER)).exitCode === 0;

async function up(): Promise<void> {
  await needMount();

  if (await userExists()) {
    say(`user ${ARCH_USER} exists; leaving it alone`);
  } else {
    if ((await inArchSoft("id", "-u", ARCH_UID)).exitCode === 0) {
      say(`uid ${ARCH_UID} already taken in the target; aborting`);
      process.exit(1);
    }
    await inArch(
      "useradd", "-m", "-u", ARCH_UID, "-G", GROUPS,
      "-s", "/usr/bin/fish", "-c", "Shan", ARCH_USER,
    );
    say(`created ${ARCH_USER} (uid ${ARCH_UID}, shell /usr/bin/fish)`);
  }

  // Re-assert the group list: an account created by an earlier run may be
  // missing one, and `usermod -aG` is idempotent.
  await inArchSoft("usermod", "-aG", GROUPS, ARCH_USER);

  say(`set a password for ${ARCH_USER}`);
  await inArch("passwd", ARCH_USER);

  await writeArch(SUDOERS, "%wheel ALL=(ALL:ALL) ALL\n", 0o440);

  const check = await inArchSoft("visudo", "-cf", SUDOERS);
  if (check.exitCode !== 0) {
    say("visudo rejected the drop-in");
    process.stderr.write(check.stderr.toString());
    process.exit(1);
  }
  say("wheel sudo enabled");
  say((await inArch("id", ARCH_USER).text()).trim());
}

async function down(): Promise<void> {
  await needMount();
  if (await userExists()) {
    const removed = await inArchSoft("userdel", "-r", ARCH_USER);
    if (removed.exitCode !== 0) await inArchSoft("userdel", ARCH_USER);
    say(`removed user ${ARCH_USER}`);
  }
  await removeArch(SUDOERS);
  say("removed sudoers drop-in");
}

await main({ up, down });
