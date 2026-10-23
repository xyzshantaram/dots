# bootstrap

A ladder of small, reversible steps that turn an Arch install done by the
installation guide into a usable niri session.

Nothing here reinstalls Arch. Start from the guide: partition, format, mount,
`pacstrap`, `genfstab`, `arch-chroot`, locales, `bootctl install`. Then take the
rest of the way with this repo.

One rule shapes everything: **the ladder depends on nothing outside itself.**
Every asset it installs — fonts, wallpaper, scripts — is vendored under
`files/`. There is no reaching into another OS for a file, so the result is
reproducible and it still works when that other OS is gone.

Things that genuinely have to cross an OS boundary moved to
[`dualboot-utils/`](dualboot-utils/README.md) and are optional.

## What this is for

Get to a system that boots, shows a terminal, and lets the UI be developed
live, without pretending the result is finished. Concretely:

- `niri` + `wezterm` + `quickshell` (`qs`), so a shell can be iterated on
- `vicinae` as the launcher, `swaync` for notifications, `gtklock` to lock
- Tapping CapsLock (your Super) opens the launcher
- NetworkManager and `nmcli`, `paru`, `firefox`, `podman`
- Fingerprint login and sudo, keyd for the Super key
- A `tuigreet` login prompt, with fingerprint working at it for free
- Hibernate-only power behaviour, ported from `../battery-sleep-configs`
- Kernels kept on the ESP automatically, with a known-good fallback
- A minimal fish config: prompt and fortune greeting, nothing else
- The NPU dictation stack, ported from `../dictation-service`

Everything is one toolchain: TypeScript run with Bun. The optional crossover
bits in `dualboot-utils/` follow the same rule.

## How it runs

Every step is TypeScript, run with Bun, and takes one argument:
`up` or `down`. `do`/`undo` were the obvious names but `do` is a reserved word
in JavaScript, so the verbs are `up`/`down`.

Run everything from the repo root, one directory up. The runner and the `.env`
live there; the steps live here.

```
cp .env.example .env                    # then fill in the UUIDs

bun run ladder list                     # see the ladder
bun run ladder plan                     # what up would run, no changes
bun run ladder up                       # everything, in order
bun run ladder up 40-packages           # resume from a step to the end
bun run ladder up --only 70-keyd        # or exactly one step
bun run ladder down 150-kernel-sync 12-esp-efi   # unwind a range backwards

bun run ladder up --live                # install into this system, not a target

bun run ladder sdks up                  # the optional developer-toolchain ladder

bun run ladder dualboot-utils up        # the optional two-system ladder
```

### A mounted target, or the running system

`ROOT_MNT` in `.env` says where the ladder writes:

| value | means |
| --- | --- |
| `/mnt/arch` | a target root mounted by `10-mount.ts`, as during a first install |
| `/` | the running system |

`--live` is the same thing as `ROOT_MNT=/` for one run:

```
bun run ladder up --live
bun run ladder up --live --only 110-niri
```

Nothing else changes. `10-mount` and `20-chroot` become no-ops — there is
nothing to mount and nothing to chroot into — every other step writes to `/`
instead of `$ROOT_MNT`, and commands run directly instead of through
`arch-chroot`. All of that lives in `lib.ts`: `at()` prefixes a target path,
and `inArch()`/`asUser()` choose the runner. `needMount()` becomes a check that
the running system is Arch-family, so pointing the ladder at the wrong machine
still stops it. `verify.sh` already understood the running system.

One step is guarded rather than merely adjusted: `10-mount.ts down` would
otherwise try to unmount `/`.

`bun run ladder` takes care of sudo: `up` and `down` escalate once, themselves.
`list` and `plan` are read-only, so they never ask for a password.

The runner stops at the first failure and prints the step to re-run. Every step
is idempotent on `up`: re-running it is safe and usually a no-op.

Progress goes to stderr, so stdout stays pipeable.

### The ladder

