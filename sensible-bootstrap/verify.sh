#!/usr/bin/env bash
# ---
# script: verify.sh
# desc:   Read-only health check. Runs from Fedora (against the mounted target)
#         or from the booted Arch system. Changes nothing.
# needs:  nothing; a missing mount is reported, not fixed
# up:     prints PASS/FAIL/WARN per check and exits 1 if anything failed
# down:   nothing; this script never mutates state
# revisit: 2026-12-21
# ---
#
# Use it before the ladder, after the ladder, and from Arch after the first
# boot. `sudo ./verify.sh` is the intended invocation.
#
# Exit codes: 0 all pass (warnings allowed), 1 something failed, 2 bad usage.
#
# Every check is read-only by construction: blkid, findmnt, cmp, stat, test,
# systemctl is-enabled, snapper list, pacman -Q. Nothing writes or mounts.
set -uo pipefail

HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$HERE/.env"

pass=0; fail=0; warn=0
ok()   { printf '  PASS  %s\n' "$*"; pass=$((pass + 1)); }
bad()  { printf '  FAIL  %s\n' "$*"; fail=$((fail + 1)); }
note() { printf '  WARN  %s\n' "$*"; warn=$((warn + 1)); }
head_() { printf '\n== %s\n' "$*"; }

[ "${1:-}" = "--help" ] && { sed -n '2,14p' "$0"; exit 0; }

# --- environment ----------------------------------------------------------
if [ ! -f "$ENV_FILE" ]; then
    printf 'verify: no .env at %s\n' "$ENV_FILE" >&2
    printf 'verify: cp .env.example .env and fill it in\n' >&2
    exit 2
fi

# Read .env without sourcing it: sourcing would run arbitrary shell code.
env_get() {
    local key="$1" line
    line="$(grep -E "^${key}=" "$ENV_FILE" 2>/dev/null | tail -1)"
    [ -n "$line" ] || return 1
    printf '%s\n' "${line#*=}" | sed -e 's/^"//' -e 's/"$//' -e "s/^'//" -e "s/'$//"
}

ROOT_MNT="$(env_get ROOT_MNT)" || ROOT_MNT=/mnt/arch
ESP_MOUNT="$(env_get ESP_MOUNT)" || ESP_MOUNT=/efi
ARCH_UUID="$(env_get ARCH_UUID)" || ARCH_UUID=""
SWAP_UUID="$(env_get SWAP_UUID)" || SWAP_UUID=""
ESP_UUID="$(env_get ESP_UUID)" || ESP_UUID=""
ARCH_USER="$(env_get ARCH_USER)" || ARCH_USER=shan
ARCH_UID_EXPECT="$(env_get ARCH_UID)" || ARCH_UID_EXPECT=1000
KERNEL="$(env_get KERNEL)" || KERNEL=linux-zen
# Optional: only dualboot-utils/ reads these, and all may be unset.
DRAWER_UUID="$(env_get DRAWER_UUID)" || DRAWER_UUID=""
DRAWER_MOUNT="$(env_get DRAWER_MOUNT)" || DRAWER_MOUNT=/mnt/drawer

HOST_OS="$(sed -n 's/^ID=//p' /etc/os-release 2>/dev/null | tr -d '"' | head -1)"
TARGET=""          # "" when not mounted, else the path to operate on
IN_TARGET=0        # 1 when the target is reachable, 2 when it is this system

case "$HOST_OS" in
    arch*|endeavouros|garuda|manjaro|cachyos)
        IN_TARGET=2
        TARGET=""
        ESP_AT="/efi"
        [ -d /boot/efi/loader ] && ESP_AT="/boot/efi"
        ;;
    *)
        if mountpoint -q "$ROOT_MNT"; then
            IN_TARGET=1
            TARGET="$ROOT_MNT"
            ESP_AT="$ROOT_MNT$ESP_MOUNT"
        else
            IN_TARGET=0
            TARGET=""
            ESP_AT=""
        fi
        ;;
esac

# Resolve a path that exists inside the thing being checked.
at() {
    if [ "$IN_TARGET" = "2" ]; then printf '%s\n' "$1"
    else printf '%s\n' "$TARGET$1"; fi
}

exists() { [ -e "$1" ]; }
has_cmd() { command -v "$1" >/dev/null 2>&1; }

