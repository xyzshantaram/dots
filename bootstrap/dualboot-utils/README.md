# dualboot-utils

Optional. Everything here exists only because two installed systems share a
disk. **Nothing in the main ladder depends on any of it**, and every key it reads
may be left unset.

It is its own ladder, run with the same runner from the repo root:

```
bun run ladder dualboot-utils list
bun run ladder dualboot-utils plan
bun run ladder dualboot-utils up
```

Naming a ladder picks that one directory and reads only the steps directly
inside it, so the main ladder never picks these up and this one never reaches
back.

- `10-chainload-entry` — the other OS in the boot menu.
- `20-hibernate-mark` — both sides learn to label their own entry.

Order matters only in that the chainload entry has to exist before
`hibernate-mark` can put `(HIBERNATED)` in its title.

## Chainload entry

Adds `loader/entries/fedora.conf` on the ESP, pointing at the other OS's own EFI
binary:

```
EFI/fedora/shimx64.efi        Secure Boot
EFI/fedora/grubx64.efi        Secure Boot off
EFI/fedora/shimx64-fedora.efi
```

- Nothing is copied — that OS keeps owning its own kernels.
- Absent EFI directory means the step says so and stops; a single-boot machine
  sees no error.
- `OTHER_OS_EFI_DIR` and `OTHER_OS_LABEL` in `.env` change the directory and the
  menu title.

## Shared swap

Two installed systems sharing a swap partition means whoever hibernates owns it.
Booting the other starts its swap unit and discards the image — this already
happened once on this machine.

- Before hibernating, each side appends `(HIBERNATED)` to its own entry titles
  and sets its entry as the **one-shot** boot default.
- `hibernate-mark-clear.service` and the post-sleep hook both clear it: a resume
  does not re-run boot units, and an interrupted hibernation leaves a stale mark.
- It is a sign, not a lock. Picking the other entry by hand still costs you the
  session.

`hibernate-mark` installs on **both** systems — it detects which OS is running
and touches only that OS's entries, so one script serves both sides. It finds the
ESP at `/efi` or `/boot/efi`, whichever that OS uses.

## The shared ESP

The sleep hook unmounts `/efi` before the image is written and remounts it after.
Leaving it mounted means the other OS can write to it during a kernel update
while the hibernation image still believes its state, which leaves a stale FAT.

The homes are shared too, but are not dropped: both systems treat that partition
as `/home`, so unmounting it would take the running session's home with it.
