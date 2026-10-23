# dots

My dotfiles, plus `sensible-bootstrap/`: the ladder that takes a fresh Arch install to a working niri session.

## sensible-bootstrap

- Small reversible steps, one Bun/TypeScript file each, one verb: `up` or `down`.
- `bun run ladder up` runs them in order, stops at the first failure, and escalates itself — no `sudo` to type.
- `list` and `plan` are read-only and never ask for a password.
- `plan` shows a range without running it; `--only <step>` runs exactly one.
- `bun run ladder dualboot-utils up` runs another ladder directory. No recursion.
- Idempotent on `up`, exact on `down`.
- Depends on nothing outside itself — assets come from `files/`, never from another installed OS.
- `verify.sh` is read-only and safe from either side.

```
run.ts            the runner, for every ladder
package.json      `bun run ladder`, `bun run verify`
.env              machine values, shared by both ladders (.env.example is the template)
sensible-bootstrap/
  dualboot-utils/   chainload entry, hibernation marker — only when two OSes share a disk
  files/            vendored assets
  verify.sh
```

## Decisions

**Boot**

- Kernels live on the ESP: `/EFI/arch/current` (arch.conf), `/EFI/arch/previous` (arch-known-good.conf). `esp-sync` rotates on update.
- `previous` is seeded from `current` on the first sync, so the fallback resolves from install time.
- Microcode is inside the initramfs (`microcode` hook) — there is no `/boot/amd-ucode.img`.
- systemd-boot does not check that an entry's files exist. It lists them and fails on selection.
- Fedora is a chainload entry, not a copy of its kernels.

**Session**

- Super/CapsLock tap opens the app drawer. niri cannot bind a bare modifier, so keyd resolves it: `overload(meta, f13)`.
- `overload_tap_timeout = 200` — measured with `tools/measure-taps.py`, not guessed.
- Login is greetd + tuigreet. Fingerprint is free on Arch: `/etc/pam.d/greetd` includes `system-local-login`.
- The greeter needs its own polkit rule for power buttons — it has no logind session, so polkit's defaults never match.
- udiskie starts from the niri session, not a user unit: polkit's stock rules need an *active* session.
- Typing goes through `wtype`, not `eitype`. Inter-key delay is voxtype's `type_delay_ms`, not the wrapper.
- Font is `FantasqueSansM Nerd Font Mono`. `Mono` keeps icons on the cell grid.

**Packages**

- paru is built from source — the `-bin` binary needs `libalpm.so.15`, pacman 7.1 ships `.16`.
- AUR packages are built directly, not through a helper. A helper installs via `sudo pacman -U`, which stalls an unattended run.
- makepkg does not fetch `validpgpkeys`; `aurInstall` imports them.
- `boston-icon-theme` is unbuildable (its PKGBUILD scrapes a page now behind a bot challenge). Use `boston-icon-theme-git`.
- Serial gear is `uucp` — Arch has no `dialout`.

**Dual boot**

- Its own ladder: `bun run ladder dualboot-utils up`.
- `10-chainload-entry` chainloads that OS's own EFI binary — no kernels copied.
- Shared swap: whoever hibernates owns it. Each side labels its own entry `(HIBERNATED)` and sets it the one-shot default — a sign, not a lock.
- The sleep hook drops `/efi` before the image is written, so the other OS cannot leave a stale FAT behind.
- Both systems mount the shared home at `/home`: uid 1000 owns its own files from either side, no second mount.

**Repo**

- CMU Serif (33 `.otf`) is the only binary committed.
- `files/wallpapers/` is committed, its contents are not — the mechanism ships, not the images.
- Crossover steps read their optional keys via `opt()`, never `req()`, so a single-boot machine does not die.

## Gotchas

- `arch-chroot` puts a fresh tmpfs over the target's `/tmp` every call — stage under `/var/tmp`.
- `arch-chroot` refuses to run as non-root, and its error names neither.
- `pacman -Q` resolves provides; `pacman -R` does not. Use `pacman -Qo <file>`.
- sudo *can* prompt inside the chroot: `/dev/tty` resolves to the terminal that started the run.
- A wrong font name never errors — fontconfig substitutes silently.

## Assumptions

Already done by the install guide before the ladder runs:

- Fedora's nvme0n1p3 shrunk; new 50G btrfs nvme0n1p5 as the Arch root.
- Subvolumes `@` and `@snapshots`.
- mirrors, pacstrap, genfstab, arch-chroot.
- Locales: `en_US.UTF-8`, plus `en_SE`/`en_IN` for time, money and paper.
- systemd-boot installed, `loader.conf` with timeout, console-mode and default.
- Console font `ter-120b`.

## Open

- The ladder has run end to end here, but the result has not been booted yet.
- Printer config deliberately not ported.
- No wallpaper until `files/wallpapers/` is populated.
- No particular disk layout assumed — everything comes from `.env`.