| step | does |
| --- | --- |
| `setup-bun.sh` | optional: installs Bun system-wide, smoke-tests Bun Shell |
| `00-check` | read-only preflight: UUIDs, block devices, ESP room, host tools |
| `10-mount` | btrfs `subvol=@` → `/mnt/arch`, ESP → `/mnt/arch$ESP_MOUNT` (a no-op when live) |
| `12-esp-efi` | moves the ESP mountpoint from `/boot/efi` to `/efi` in fstab |
| `20-chroot` | wrapper for `arch-chroot` (helper, skipped by `run.ts`) |
| `30-keys` | pacman keyring init and refresh |
| `40-packages` | every package the Arch side needs |
| `50-user` | `shan`, uid 1000, fish, wheel/input/uucp/video, wheel sudo |
| `60-net` | enables NetworkManager |
| `70-keyd` | CapsLock as Meta, Copilot key as `Pause` |
| `72-trackpoint` | tags the TrackPoint as a pointing stick, so libinput and niri treat it as one |
| `80-fonts` | vendored CMU Serif; Inter as the default sans-serif; full hinting |
| `90-fish` | prompt, fortune greeting, git prompt colours |
| `95-nanorc` | `/etc/nanorc`, the system-wide nano config |
| `100-wezterm` | WezTerm config; background comes from `~/wallpapers` |
| `105-niri-gestures` | rebuilds niri with the configurable touch-gesture patch set |
| `110-niri` | niri config, the `vicinae` launcher, and the mic-mute helper |
| `112-wallpaper` | `wallpaper-random` + swaybg, so each session picks a random wallpaper |
| `114-udisks` | `udiskie` in the session, so USB drives and cards mount on insert |
| `115-pam-fpr` | fingerprint at the console and for sudo; asterisks on sudo |
| `117-greetd` | greetd + tuigreet as the login prompt; fingerprint comes along |
| `120-quickshell` | starter `shell.qml` so `qs` shows something |
| `130-paru` | `paru` built from source against this system's libalpm |
| `135-icons` | Boston icon theme, applied to GTK 3 and 4 |
| `145-hibernate` | `resume` hook, wake-source mask, suspend→hibernate, logind |
| `147-idle` | swayidle: 20 min on AC, 10 min on battery |
| `150-kernel-sync` | `esp-sync` + pacman hook, `arch.conf`, `arch-known-good.conf` |
| `155-battery` | charge thresholds, audio power save, wifi powersave, backlight |
| `170-dictation` | FastFlowLM, Voxtype, the preview strip, the Pause-key toggle |
| `180-snapper` | `@snapshots` at `/.snapshots`, snapper + snap-pac, post-bootstrap snapshot |

Two moved out, because they only exist when two systems share a disk:
`140-fedora-entry` became `10-chainload-entry`, and `160-boot-marker` plus
`fedora-side.sh` became one `20-hibernate-mark` step. They are a second ladder,
`run.ts --ladder dualboot-utils`. See that directory's README.

The developer toolchain is a third ladder, [`sdks/`](sdks/README.md): cmake,
unzip, autoconf, fnm carrying the Node LTS, pnpm, Command Code, rustup and Zed.
None of it is needed for a session, so it is optional — but one main-ladder step
does care about rustup: `105-niri-gestures` builds the patched niri with it, and
installs it itself when the sdks ladder has not run.

### Checking it

```
sudo ./verify.sh
```

Read-only, and safe to run from Fedora against the mounted target **or** from
the booted Arch system. It checks UUIDs, mounts, the account and its groups,
that every `linux`/`initrd` line in every boot entry points at a file that
exists, hibernation wiring, the session files, and snapshot state. Exit 1 means
something is actually wrong; warnings are things not done yet.

### Snapshots

`180-snapper` is deliberately last. It creates `@snapshots` if it is missing,
installs `snapper` and `snap-pac`, and then takes one snapshot described
`sensible-bootstrap complete`.

That snapshot is the rollback point for everything above it. `snap-pac` then
takes a pre/post pair around every future pacman transaction, so an upgrade
becomes `snapper undochange <pre>..<post>` instead of a manual snapshot first.

`@snapshots` must be a sibling subvolume, not a directory: a snapshot stored
inside the subvolume it snapshots ends up containing the previous ones. If it
is missing, the step creates it from the btrfs top level.

