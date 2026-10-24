/**
 * ---
 * script: 60-net.ts
 * desc: Enables NetworkManager so nmcli works on the Arch side.
 * needs: 40-packages.ts up
 * up: systemctl enable NetworkManager.service
 * down: systemctl disable NetworkManager.service
 * revisit: 2026-12-21
 * ---
 *
 * Deliberately does not stop systemd-networkd, dhcpcd or iwd: a fresh Arch
 * install usually has none of them enabled, and disabling one that Fedora
 * relies on would be a nasty surprise.
 */
import { fail, inArch, inArchSoft, main, needMount, ok, say } from "./lib.ts";

async function up(): Promise<void> {
  await needMount();
  await inArch("systemctl", "enable", "NetworkManager.service");
  say("NetworkManager enabled for next boot");
  say("not started now: the chroot shares the host's network namespace");
  say((await inArch("pacman", "-Q", "networkmanager").text()).trim());
}

async function down(): Promise<void> {
  await needMount();
  await inArchSoft("systemctl", "disable", "NetworkManager.service");
  say("NetworkManager disabled");
}

async function verify(): Promise<void> {
  const r = await inArchSoft("systemctl", "is-enabled", "NetworkManager.service");
  r.exitCode === 0 ? ok("NetworkManager is enabled") : fail("NetworkManager is not enabled");
}

await main({ up, down, verify });
