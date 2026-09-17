#!/bin/sh
H=/home/team_singularity
F=$H/boot-audit-results.txt
C=$H/bootloop-remaining
i=0
until systemd-analyze > /dev/null 2>&1 || [ $i -ge 60 ]; do sleep 2; i=$((i+1)); done
j=0
until nmcli -t -f TYPE connection show --active | grep -q wifi || [ $j -ge 15 ]; do sleep 2; j=$((j+1)); done
NET=$(nmcli -t -f TYPE,NAME connection show --active | grep '^802-11-wireless:' | cut -d: -f2)
{
  echo "--- $(date -Is) net=${NET:-none}"
  dmesg | grep pt-verify
  systemd-analyze | head -1
  systemd-analyze blame | head -5
} >> $F
sync
N=$(cat $C 2>/dev/null || echo 0)
if [ "$N" -gt 0 ]; then echo $((N-1)) > $C; sync; systemctl reboot; fi
