#!/bin/bash

if xrandr | grep -q "VGA1 connected"; then
    xrandr --output VGA1 --mode 1366x768 --output LVDS1 --mode 1366x768 --right-of VGA1
fi
sleep 2 && sh -c "$HOME/scripts/remap_touch.sh" &
sleep 2 && sh -c "$HOME/scripts/setWall.sh" &
sleep 2 && sh -c "$HOME/scripts/trackpoint_settings.sh" &
sleep 1 && sh -c "$HOME/scripts/locker.sh" &
sleep 1 && sh -c "xcompmgr -cFfn -D 4" &
# sleep 1 && ulauncher &
sleep 1 && blueman-tray &
sleep 1 && tint2 &
sleep 1 && stalonetray &
dunst &
sleep 1 && lxqt-policykit-agent &
sleep 1 && sh -c "$HOME/scripts/notify_boot_time.sh" &
sleep 1 && sh -c "$HOME/scripts/lemon_init.sh" &
# sleep 1 && nm-tray &
# sleep 1 && gnome-terminal -e 'python3 "$HOME/Teams-Auto-Joiner/auto_joiner.py"'
disown
