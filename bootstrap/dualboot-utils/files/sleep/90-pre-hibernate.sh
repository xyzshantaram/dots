#!/usr/bin/bash
# Mark the hibernation in the boot menu and unmount shared filesystems before
# the image is written.
#
#   pre   title marker, drop the ESP, sync
#   post  remount the ESP, clear the marker
#
# The ESP is shared with another OS. Leaving it mounted while this machine is
# hibernated means that OS can write to it during its own kernel update while
# the hibernation image still believes its state. Unmounting first avoids a
# stale FAT, which is a much worse failure than a lost session.
#
# The homes are shared too, but they are not unmounted here: both systems treat
# the shared partition as /home, so dropping it would take the running session's
# home with it.
#
# Never fail. A broken hook must not block a hibernation.
set -u

log() { printf 'pre-hibernate: %s\n' "$*"; }

have_mark() { command -v hibernate-mark >/dev/null 2>&1; }

case "${1:-}" in
    pre)
        if have_mark; then
            hibernate-mark mark || log "could not set the menu marker"
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
        if have_mark; then
            hibernate-mark clear || log "could not clear the menu marker"
        fi
        ;;
esac

exit 0
