#!/bin/bash
temp="$(awk '{gsub("000", "", $0)}; END{print $0}' /sys/class/thermal/thermal_zone*/temp)"
echo -ne "\uf769 ${temp}C"
