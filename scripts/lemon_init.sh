#!/bin/bash
if pidof lemonbar; then killall -9 lemon.sh; fi
sleep 1 && mobile=1 sh -c "/home/sid/scripts/lemon.sh | lemonbar -g 1255x24+50+0 -f \"Inconsolata:family=regular:size=11:weight=400\" -f \"Font Awesome 5 Free Regular\" -f \"Font Awesome 5 Free Solid\" -n \"openbox\" | /bin/sh > /dev/null" & disown;