The order this happens in is not the obvious one, and getting it backwards fails
outright. `snapper create-config` builds `/.snapshots` itself, as a subvolume
nested inside `@`, and it will not reuse anything already at that path — with a
mount, or even an empty directory, in the way it stops with:

```
btrfs_util_create_subvolume_fd() failed, errno:17 (File exists)
```

So the step clears `/.snapshots` first, runs `create-config`, deletes the nested
subvolume snapper just made, and only then mounts `@snapshots` in its place with
`750` permissions. ArchWiki, *Snapper*, "Configuration of snapper and mount
point" describes exactly this sequence. Mounting `@snapshots` before
`create-config` is the mistake to avoid.

Rolling back `/` also rolls back `/boot`, while the ESP still holds whatever
kernel `esp-sync` copied there last. After a rollback, run `esp-sync` by hand
so the two agree.

## One thing that will bite you

### `/tmp` inside `arch-chroot` is a fresh tmpfs every time

Steps run through `arch-chroot`, and `arch-chroot` mounts a **new tmpfs over
the target's `/tmp` on every invocation** (see `chroot_add_mount` in
`/usr/bin/arch-chroot`). Each `inArch()`/`asUser()` call is its own invocation,
so anything written to `/tmp` in one call is gone before the next one looks for
it.

That bit `130-paru` hard: it built `paru` successfully as the user, then
asked for the package in a separate call and found nothing, because the file had
gone with the tmpfs it was written to. Anything that has to survive from one
step call to the next belongs under `/var/tmp`, which is a plain directory on
the target's root filesystem — and is what FHS reserves it for.

This is worth remembering before adding a step that builds or stages something.

### AUR `-bin` packages break when a core library bumps its soname

`paru` links `libalpm` directly, so a prebuilt binary only works while its
soname matches the pacman in the machine. `paru-bin 2.1.0` needs
`libalpm.so.15`; pacman 7.1 ships `.16`, so every call to it died with `cannot
open shared object file`. You can see the mismatch without running anything:

```
$ readelf -d /usr/bin/paru | grep alpm
 0x0000000000000001 (NEEDED)  Shared library: [libalpm.so.15]
$ ls /usr/lib/libalpm.so*
/usr/lib/libalpm.so -> libalpm.so.16
```

Nothing in the ladder caught that. The `-Sy` at the end of `130-paru` treats
failure as non-fatal, and the next step reported a bare exit code 127.

So `130-paru` builds `paru` from source, which links against this system's own
libalpm — which is what the `alpm` crate's build probe demands anyway
(`atleast_version("16.0.0")`). The Rust toolchain goes in as a dependency and
comes out again afterwards, so the finished system does not carry ~324MB of
compiler.

The general rule: for anything linking a core Arch library, prefer a source
build over `-bin`, and check the binary actually **runs** rather than trusting
that it installed. `verify.sh` now does exactly that for paru.

### AUR packages that work out their own source URL by scraping break quietly

`boston-icon-theme` builds its source array by scraping a webpage while makepkg
is still parsing the PKGBUILD:

```
_od_url=$(curl -s "https://www.opendesktop.org/dl?file_id=..." -X POST ... |
          sed -n 's|^ *<a href="\([^"]*\)">Please click here</a>.*$|\1|p')
source=($_od_url)
```

opendesktop.org now answers that request with a bot challenge — Anubis, the same
proxy the AUR itself uses — so the scrape returns nothing, `_od_url` is empty,
and `source=()` collapses to an empty array. makepkg then reports:

```
==> ERROR: Integrity checks (sha256) differ in size from the source array.
```

which points at the checksums and says nothing about the empty source list. The
package has been flagged out of date since September 2026 and cannot be built by
anyone.

`135-icons` uses `boston-icon-theme-git` instead, which clones the upstream
GitHub repo with `sha256sums=('SKIP')` and provides/conflicts with the plain
package, so it is a drop-in replacement.

The general rule: a PKGBUILD that runs a command to work out its own source URL
is at the mercy of whatever that command talks to, and it fails at parse time —
before anything is downloaded, so there is nothing in `src/` to look at.

