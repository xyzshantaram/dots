# dots

My dotfiles, plus `bootstrap/`: the ladder that takes a fresh Arch install to a working niri session.

## bootstrap

- Small reversible steps, one Bun/TypeScript file each, one verb: `up` or `down`.
- `bun run ladder up` runs them in order, stops at the first failure, and escalates itself — no `sudo` to type.
- `list` and `plan` are read-only and never ask for a password.
- `plan` shows a range without running it; `--only <step>` runs exactly one.
- `ROOT_MNT=/` in `.env` (or `--live`) points the whole ladder at the running system instead of a mounted target root.
- `bun run ladder dualboot-utils up` runs another ladder directory. No recursion.
- `bun run ladder software-dev up` is a separate, optional ladder: the developer toolchain (Node through fnm, pnpm, Command Code, rustup, Zed, uv).
- `bun run ladder creative up` is another optional one: ImageMagick, GIMP, Inkscape, Audacity, Kdenlive, OnlyOffice and Typst.
- Idempotent on `up`, exact on `down`.
- Depends on nothing outside itself — assets come from `files/`, never from another installed OS.
- `bun run ladder verify` is read-only and safe from either side.

```
run.ts            the runner, for every ladder
package.json      `bun run ladder`, `bun run verify`
.env              machine values, shared by both ladders (.env.example is the template)
bootstrap/
  dualboot-utils/   chainload entry, hibernation marker — only when two OSes share a disk
  software-dev/     developer toolchain — optional
  creative/         image, audio, video, office, typesetting — optional
  files/            vendored assets
```

## Shell

Quickshell, under `bootstrap/files/shell/`. The ladder copies the directory to
`~/.config/shell`, so a new file installs itself and no step names one.

```
Shell.qml        the one full-screen layer surface: strip, floats, catcher
bar/             the strip's widgets, each in its own file
float/           control centre, mixer, tray menu, bluetooth menu
components/      chips, entries, the notification card
core/            Theme, and the shared hover state
dock/            the dock
lock/            the lock screen
notices/         notification banners
services/        niri, wifi, bluetooth, pipewire, voxtype, OSD
```

- The window is full-screen and transparent, and `mask` is a union of
  rectangles. Opening the whole screen so a banner could be clicked kept the
  mask full-screen for a notification with no timeout, and the shell took every
  click and key on the machine.
- The strip reserves `Theme.barHeight` through `exclusiveZone`. Everything else
  in the window is click-through.
- A surface that takes typing is a `PanelWindow` with exclusive keyboard. A
  `PopupWindow` is a menu surface and never receives the keyboard, however the
  focus is asked for — that is what kept the Wi-Fi passphrase untypable.
- The shell owns `org.freedesktop.Notifications`. `swaync` must not be running:
  it takes the name and draws its own cards.
- One `Notice` component is both the banner and the panel row, so the two cannot
  drift apart.
- The dock is its own surface anchored to the bottom edge. The two pixels it
  reserves are the reveal trigger, so the mask only describes the plate, and the
  base flares into the screen edge as one `Shape` path rather than a rounded
  rectangle.

## Decisions

**Boot**

- Kernels live on the ESP: `/EFI/arch/current` (arch.conf), `/EFI/arch/previous` (arch-known-good.conf). `esp-sync` rotates on update.
- `previous` is seeded from `current` on the first sync, so the fallback resolves from install time.
- Microcode is inside the initramfs (`microcode` hook) — there is no `/boot/amd-ucode.img`.
- systemd-boot does not check that an entry's files exist. It lists them and fails on selection.
- Fedora is a chainload entry, not a copy of its kernels.

**Session**

- Super/CapsLock tap opens the launcher (`vicinae`). niri cannot bind a bare modifier, so keyd resolves it: `overload(meta, f13)`.
- Touchpad gestures are patched in, not configured: niri hardcodes the finger counts, so `105-niri-gestures` builds a pinned patch set (niri-wm/niri#3771) that turns them into binds. Drop it when upstream ships it.
- `overload_tap_timeout = 200` — measured with `tools/measure-taps.py`, not guessed.
- Login is greetd + tuigreet. Fingerprint is free on Arch: `/etc/pam.d/greetd` includes `system-local-login`.
- The greeter needs its own polkit rule for power buttons — it has no logind session, so polkit's defaults never match.
- udiskie starts from the niri session, not a user unit: polkit's stock rules need an *active* session.
- Typing goes through `wtype`, not `eitype`. Inter-key delay is voxtype's `type_delay_ms`, not the wrapper.
- Font is `FantasqueSansM Nerd Font Mono`. `Mono` keeps icons on the cell grid.
- Default sans-serif is `Inter`, with full hinting; Noto is the coverage fallback behind it.

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
- `WlrLayershell.layer: WlrLayer.Overlay` on a `PopupWindow` segfaults Quickshell; it is safe on a `PanelWindow`.
- An icon is found by desktop entry first. A launcher that wraps an app reports its own id, so fall back to `StartupWMClass`: Spotify's window is `spotify`, its entry is `spotify-launcher.desktop`.

## Assumptions

Already done by the install guide before the ladder runs:

- Fedora's nvme0n1p3 shrunk; new 50G btrfs nvme0n1p5 as the Arch root.
- Subvolumes `@` and `@snapshots`.
- mirrors, pacstrap, genfstab, arch-chroot.
- Locales: `en_US.UTF-8`, plus `en_SE`/`en_IN` for time, money and paper.
- systemd-boot installed, `loader.conf` with timeout, console-mode and default.
- Console font `ter-120b`.

## Open

- The ladder has run end to end here, and the result has been booted.
- Printer config deliberately not ported.
- No wallpaper until `files/wallpapers/` is populated.
- No particular disk layout assumed — everything comes from `.env`.
