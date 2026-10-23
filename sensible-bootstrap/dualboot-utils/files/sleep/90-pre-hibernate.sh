#!/usr/bin/bash
# Mark the hibernation in the boot menu and unmount shared filesystems before
# the image is written.
#
#   pre   title marker, leave shared filesystems alone, sync
#   post  remount the ESP, clear the marker
#
# The ESP is shared with another OS. Leaving it mounted while this machine is
# hibernated means that OS can write to it during its own kernel update while
# the hibernation image still believes its state. Unmounting first avoids a
# stale FAT, which is a much worse failure than a lost session.
#
# The drawer is the other OS's home. Same argument, higher stakes: it holds
# someone's files, and its owner resumes onto it. DRAWER_MOUNT below is
# substituted at install time by dualboot-utils/hibernate-mark.ts.
#
# Never fail. A broken hook must not block a hibernation.
set -u

log() { printf 'pre-hibernate: %s\n' "$*"; }

have_mark() { command -v hibernate-mark >/dev/null 2>&1; }

DRAWER_MOUNT="@DRAWER_MOUNT@"

case "${1:-}" in
    pre)
        if have_mark; then
            hibernate-mark mark || log "could not set the menu marker"
        fi

        # Other filesystems first: they are the ones another OS writes to.
        if [ -n "$DRAWER_MOUNT" ] && mountpoint -q "$DRAWER_MOUNT"; then
            umount "$DRAWER_MOUNT" && log "unmounted $DRAWER_MOUNT"
        fi

        sync
        if mountpoint -q /efi; then
            umount /efi && log "unmounted /efi"
        fi
        ;;
    post)
        if ! mountpoint -q /efi; then
            mount /efi 2>/dev/null && log "remounted /efi"
        fi
        # Deliberately NOT remounted here: the drawer automounts on access,
        # and bringing it back would undo the whole point of dropping it.
        if have_mark; then
            hibernate-mark clear || log "could not clear the menu marker"
        fi
        ;;
esac

exit 0