### AUR packages that sign their sources need their keys imported

`voxtype-bin` ships a `.asc` beside every downloadable binary and lists the keys
it accepts in `validpgpkeys`. Nothing fetches those keys — an AUR helper
normally does that step, and asking makepkg directly does not:

```
==> Verifying source file signatures with gpg...
    voxtype-1.1.1.tar.gz ... FAILED (unknown public key A3FC9F33FD209279)
==> ERROR: One or more PGP signatures could not be verified!
```

The key named there is a 16-character **key ID**, which is just the tail of the
40-character fingerprint in `validpgpkeys` — worth knowing, because the two look
like unrelated things in the two places. `aurInstall` reads `validpgpkeys` out
of the package's `.SRCINFO` and imports anything missing before it builds,
fetched as plain HTTPS GETs rather than through gpg's keyserver protocol, which
would put `dirmngr` in the path for what is only a download.

The key only has to be **present**, not trusted: makepkg checks the signing
fingerprint against `validpgpkeys` itself and never asks whether the key is
trusted. So there is no need to sign it locally — and `--skippgpcheck` would be
removing the check rather than fixing what broke.

### Hibernation needs swap sized for RAM, and a shared one has an owner

Hibernation writes an image somewhere big enough to hold it. That has to be a
real swap partition — zram cannot hold a hibernation image — and it should be
at least the size of RAM. `145-hibernate` sets it up; the `resume=` UUID comes
from `SWAP_UUID` and goes on both boot entries via `150-kernel-sync`.

Where this gets sharp is a machine with two installed systems sharing that
partition. Whichever hibernates owns it, and booting the other one starts that
system's swap unit, which discards the image. That already happened once here:
a reboot landed on Arch because `arch.conf` was the default entry, and the other
system's hibernation state was gone.

The mitigation is `dualboot-utils/20-hibernate-mark.ts`, which labels the
hibernating entry `(HIBERNATED)` and sets it as the **one-shot** boot default,
so the menu shows who holds an image and points at that entry. It is a sign,
not a lock: picking the other entry by hand still costs you the session.

The only way to make the collision impossible is to stop sharing — one side
loses hibernation and lives on zram alone.

Both systems mount the shared home at `/home`, so there is no second mount to
gate: the account whose uid is 1000 owns its own files from either side.

## ESP mountpoint: moved to `/efi`

This install put the ESP at `/boot/efi`. ArchWiki calls that *"historical and
now discouraged"* and recommends `/efi`. `12-esp-efi` rewrites that one line in
the target's fstab and remounts; the `.env` key `ESP_MOUNT=/efi` is what every
later step reads.

Left behind: an empty `/boot/efi` directory, which is harmless.

If this Arch install is ever redone from scratch, mount the ESP at `/efi` from
the start — then `12-esp-efi` is a no-op.

## Key bindings

`Mod` is Super, and `70-keyd` makes CapsLock act as Meta — so either the real
Super key or CapsLock works as `Mod`.

**Tapping CapsLock or the physical Super key opens the launcher.**
This cannot be done in niri: a bind has to name a key, and nothing fires on the
*release* of Super with no other key pressed. niri's own tracker has this open as
a feature request (`niri-wm/niri#4142`, `#4651`). So the tap is resolved one
layer down, in keyd, for both keys:

```
capslock = overload(meta, f13)
leftmeta = overload(meta, f13)
```

Held, either key is Meta. Tapped, either emits evdev `KEY_F13`, and that key is
bound in `config.kdl` to `vicinae toggle`. The bind is written `XF86Tools`, not
`F13`, and that is not a typo: this keymap maps `<FK13>` to `[ XF86Tools ]`, so a
bind named `F13` parses, validates, and then never matches anything. Confirm with

```
xkbcli compile-keymap | grep 'key <FK13>'
```

`f23` belongs to the Copilot key.

The tap action does not fire when another key is pressed during the hold, so
`Mod+T` and the rest are unaffected — that property is what makes `overload()`
usable for a modifier at all.

