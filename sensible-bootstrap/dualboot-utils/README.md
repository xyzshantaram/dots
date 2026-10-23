# dualboot-utils

Optional. Everything in here exists only because two installed systems share a
disk. **Nothing in the ladder above depends on any of it**, and every key these
tools read may be left unset.

The base ladder builds a working Arch desktop from the install guide plus this
repo. These tools handle the parts that genuinely have to cross an OS
boundary, and nothing they depend on comes out of the other install either —
the assets they used to share are vendored into the base repo instead.

Run them by hand, from `sensible-bootstrap/`, in this order:

```
bun run dualboot-utils/drawer-mount.ts up        # read-only drawer + drawer-rw.service
bun run dualboot-utils/hibernate-mark.ts up      # both sides get the marker
bun run dualboot-utils/chainload-entry.ts up     # other OS in the boot menu
bun run dualboot-utils/drawer-export.ts up       # pull files in
```

`run.ts` never picks these up: it only globs `^\d+-.+\.ts$` in the parent
directory.

## The drawer

A read-only mount of another OS's home, so its files can be read from here.
Called a drawer rather than anything OS-named because that is all it is: a
read-only door.

```
DRAWER_UUID=...      that OS's /home partition
DRAWER_USER=...      whose home, inside it
DRAWER_MOUNT=/mnt/drawer
```

Mounted `ro,nofail,x-systemd.automount,x-systemd.idle-timeout=10min`, so it
appears on first access and disappears when idle. Unset `DRAWER_UUID` and
`drawer-mount.ts` simply says there is nothing to do.

Read-only on purpose. Writes land as that OS's user — ext4 stores owners as
numbers, and both installs usually have 1000 — so anything created here belongs
to someone over there.

### Read-write window

`drawer-mount.ts` installs one systemd unit:

```
systemctl start drawer-rw     read-write now, read-only again in 10 minutes
systemctl stop drawer-rw      read-only now
systemctl status drawer-rw    how long is left
```

It is a `Type=oneshot` unit with `RemainAfterExit=yes`. That second line is
load-bearing: `mount` returns in milliseconds, so without it `RuntimeMaxSec`
would fire immediately and there would be no window at all. `ExecStop` is what
puts it back to read-only, and it runs whether you stop it or the timer does.

### The guard

`ExecStartPre` runs `hibernate-mark other` before anything is remounted. When a
different OS's boot entry still carries `(HIBERNATED)`, that install owns a
hibernation image, and writing its filesystem from here is how a home directory
is lost. The unit refuses.

The guard **allows** when it cannot tell — no ESP mounted, no marker installed.
Refusing every read-write window because some unrelated thing was unmounted
would be worse than the risk it manages.

It also errs safe in the other direction: if that OS was powered off
mid-hibernation rather than resumed, its marker survives and the window is
refused even though writing would have been fine. An occasional false refusal,
with a clear reason, beats one silent corruption.

## Shared swap

Two installed systems sharing a swap partition means whoever hibernates owns
it. Booting the other starts its swap unit and discards the image — this
already happened once on this machine. `hibernate-mark` is the whole
mitigation: before hibernating, each side labels its own entry `(HIBERNATED)`
and sets itself as the **one-shot** boot default, so the menu shows who holds an
image and points at that entry.

It is a sign, not a lock. Picking the other entry by hand still costs you the
session. Nothing here can be otherwise without taking hibernation away from one
side.

The Arch-side unit `hibernate-mark-clear.service` covers the boot after an
interrupted hibernation, and the post-sleep hook covers a resume, which does
not re-run boot units. Both exist because either alone leaves a stale label.

## Files moved here

`drawer-mount.ts` and the read-write window were `125-fh-mount.ts` and
`127-fh-rw.ts`. The chainload entry was `140-fedora-entry.ts`. The marker was
`160-boot-marker.ts` plus `fedora-side.sh`, which is now one TypeScript step
instead of a second language to keep in sync.

Nothing was dropped. `files/marker/` and the pre-hibernate sleep hook moved
with them.
