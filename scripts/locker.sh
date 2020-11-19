#!/usr/bin/env bash

# Run xidlehook
xidlehook --not-when-fullscreen --not-when-audio \
    --timer 90 \
    'xbacklight -dec 10' \
    'xbacklight -inc 10' \
    --timer 270 \
    'xbacklight -inc 10; /home/sid/scripts/corrupterlck' \
    '' \
    --timer 3600 \
    'systemctl suspend' \
    ''