keyd's own `check` flagged the previous form — a bare `capslock = leftmeta` —
with *"You should use layer(meta) instead of assigning to leftmeta directly."*
`overload(meta, …)` is the recommended shape, so this change also clears a
warning that was already there.

**The tap window is set to 200 ms.** A press held longer than that is treated
purely as a modifier and the tap action is ignored, which stops a slow
hold-and-release from opening the drawer by accident:

```
[global]
overload_tap_timeout = 200
```

200 ms came from `tools/measure-taps.py`, which measures real press durations
and suggests a value:

```
python3 tools/measure-taps.py          # Ctrl+C when done
```

Live events go to stderr, the summary to stdout so it can be piped. It needs
read access to `/dev/input` — the `input` group, which `50-user` already grants.

The trade-off is one-sided, and it is worth knowing which way to turn the knob:
raising it makes a stray drawer more likely, lowering it makes a slow tap
silently do nothing. Setting it *at* your longest tap means borderline presses
fall on the wrong side, so if drawer opens feel unreliable, raise it.

## The launcher

A tap of CapsLock or Super runs `vicinae toggle`. `Mod+V` opens the clipboard
history through a deeplink, and `Mod+D` is the floating toggle.

`vicinae` is a server plus a client. The client is what the bind runs; the
window it opens is drawn by a daemon that has to already be up. That daemon
comes from a **systemd user unit**, `vicinae.service`, which the package ships
**disabled** — so a session that has only ever run the client shows nothing at
all when the key is pressed.

`110-niri` enables it by writing the symlink `systemctl --user enable` would
create, under `~/.config/systemd/user/graphical-session.target.wants/`. It
cannot call `systemctl` itself: the ladder runs in a chroot, and a chroot has no
user session to talk to. `graphical-session.target` is started by the niri
session, which is when the daemon should come up.

It is AUR-only (`vicinae-bin`), so it is installed by `aurInstall` in
`110-niri`, not by `40-packages`.

If the launcher stops opening, the daemon is the thing to check: `vicinae ping`,
then `systemctl --user status vicinae.service`. The unit ships disabled; `110`
enables it by symlink, and when the target is the running system it also starts
it, because `graphical-session.target` has already been reached by the time the
ladder writes that link.

## Touchpad gestures, and the niri patch set

