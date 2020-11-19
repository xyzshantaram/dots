#!/bin/bash
# TODO: refactor to properly use echo -ne
set -o noglob
FGCOLOR='f5f4f0'
BGCOLOR='303030'
BG_ALPHA='f1'
max_len=50

Clock() {
	TIME=$(date "+%H%M+%S")
	echo -ne "\uf017 ${TIME}"
}

Cal() {
    DATE=$(date "+%a, %d %B %Y")
    echo -ne " ${DATE}"
}

ActiveWindow() {
	len=$(echo -n "$(xdotool getwindowfocus getwindowname)" | wc -m)
	name="$(xdotool getwindowfocus getwindowname | sed 's|*|\*|g')"
	if (( $len > max_len));then
		echo -ne "$(echo -ne $name | cut -c 1-$max_len)..."
	else
        echo -ne "$(xdotool getwindowfocus getwindowname)"
	fi
}

Sound() {
	echo -ne "$(/home/sid/.local/bin/volume)"
}

CPUTemp() {
	echo -ne "$(/home/sid/scripts/cpu_temp.sh)"
}

Buttons() {
	echo -ne "%{A:xdotool windowkill $(xdotool getactivewindow):}\uf00d%{A} "\
	"%{F#$FGCOLOR}%{T3}%{A:xdotool windowminimize $(xdotool getwindowfocus getactivewindow):}\uf2d1%{A} "\
	"%{T2}%{A:wmctrl -r \:ACTIVE\: -b toggle,maximized_vert,maximized_horz:}\uf2d0%{A}"\
	"%{A:wmctrl -k on:}\uf078%{A}"
}

Battery() {
    BATPERC=" $(acpi --battery | cut -d' ' -f4 | sed 's/,//')"
    if [[ -z "$(acpi --battery | grep -i discharging)" ]]; then
        # Charging.
        echo -ne "\uf5e7$BATPERC"
    else
        echo -ne "\uf244$BATPERC"
    fi
}

Network() {
	if iwconfig wlan0 | grep -q 'Link Quality'; then
    	signal=$(iwconfig wlan0 | awk '/Link Quality/{print "scale=0;100*" substr($2,9,5)}' | bc)
		echo -ne "\uf1eb $signal% ";
	else
		if ping -q -c 1 -W 1 8.8.8.8 > /dev/null; then
  			echo -ne "\uf6ff "
		else
			echo -ne "\uf6ff \uf00d"
		fi
	fi
}

while true; do
	constant="%{B#$BG_ALPHA$BGCOLOR}%{l}\
	%{F#F92672}$(Buttons)\
	%{T1}%{F#$FGCOLOR}%{B#$BG_ALPHA$BGCOLOR}  $(ActiveWindow) %{c}$(Clock) %{r}$(Cal)\
	|%{A2:gnome-system-monitor:} $(CPUTemp) %{A}|\
    %{A:/home/sid/.local/bin/volume mute:}%{A4:/home/sid/.local/bin/volume up:}%{A5:/home/sid/.local/bin/volume down:}%{A2:pavucontrol:}$(Sound)%{A}%{A}%{A}%{A}"
    if [[ "$mobile" == "1" ]]; then
        final=$constant" | $(Battery) | %{A2:networkmanager_dmenu:}$(Network)%{A}"
    else
        final=$constant;
    fi
    echo -ne $final;
	sleep 0.1s;
	toEcho="";
done