printf 'verify: host=%s target=%s\n' "$HOST_OS" \
    "$([ "$IN_TARGET" = 2 ] && echo "this system" \
       || [ "$IN_TARGET" = 1 ] && echo "$ROOT_MNT" || echo "NOT MOUNTED")"
printf 'verify: kernel=%s user=%s esp=%s\n' "$KERNEL" "$ARCH_USER" \
    "$([ -n "$ESP_AT" ] && echo "$ESP_AT" || echo "-")"

# --- 1. block devices -----------------------------------------------------
head_ "block devices and UUIDs"

# lsblk, not blkid: blkid needs root to open the device, so an unprivileged run
# would report every UUID as a mismatch. lsblk reads udev's database instead and
# works either way.
if ! has_cmd lsblk; then
    note "lsblk not found; skipping the device checks"
else
    dev_field() {   # dev_field <partition> <FSTYPE|UUID>
        lsblk -no "$2" "/dev/$1" 2>/dev/null | head -1 | tr -d ' '
    }

    [ "$(dev_field nvme0n1p5 FSTYPE)" = "btrfs" ] \
        && ok "nvme0n1p5 is btrfs" \
        || bad "nvme0n1p5 is not btrfs (got '$(dev_field nvme0n1p5 FSTYPE)')"

    [ "$(dev_field nvme0n1p1 FSTYPE)" = "vfat" ] \
        && ok "nvme0n1p1 is vfat (ESP)" \
        || bad "nvme0n1p1 is not vfat (got '$(dev_field nvme0n1p1 FSTYPE)')"

    for pair in "nvme0n1p1:$ESP_UUID:ESP_UUID" \
                "nvme0n1p2:$SWAP_UUID:SWAP_UUID" \
                "nvme0n1p5:$ARCH_UUID:ARCH_UUID"; do
        dev="${pair%%:*}"; rest="${pair#*:}"
        want="${rest%%:*}"; name="${rest##*:}"
        got="$(dev_field "$dev" UUID)"
        if [ -z "$want" ] || [ "$want" = "0000-0000" ] \
           || [ "$want" = "00000000-0000-0000-0000-000000000000" ]; then
            note "$name is still the placeholder in .env"
        elif [ "$got" = "$want" ]; then
            ok "$name matches $dev"
        elif [ -z "$got" ]; then
            note "$name unreadable for $dev (unprivileged?); re-run with sudo"
        else
            bad "$name mismatch: .env has '$want', device has '$got'"
        fi
    done
fi

# --- 2. mounts ------------------------------------------------------------
head_ "mounts"

if [ "$IN_TARGET" = 0 ]; then
    note "$ROOT_MNT is not mounted; everything below that needs the target is skipped"
    note "run: sudo bun run 10-mount.ts up   (or ./10-mount.ts up)"
elif [ -n "$ESP_AT" ]; then
    if mountpoint -q "$ESP_AT" 2>/dev/null; then
        ok "ESP mounted at $ESP_AT"
    elif [ "$IN_TARGET" = 2 ]; then
        note "ESP not mounted at $ESP_AT; mount it before a kernel update"
    else
        bad "ESP is not mounted at $ESP_AT"
    fi
fi

if [ "$IN_TARGET" != 0 ]; then
    # The ESP mountpoint in fstab should be the one .env declares.
    fstab="$(at /etc/fstab)"
    if [ -f "$fstab" ]; then
        line="$(grep -E "^(UUID=${ESP_UUID}|/dev/disk/by-uuid/${ESP_UUID})[[:space:]]" "$fstab" 2>/dev/null | head -1)"
        if [ -z "$line" ]; then
            note "no ESP line in fstab for UUID=$ESP_UUID"
        else
            mounted_at="$(printf '%s\n' "$line" | awk '{print $2}')"
            [ "$mounted_at" = "$ESP_MOUNT" ] \
                && ok "fstab mounts the ESP at $ESP_MOUNT" \
                || bad "fstab mounts the ESP at '$mounted_at', .env says '$ESP_MOUNT' (run 12-esp-efi.ts up)"
        fi

        if grep -q "subvol=@snapshots" "$fstab" 2>/dev/null; then
            ok "fstab has the @snapshots entry"
        else
            note "fstab has no @snapshots entry (180-snapper.ts up adds it)"
        fi

        if [ -n "$DRAWER_MOUNT" ] && grep -q " ${DRAWER_MOUNT} " "$fstab" 2>/dev/null; then
            opts="$(grep " ${DRAWER_MOUNT} " "$fstab" | awk '{print $4}')"
            case "$opts" in
                *ro*|*" ro,"*) ok "drawer at $DRAWER_MOUNT is read-only in fstab" ;;
                *) bad "drawer at $DRAWER_MOUNT is NOT read-only in fstab ($opts)" ;;
            esac
        else
            note "no drawer entry in fstab (dualboot-utils/drawer-mount.ts up)"
        fi
    else
        bad "no /etc/fstab at $fstab"
    fi