niri's touchpad gestures are hardcoded: three fingers switch workspaces and
scroll the view, four open the overview, and none of it is configurable. This
machine wants three fingers on the overview and four for navigation, so
`105-niri-gestures` builds niri with
[niri-wm/niri#3771](https://github.com/niri-wm/niri/pull/3771), which turns the
gestures into ordinary bind triggers.

- The patch series is vendored in `files/niri-gestures/`, pinned to the exact
  upstream commit it was rebased onto. Bumping that commit means regenerating
  every patch.
- The build is packaged as `niri-gestures`, which `provides`/`conflicts` `niri`,
  so `pacman -U` replaces the stock package cleanly.
- The binds live in `config.kdl` like any others:
  `TouchpadSwipe fingers=3 direction="up" { open-overview; }`.
- **The config only validates against this build.** On the stock `niri`,
  `niri validate` rejects `TouchpadSwipe`, which is why `105` runs before `110`.

It builds with **rustup's** cargo, not with the repositories' `rust` package, so
makedepends names no rust provider — makepkg could not check a rustup toolchain
anyway — and the PKGBUILD puts `~/.cargo/bin` on PATH itself.

That combination has one trap, found the hard way and recorded in the PKGBUILD:
makepkg's `lto` option compiles C with `-flto=auto`, which turns libspa's C shim
into GCC LTO bytecode, and rustup's rustc links with `rust-lld`, which reads
LLVM bitcode but not GCC's. The link then fails with

```
rust-lld: error: undefined symbol: libspa_rs_type_video_format
```

`options=('!lto')` in the PKGBUILD is the fix; the archive and its symbols were
always fine.

Exit: when the PR (or an equivalent) lands upstream, delete
`105-niri-gestures.ts`, `files/niri-gestures/` and the `TouchpadSwipe` binds,
and go back to the `niri` package. A `pacman -Syu` that moves the repo's niri
past 26.04 will offer to swap the package back out on its own.

## Fonts and hinting

`Inter` is the default `sans-serif`. The Noto families stay behind it in the
family list, so characters Inter has no glyph for — CJK, and the rest — still
resolve. That is fontconfig's ordinary per-character fallback; nothing has to
declare it.

| file | does |
| --- | --- |
| `98-noto-emoji-fallback.conf` | makes Noto Color Emoji a `sans-serif` candidate |
| `99-inter-sans.conf` | prepends Inter to `sans-serif` |
| `99-hinting-full.conf` | `hintstyle=hintfull`, overriding `10-hinting-slight.conf` |

The numbering is load-bearing. The emoji alias puts an emoji font into the
`sans-serif` list, and a file that prepends Inter has to load *after* it or the
emoji font can come out on top — which is the state this machine reached on its
own, with `fc-match sans-serif` answering `Noto Color Emoji`.

`80-fonts` fails the run if `sans-serif` does not resolve to `Inter`. Asking for
the family by name, which the rest of its checks do, passes on the broken setup
too.

## Removable media

USB drives and cards mount on insert through `udisks2` and `udiskie`, and land
under `/run/media/shan/<label>`:

```
udiskie-umount -a            # unmount everything
udiskie-umount -d <path>     # unmount and power the device down
udiskie-info -a              # what udiskie can see
```

**`udiskie` runs from the niri session, not as a systemd user service, and that
is the whole design.** ArchWiki, udisks: what a user may do through udisks is
decided by polkit, and the stock rules that allow mounting without a password
match an *active* user session. A unit started outside the graphical session has
no session to match, so every mount is challenged and automounting looks like it
silently does nothing. `spawn-at-startup` keeps it inside the session logind
already knows about.

`udisks2.service` is deliberately **not** enabled. `udisksd` is D-Bus activated
on first use, which is what the same wiki page recommends.

`~/.config/udiskie/config.yml` is where the behaviour lives. The tray icon is
off, because niri has no status-notifier host; `notify` is on and reaches
`swaync`. `file_manager` is deliberately unset — setting it, e.g. to `nautilus`,
opens a window on every insert.

If mounts are ever *refused* rather than silent, the session was not seen as
active and the fallback is a polkit rule for the `storage` group; udiskie's own
wiki carries it. Nothing here needs it while the session is active.

## Login

`117-greetd` installs `greetd` with the `tuigreet` console greeter. The prompt
is a TUI on tty1 instead of a bare getty, and F3 lists sessions found in
`/usr/share/wayland-sessions` — the niri package puts `niri.desktop` there with
`Exec=niri-session`, which is also what `--cmd` preselects.

**Fingerprint at the greeter needs no work, for an Arch-specific reason.**
Arch's greetd ships `/etc/pam.d/greetd` containing:

```
auth       include      system-local-login
```

and `115-pam-fpr` already prepends `auth sufficient pam_fprintd.so` to that
file. So the greeter inherits fingerprint auth from a rule written for console
login. Nothing in `117-greetd` touches PAM, and adding a second `pam_fprintd`
line to `/etc/pam.d/greetd` would just be a copy of the same rule.

That does **not** transfer to Fedora, whose greetd instead does
`auth substack system-auth` — which bypasses `system-local-login` entirely.

The greeter is optional and fully reversible: `down` disables
`greetd.service`, restores the shipped config and removes both packages, and
tty1 console login comes back on the next boot. `verify.sh` reports its absence
as a warning, not a failure.

Two things worth knowing:

- **The power menu needs a polkit rule, and gets one.** The greeter runs as a
  system service with no logind session, so polkit's defaults — which grant
  power actions to local *active-session* users — never match it, and F12 would
  do nothing. `files/greetd/49-greeter-power.rules` grants `power-off`,
  `reboot`, `suspend` and `hibernate` to the `greeter` account alone, plus the
  `-multiple-sessions` variants, which are the actions actually consulted when
  someone else is logged in on tty2. The `49-` prefix is load-bearing: polkit
  takes the first matching rule and `50-default.rules` is the system's.

  Scope, plainly: this lets one nologin system account power the machine off
  without a password. Anyone standing at the console can already do that at the
  firmware level, and `greeter` cannot be logged into. Nothing else is granted —
  the rule explicitly does not answer for `login1.manage` or for any other user.

- `greetd.service` declares `Conflicts=getty@tty1.service`, so it takes tty1 on
  its own — there is no getty to mask by hand. Console login still works from
  tty2 upward.

## Hibernation

- Lid close hibernates, immediately, through logind. No desktop environment
  holds a lid inhibitor here.
- Every `systemctl suspend` is redirected to hibernate by a drop-in on
  `systemd-suspend.service`.
- Idle hibernation comes from `swayidle`, not logind: logind only reports idle
  when the session says so, and niri does not. niri implements
  `ext-idle-notify-v1`, which is what swayidle listens to.
- Wake source: the power button. `LID` is masked on purpose, so opening the lid
  mid-write cannot roll the hibernation back.
- `resume=` is on both boot entries; `image_size=0` asks for maximum
  compression because 42 GiB of RAM has to fit in 48 GiB of swap.
- Arch's initramfs is busybox-based, so `145-hibernate` adds the `resume` hook
  after `udev` and rebuilds. Without it the image is written and never resumed.

## Kernels

`150-kernel-sync` keeps two sets on the ESP:

- `/EFI/arch/current/` — what `arch.conf` boots
- `/EFI/arch/previous/` — what `arch-known-good.conf` boots

On each kernel update the pacman hook (`PostTransaction`, after mkinitcpio)
copies the new images in and rotates the old `current` pair to `previous`. So
"known good" is the kernel you were running before the update.

The first sync seeds `previous` from `current`, so the fallback resolves from
install time rather than only after the first update. That matters because
systemd-boot does **not** check whether an entry's files exist — it assembles the
menu from `loader/entries/` and fails only when the entry is chosen. An empty
`previous` would therefore be a broken entry sitting in the boot menu, which is
worse than no entry at all. `verify.sh` fails on any entry referencing a file
that is not on the ESP.

Microcode rides inside the initramfs, embedded by the `microcode` hook, so there
is no `amd-ucode.img` to carry alongside it. Naming one would point an entry at
a file that does not exist.

## Dictation

- `flm` (FastFlowLM, `extra`, 1.0.9) serves Whisper on the NPU at
  `127.0.0.1:52625`.
- `voxtype` captures the microphone and types the transcript through `wtype`.
- `wtype` is wrapped by `dictation-strip`, which previews the text and lets it
  be accepted or cancelled. The wrapper is only on voxtype's `PATH`, and calls
  the real binary by absolute path so it cannot re-enter itself.
- The Copilot key arrives as `Pause` (keyd) and is bound in niri to
  `voxtype record toggle`.
- The NPU driver is the in-tree `amdxdna`; a sleep hook unloads it around
  hibernation, because its resume path times out and leaves the device dead.

Verify after the first boot:

```
flm validate          # expect an NPU line and firmware 1.1.x
xrt-smi examine       # XRT must see the NPU
```

### Why wtype and not eitype

`wtype` is voxtype's own preferred Wayland driver. It needs one thing — the
`zwp_virtual_keyboard_manager_v1` protocol — and niri advertises it. That single
fact is the whole dependency, and it is why no translation layer exists between
voxtype and the wrapper: voxtype emits wtype's argv, and the wrapper forwards
it.

`eitype` is voxtype's libei driver, added for GNOME and KDE, whose compositors
do not speak that protocol. Installing it here would have added an AUR package
for a code path niri never takes.

`dotool` stays in `driver_order` behind `wtype` as a fallback. It is
uinput-based, so it covers the non-US layout case wtype cannot, and it is why
the account stays in the `input` group. It also bypasses the preview strip:
if the wrapper exits non-zero, voxtype falls through to dotool and the strip
is not in that path.

## Undo

Every step's `down` is exact:

| step | undo |
| --- | --- |
| `12-esp-efi` | fstab line back to `/boot/efi`, remount |
| `40-packages` | `pacman -Rns` over the same list |
| `50-user` | `userdel -r`, remove the sudoers drop-in |
| `70-keyd` | restore `.keyd-save`, disable the service |
| `95-nanorc` | restore the original `/etc/nanorc` |
| `105-niri-gestures` | remove the patch build, reinstall the stock `niri` |
| `115-pam-fpr` | restore `.pam-save` copies of both PAM files |
| `117-greetd` | disable greetd, restore the shipped config, remove the polkit rule, uninstall both packages |
| `135-icons` | remove GTK settings, uninstall the theme |
| `145-hibernate` | restore `mkinitcpio.conf`, rebuild without `resume` |
| `150-kernel-sync` | restore the original `arch.conf`, remove hook and ESP copies |
| `155-battery` | reset thresholds to 0/100, remove the drop-ins |
| `170-dictation` | remove units and files, uninstall the AUR packages |
| `180-snapper` | delete the config and fstab line; **snapshots stay on disk** |

`dualboot-utils/` has its own table in its README.

Anything that edits a file it did not create leaves a `*.pam-save`,
`*.keyd-save`, `*.hib-save`, `*.pre-esp-sync` or
`*.sensible-bootstrap-save` sibling. Those are gitignored.

Two `down`s deliberately under-delete, because the obvious version destroys
state that cannot be recovered:

- `150-kernel-sync` keeps `/EFI/arch/{current,previous}` unless
  `FORCE_ESP_WIPE=1` is set. Those images are the only thing the boot entries
  point at, so removing them first is how a working machine stops booting. It
  also refuses even then if the restored `arch.conf` still references them.
- `180-snapper` never deletes snapshots. `down` should not quietly remove a
  rollback point.

Down is *not* a reinstall: it returns the system to the post-install-guide
state, not to a blank partition.

## Wallpapers

`files/wallpapers/` is committed; **its contents are not**. Drop images in
there and `112-wallpaper` copies them into `~/wallpapers`. That is the directory
both consumers read:

- `swaybg` picks one at random at each session start, through
  `wallpaper-random`. With no images it exits cleanly and the session still
  starts, just without a background.
- WezTerm names one file for its own background — currently `Drangarnir.png`.
  Change the name in `files/wezterm/wezterm.lua`.

The repo carries the mechanism, not the images. That keeps large binaries out of
history and leaves the choice with whoever is looking at the screen.

## Known gaps

- No notification daemon config, just `swaync` at startup.
- `xwayland-satellite` is not installed, so X11 apps will not run.
- The keyd Copilot mapping emits `Pause`, which nothing else claims. If that
  key is wanted for something else later, change it in one place.
- The `(HIBERNATED)` marker only titles entries `systemd-boot` owns. Another
  OS whose real bootloader is grub keeps its own menu untouched.
- AUR packages (`135-icons`, `170-dictation`, and `110-niri` for vicinae) are
  built by `aurInstall` in
  `lib.ts`, not by an AUR helper: clone as the user, install the package's own
  build dependencies as root, `makepkg` without `-s`, then `pacman -U` as root.
  A helper installs through `sudo pacman -U`, and while that password prompt is
  answerable (see below), it needs someone at the keyboard, and every other step
  runs unattended. `aurInstall` never reaches for sudo, so no step is
  interactive. `paru` is still installed by `130-paru` for use on the running
  system, but no other step depends on it.

  Note that sudo *can* prompt inside the chroot: `arch-chroot` mounts a fresh
  devtmpfs on `/dev`, and `/dev/tty` still resolves to the terminal that started
  the run. The reason to avoid a helper is that the ladder would stall waiting
  for input, not that input is impossible.
- CMU Serif is vendored in `files/fonts/cmu/` (33 `.otf`, 7.7 MiB, OFL-1.1).
  That is the only binary in the repo. Wallpapers are deliberately not
  vendored — see the Wallpapers section above.
- A fresh machine has no wallpaper until `files/wallpapers/` is populated, so
  the first session starts plain. That is the accepted cost of keeping images
  out of the repo.
- No btrfs `@home` subvolume: `/home` lives in `@`, so a rollback of `@` also
  rolls back home directories. That is consistent with how this install was
  made, but it means `snapper undochange` is coarse.
