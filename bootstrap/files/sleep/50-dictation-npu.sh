#!/usr/bin/bash
# Keep the XDNA NPU out of the hibernation power path.
#
# The amdxdna resume path times out on the SMU (-110, Access power failed,
# aie2_hw_resume) when the NPU was in use, and leaves the NPU dead until the
# next reboot. Stopping dictation and unloading the module before hibernation
# avoids that path. Both come back after resume.
#
# systemd-sleep calls this with "pre" or "post" (plus the sleep operation).
# USER_NAME is rewritten for the target account when bootstrap installs it.
set -u

USER_NAME=sid
USER_UID="$(id -u "$USER_NAME" 2>/dev/null || echo 1000)"

as_user() {
    runuser -u "$USER_NAME" -- env \
        XDG_RUNTIME_DIR="/run/user/$USER_UID" \
        DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$USER_UID/bus" \
        "$@"
}

case "${1:-}" in
    pre)
        as_user systemctl --user stop dictation.target >/dev/null 2>&1 || true
        # Give flm a moment to close the NPU device before the module unload.
        sleep 1
        modprobe -r amdxdna 2>/dev/null || true
        ;;
    post)
        modprobe amdxdna 2>/dev/null || true
        as_user systemctl --user start dictation.target >/dev/null 2>&1 || true
        ;;
esac

exit 0