fi

# --- 3. account -----------------------------------------------------------
head_ "account: $ARCH_USER"

if [ "$IN_TARGET" = 0 ]; then
    note "skipped: target not mounted"
else
    pw="$(
        if [ "$IN_TARGET" = 2 ]; then getent passwd "$ARCH_USER"
        else chroot "$ROOT_MNT" getent passwd "$ARCH_USER" 2>/dev/null; fi
    )"
    if [ -z "$pw" ]; then
        bad "user $ARCH_USER does not exist"
    else
        ok "user $ARCH_USER exists"
        shell="$(printf '%s\n' "$pw" | cut -d: -f7)"
        [ "$shell" = "/usr/bin/fish" ] \
            && ok "login shell is fish" \
            || bad "login shell is '$shell', expected /usr/bin/fish"
        uid="$(printf '%s\n' "$pw" | cut -d: -f3)"
        [ "$uid" = "$ARCH_UID_EXPECT" ] \
            && ok "uid is $ARCH_UID_EXPECT" \
            || note "uid is $uid, not $ARCH_UID_EXPECT; another distro's home may not resolve"

        groups_of() {
            if [ "$IN_TARGET" = 2 ]; then id -nG "$ARCH_USER"
            else chroot "$ROOT_MNT" id -nG "$ARCH_USER" 2>/dev/null; fi
        }
        gs=" $(groups_of) "
        for g in wheel input uucp video; do
            case "$gs" in
                *" $g "*) ok "in group $g" ;;
                *) bad "missing group $g" ;;
            esac
        done
    fi

    sudoers="$(at /etc/sudoers.d/10-wheel)"
    exists "$sudoers" && ok "wheel sudo drop-in present" \
                      || bad "missing /etc/sudoers.d/10-wheel"
fi

# --- 4. kernel and ESP ----------------------------------------------------
head_ "kernel: $KERNEL"

if [ "$IN_TARGET" = 0 ]; then
    note "skipped: target not mounted"
