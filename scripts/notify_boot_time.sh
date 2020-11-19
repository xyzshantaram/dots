#!/bin/bash

time1="$(systemd-analyze | awk 'NR==1 {print $NF}' | sed 's/.$//')"
time2="$(systemd-analyze | awk 'NR==2 {print $4}' | sed 's/.$//')"
total="$(echo "scale=2; $time1 + $time2" | bc)"
notify-send -a "init.sh" "Loaded system" "Boot took $total seconds to complete"