else
    for f in "/boot/vmlinuz-$KERNEL" "/boot/initramfs-$KERNEL.img"; do
        exists "$(at "$f")" && ok "present: $f" || bad "missing: $f"
    done

    # Microcode rides inside the main initramfs via the `microcode` hook, which
    # Arch's default HOOKS already list, so there is no separate
    # /boot/amd-ucode.img to look for. Confirm it actually got embedded, the way
    # ArchWiki suggests, rather than checking for a file this arrangement does
    # not produce.
    if grep -q 'microcode' "$(at /etc/mkinitcpio.conf)" 2>/dev/null; then
        if [ "$IN_TARGET" = 2 ]; then
            early_uc="$(lsinitcpio --early "/boot/initramfs-$KERNEL.img" 2>/dev/null)"
        else
            early_uc="$(chroot "$ROOT_MNT" lsinitcpio --early "/boot/initramfs-$KERNEL.img" 2>/dev/null)"
        fi
        case "$early_uc" in
            *microcode*) ok "initramfs contains microcode (early CPIO)" ;;
            *) note "no microcode in the initramfs yet; 145-hibernate.ts up rebuilds it" ;;
        esac
    else
        bad "no microcode hook in /etc/mkinitcpio.conf; early microcode will not load"
    fi

    if [ -n "$ESP_AT" ] && [ -d "$ESP_AT/EFI/arch" ]; then
        for dir in current previous; do
            vmlinuz="$ESP_AT/EFI/arch/$dir/vmlinuz-$KERNEL"
            initrd="$ESP_AT/EFI/arch/$dir/initramfs-$KERNEL.img"
            if exists "$vmlinuz" && exists "$initrd"; then
                ok "ESP $dir kernel pair complete"
            else
                # previous is seeded from current by esp-sync, so this is not a
                # "wait for the first kernel update" state any more.
                note "ESP $dir incomplete; 150-kernel-sync.ts up seeds it from current"
            fi
        done
        # current should match what mkinitcpio last wrote in /boot.
        if cmp -s "$(at "/boot/vmlinuz-$KERNEL")" \
                  "$ESP_AT/EFI/arch/current/vmlinuz-$KERNEL" 2>/dev/null; then
            ok "ESP current matches /boot"
        else
            note "ESP current differs from /boot; run esp-sync"
        fi
    fi

    entries="$(at "$ESP_MOUNT/loader/entries")"
    if [ -d "$entries" ]; then
        for e in arch.conf arch-known-good.conf fedora.conf; do
            if exists "$entries/$e"; then
                t="$(sed -n 's/^title[[:space:]]*//p' "$entries/$e" | head -1)"
                ok "entry $e: $t"
            else
                note "entry $e missing"
            fi
        done
        # A referenced initrd that is not on disk makes systemd-boot refuse
        # the entry, which is a silent path to an unbootable machine.
        for e in "$entries"/*.conf; do
            [ -e "$e" ] || continue
            while IFS= read -r ref; do
                [ -n "$ref" ] || continue
                esc="$(printf '%s' "$ref" | sed -e 's|\\|/|g' -e 's|^/||')"
                exists "$ESP_AT/$esc" \
                    || bad "$(basename "$e") references missing $ref"
            done < <(awk '$1=="linux"||$1=="initrd"{print $2}' "$e" 2>/dev/null)
        done
    else
        note "no loader/entries directory on the ESP"
    fi

    if grep -q "resume=UUID=$SWAP_UUID" "$entries/arch.conf" 2>/dev/null; then
        ok "arch.conf carries resume=UUID=$SWAP_UUID"
    elif [ -f "$entries/arch.conf" ]; then
        bad "arch.conf has no resume=UUID=$SWAP_UUID (hibernate will not resume)"
    fi
fi

# --- 5. hibernation -------------------------------------------------------
head_ "hibernation"

if [ "$IN_TARGET" = 0 ]; then
    note "skipped: target not mounted"
else
    hooks="$(at /etc/mkinitcpio.conf)"
    if [ -f "$hooks" ]; then
        grep -qE '^HOOKS=.*\bresume\b' "$hooks" \
            && ok "mkinitcpio HOOKS include resume" \
            || bad "mkinitcpio HOOKS lack resume; the image will never be resumed"
    fi

    for f in \
        "/etc/systemd/logind.conf.d/10-hibernate.conf" \
        "/etc/systemd/system/systemd-suspend.service.d/10-suspend-is-hibernate.conf" \
        "/etc/tmpfiles.d/hibernation-image-size.conf" \
        "/usr/local/bin/hibernate-wakeup-mask" \
        "/usr/local/bin/hibernate-mark"
    do
        exists "$(at "$f")" && ok "present: $f" || note "missing: $f"
    done

    logind="$(at /etc/systemd/logind.conf.d/10-hibernate.conf)"
    if [ -f "$logind" ]; then
        grep -q '^HandleLidSwitch=hibernate' "$logind" \
            && ok "lid close hibernates" \
            || bad "HandleLidSwitch is not hibernate"
    fi

    clear_unit="$(at /etc/systemd/system/hibernate-mark-clear.service)"
    if [ "$IN_TARGET" = 2 ] && [ -f "$clear_unit" ]; then
        systemctl is-enabled hibernate-mark-clear.service >/dev/null 2>&1 \
            && ok "hibernate-mark-clear is enabled" \
            || bad "hibernate-mark-clear is installed but not enabled"
    fi

    # A shared swap partition is the whole reason for the marker. If Fedora's
    # image is on it, this must be seen before booting anything else.
    if [ "$IN_TARGET" = 2 ]; then
        if grep -qE "resume=UUID=$SWAP_UUID" /proc/cmdline; then
            ok "running kernel was started with resume=$SWAP_UUID"
        else
            note "running kernel cmdline has no resume= (fine if this boot followed a cold start)"
        fi
    fi
fi

# --- 6. session, config, services ----------------------------------------
head_ "session and services"

if [ "$IN_TARGET" = 0 ]; then
    note "skipped: target not mounted"
else
    niri="$(at "/home/$ARCH_USER/.config/niri/config.kdl")"
    if [ -f "$niri" ]; then
        ok "niri config present"
        for snippet in XF86AudioMute XF86AudioLowerVolume XF86AudioRaiseVolume \
                       XF86AudioMicMute XF86MonBrightnessUp XF86MonBrightnessDown; do
            grep -q "$snippet" "$niri" \
                && ok "niri binds $snippet" \
                || note "niri config lacks $snippet"
        done
        grep -q 'spawn-at-startup "qs"' "$niri" \
            && ok "niri starts quickshell" \
            || note "niri does not start quickshell"
        grep -q 'idle-hibernate' "$niri" \
            && ok "niri starts swayidle" \
            || note "niri does not start swayidle (147-idle.ts up)"
        grep -q 'wallpaper-random' "$niri" \
            && ok "niri starts wallpaper-random" \
            || note "niri does not set a wallpaper (112-wallpaper.ts up)"
        # A CapsLock tap arrives as F13, emitted by keyd's overload().
        grep -q 'F13' "$niri" \
            && ok "niri binds F13 (Super tap -> app drawer)" \
            || note "niri does not bind F13 (keyd Super tap has nowhere to land)"
        grep -q 'Pause' "$niri" \
            && ok "niri binds the Copilot key (Pause)" \
            || note "niri does not bind Pause"
        # udiskie must run inside the session, not as a systemd user service:
        # polkit only lets an *active* session mount without a password.
        grep -q 'spawn-at-startup "udiskie"' "$niri" \
            && ok "niri starts udiskie (removable media automount)" \
            || note "niri does not start udiskie (114-udisks.ts up)"
    else
        note "no niri config at $niri"
    fi

    for f in \
        "/home/$ARCH_USER/.config/wezterm/wezterm.lua" \
        "/home/$ARCH_USER/.config/quickshell/shell.qml" \
        "/home/$ARCH_USER/.config/fish/config.fish" \
        "/home/$ARCH_USER/.config/fish/functions/fish_prompt.fish" \
        "/home/$ARCH_USER/.local/share/dictation/qml/DictationStrip.qml" \
        "/home/$ARCH_USER/.local/share/dictation/bin/dictation-strip" \
        "/home/$ARCH_USER/.local/share/dictation/bin/wtype" \
        "/home/$ARCH_USER/.config/udiskie/config.yml"
    do
        exists "$(at "$f")" && ok "present: ${f#"$TARGET"}" || note "missing: ${f#"$TARGET"}"
    done

    # udisksd is D-Bus activated, so udisks2.service being inactive is normal
    # and deliberately not checked. Only the automounter has to be present.
    if exists "$(at /usr/bin/udiskie)"; then
        ok "udiskie installed"
    else
        note "udiskie missing; removable media will not automount (40-packages.ts up)"
    fi

    # paru links libalpm, so being installed says nothing about whether it works.
    # The paru-bin prebuilt binary needed libalpm.so.15 while pacman 7.1 ships
    # .16, and it failed identically everywhere else: as a bare exit 127 from the
    # next step. Running it is the only way to know.
    if exists "$(at /usr/bin/paru)"; then
        if [ "$IN_TARGET" = 2 ]; then
            paru --version >/dev/null 2>&1 && paru_runs=yes || paru_runs=no
        else
            chroot "$ROOT_MNT" paru --version >/dev/null 2>&1 && paru_runs=yes || paru_runs=no
        fi
        [ "$paru_runs" = yes ] \
            && ok "paru runs" \
            || bad "paru is installed but will not run (libalpm mismatch? see 130-paru.ts)"
    else
        note "paru not installed (130-paru.ts up)"
    fi

    for f in \
        "/etc/keyd/default.conf" \
        "/etc/pam.d/system-local-login" \
        "/etc/sudoers.d/10-pwfeedback" \
        "/usr/local/bin/esp-sync" \
        "/usr/local/bin/idle-hibernate" \
        "/usr/local/bin/wallpaper-random" \
        "/usr/share/libalpm/hooks/99-esp-kernel-sync.hook" \
        "/etc/NetworkManager/conf.d/wifi-powersave.conf" \
        "/etc/modprobe.d/audio-mute.conf" \
        "/etc/snapper/configs/root" \
        "/usr/local/share/fonts/cmu" \
        "/home/$ARCH_USER/wallpapers"
    do
        exists "$(at "$f")" && ok "present: $f" || note "missing: $f"
    done

    if [ -f "$(at /etc/pam.d/sudo)" ]; then
        grep -q pam_fprintd "$(at /etc/pam.d/sudo)" \
            && ok "pam_fprintd is in /etc/pam.d/sudo" \
            || note "pam_fprintd not in /etc/pam.d/sudo"
    fi

    if [ -f "$(at /etc/keyd/default.conf)" ]; then
        # Either form means CapsLock behaves as Meta: a direct assignment, or
        # overload(meta, ...) which holds as Meta and taps as another key.
        grep -Eq 'capslock = (leftmeta|overload\(meta)' "$(at /etc/keyd/default.conf)" \
            && ok "CapsLock acts as Meta" \
            || note "keyd does not map CapsLock to Meta"
        # overload() is what makes a Super *tap* possible at all; niri cannot
        # bind a bare modifier release.
        grep -q 'overload(' "$(at /etc/keyd/default.conf)" \
            && ok "keyd overload present (Super tap emits a key)" \
            || note "no keyd overload; tapping Super does nothing"
        # Without this, any release without an intervening key counts as a tap,
        # so a slow hold-and-release opens the drawer by accident.
        grep -q 'overload_tap_timeout' "$(at /etc/keyd/default.conf)" \
            && ok "keyd tap window is set (overload_tap_timeout)" \
            || note "no overload_tap_timeout; a slow hold-release will open the drawer"
    fi

    # tools/measure-taps.py reads /dev/input directly, and the buses there are
    # 0660 root:input. Checked against the target's own /etc/group rather than
    # the running machine's, since verify.sh can run from Fedora.
    if [ -f "$(at /etc/group)" ]; then
        input_members="$(awk -F: '$1=="input"{print $4}' "$(at /etc/group)" 2>/dev/null)"
        case ",$input_members," in
            *",$ARCH_USER,"*)
                ok "$ARCH_USER is in the input group (can read /dev/input)" ;;
            *)
                note "$ARCH_USER is not in the input group; tools/measure-taps.py cannot read /dev/input" ;;
        esac
    fi

    # greetd + tuigreet. The greeter is optional: a machine without it uses
    # console login and is not broken.
    greeter_cfg="$(at /etc/greetd/config.toml)"
    if [ -f "$greeter_cfg" ]; then
        if grep -q 'tuigreet' "$greeter_cfg"; then
            ok "greetd is configured to run tuigreet"
            grep -q 'niri-session' "$greeter_cfg" \
                && ok "tuigreet preselects niri-session" \
                || note "tuigreet does not name niri-session as its default"
        else
            note "greetd config does not mention tuigreet"
        fi

        # The greeter has no logind session, so without this rule every power
        # action is denied and tuigreet's F12 menu does nothing at all.
        if [ -f "$(at /etc/polkit-1/rules.d/49-greeter-power.rules)" ]; then
            ok "greeter polkit rule present (power menu can work)"
        else
            note "no greeter polkit rule; tuigreet's power menu will not work (117-greetd.ts up)"
        fi

        # greetd delegates auth to system-local-login, which is where the
        # fingerprint line lives. If that include ever disappears from the
        # shipped PAM file, fingerprint at the greeter stops working silently,
        # which is exactly the kind of thing worth reporting.
        pam_greetd="$(at /etc/pam.d/greetd)"
        if [ -f "$pam_greetd" ] && grep -q 'system-local-login' "$pam_greetd"; then
            if grep -q pam_fprintd "$(at /etc/pam.d/system-local-login)" 2>/dev/null; then
                ok "fingerprint reaches the greeter via system-local-login"
            else
                note "greeter cannot use fingerprint: no pam_fprintd in system-local-login"
            fi
        fi
    else
        note "no greetd config (117-greetd.ts up adds one); console login is used"
    fi

    # systemctl only works against the running system, not a chroot.
    if [ "$IN_TARGET" = 2 ]; then
        for unit in NetworkManager.service keyd.service; do
            systemctl is-enabled "$unit" >/dev/null 2>&1 \
                && ok "$unit enabled" || bad "$unit not enabled"
        done
        for unit in battery-charge-thresholds.service hibernate-mark-clear.service greetd.service; do
            systemctl is-enabled "$unit" >/dev/null 2>&1 \
                && ok "$unit enabled" || note "$unit not enabled"
        done
    else
        # Read the symlink directly: no systemd is running against the target.
        wan="$(at /etc/systemd/system/multi-user.target.wants/NetworkManager.service)"
        [ -L "$wan" ] && ok "NetworkManager enabled (symlink)" \
                      || note "NetworkManager is not enabled yet"
    fi
fi

# --- 7. snapper -----------------------------------------------------------
head_ "snapshots"

if [ "$IN_TARGET" = 0 ]; then
    note "skipped: target not mounted"
else
    snap_mnt="$(at /.snapshots)"
    if [ "$IN_TARGET" = 2 ]; then
        mountpoint -q /.snapshots && ok "/.snapshots is mounted" \
                                   || note "/.snapshots is not mounted"
    elif exists "$snap_mnt"; then
        ok "/.snapshots exists in the target"
    fi

    if [ -f "$(at /etc/snapper/configs/root)" ]; then
        ok "snapper root config exists"
        if [ "$IN_TARGET" = 2 ]; then
            if snapper -c root list 2>/dev/null | grep -q 'sensible-bootstrap'; then
                ok "post-bootstrap snapshot exists"
            else
                note "no 'sensible-bootstrap complete' snapshot yet"
            fi
        fi
        grep -q '^TIMELINE_CREATE="no"' "$(at /etc/snapper/configs/root)" \
            && ok "hourly timeline snapshots disabled" \
            || note "timeline snapshots are enabled"
    else
        note "no snapper config (180-snapper.ts up)"
    fi
fi

# --- 8. dual boot (drawer and hibernation marker) --------------------------
# Nothing in the ladder itself needs any of this, so every branch here is
# optional and reports as a warning when it is not configured.
head_ "dual boot (optional)"

if [ -z "$DRAWER_UUID" ] || [ "$DRAWER_UUID" = "00000000-0000-0000-0000-000000000000" ]; then
    note "no DRAWER_UUID in .env; single-boot machine, nothing to check"
else
    if has_cmd findmnt && [ -n "$DRAWER_MOUNT" ]; then
        if findmnt -rno TARGET "$DRAWER_MOUNT" >/dev/null 2>&1; then
            opts="$(findmnt -rno OPTIONS "$DRAWER_MOUNT")"
            case "$opts" in
                *rw*) note "drawer is read-WRITE; systemctl stop drawer-rw to end the window" ;;
                *) ok "drawer at $DRAWER_MOUNT is mounted read-only" ;;
            esac
        else
            note "drawer not mounted (it automounts on first access)"
        fi
    fi

    # The guard is what stops a read-write window opening onto a filesystem
    # belonging to a hibernated OS. Worth knowing if it is missing.
    if [ -x "$(at /usr/local/bin/hibernate-mark)" ]; then
        ok "hibernate-mark installed"
    else
        note "no hibernate-mark (dualboot-utils/hibernate-mark.ts up)"
    fi

    if exists "$(at /etc/systemd/system/drawer-rw.service)"; then
        ok "drawer-rw.service installed"
    else
        note "no drawer-rw.service (dualboot-utils/drawer-mount.ts up)"
    fi

    unit="$(at /usr/local/bin/hibernate-mark)"
    if [ "$IN_TARGET" = 2 ] && [ -x "$unit" ]; then
        "$unit" show >/dev/null 2>&1 \
            && ok "hibernate-mark can read the boot entries" \
            || note "hibernate-mark cannot find the ESP from here"
    fi
fi

# --- summary --------------------------------------------------------------
printf '\nverify: %d passed, %d failed, %d warnings\n' "$pass" "$fail" "$warn"
if [ "$fail" -gt 0 ]; then
    printf 'verify: FAILED\n'
    exit 1
fi
printf 'verify: OK\n'
exit 0
