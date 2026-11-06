#!/bin/bash
# Run with the phone in a WORKING RECOVERY that has root adb (official TWRP first).
# Read-only on the phone: copies small/critical partitions to the PC.
# Lists sizes and asks before transferring anything. Skips super and userdata.
set -u
OUT="${OUT:-$PWD/lexus-device-backup/$(date +%Y%m%d-%H%M%S)}"
MAX_MB="${MAX_MB:-256}"   # skip anything bigger than this (super/userdata are excluded regardless)

adb get-state >/dev/null 2>&1 || { echo "No adb device. Is recovery up?"; exit 1; }
[ "$(adb shell id -u | tr -d '\r')" = "0" ] || { echo "adb is not root."; exit 1; }

# Needed first no matter what: IMEI/calibration/sensor data and OnePlus-specific bits
CRITICAL='persist modemst1 modemst2 fsg fsc oplusstanvbk_a oplusstanvbk_b oplus_sec_a oplus_sec_b oplusreserve1 oplusreserve2 devinfo frp'
is_critical() { case " $CRITICAL " in *" $1 "*) return 0;; esac; return 1; }

echo "Reading partition table..."
adb shell 'for p in /dev/block/by-name/*; do n=${p##*/}; s=$(blockdev --getsize64 $p 2>/dev/null); echo "$n $s"; done' \
  | tr -d '\r' | sort > /tmp/lexus-parts.txt

total=0; : > /tmp/lexus-plan.txt
while read -r n s; do
  case "$n" in super|userdata) continue;; esac
  [ -z "$s" ] && continue
  mb=$(( s / 1048576 ))
  if [ "$mb" -le "$MAX_MB" ] || is_critical "$n"; then
    echo "$n $s" >> /tmp/lexus-plan.txt; total=$(( total + s ))
  else
    printf '  skip %-28s %6d MB (over MAX_MB=%s)\n' "$n" "$mb" "$MAX_MB"
  fi
done < /tmp/lexus-parts.txt

echo; echo "Critical partitions present:"
while read -r n s; do is_critical "$n" && printf '  %-22s %8.1f MB\n' "$n" "$(echo "$s/1048576" | bc -l)"; done < /tmp/lexus-plan.txt
printf '\nPlan: %d partitions, %.1f MB total -> %s\n' "$(wc -l < /tmp/lexus-plan.txt)" "$(echo "$total/1048576" | bc -l)" "$OUT"
if [ "${YES:-0}" != 1 ]; then read -r -p "Proceed? [y/N] " a; [ "$a" = "y" ] || exit 0; fi

mkdir -p "$OUT"; cp /tmp/lexus-parts.txt "$OUT/partition-table.txt"
# Critical ones first so a cable yank still leaves the important stuff saved
{ while read -r n s; do is_critical "$n" && echo "$n $s"; done < /tmp/lexus-plan.txt
  while read -r n s; do is_critical "$n" || echo "$n $s"; done < /tmp/lexus-plan.txt; } |
while read -r n s; do
  printf '%-28s %8.1f MB ... ' "$n" "$(echo "$s/1048576" | bc -l)"
  adb exec-out "cat /dev/block/by-name/$n" < /dev/null > "$OUT/$n.img"
  got=$(stat -c %s "$OUT/$n.img")
  [ "$got" = "$s" ] && echo ok || echo "SIZE MISMATCH ($got != $s)"
done
( cd "$OUT" && sha256sum *.img > SHA256SUMS )
echo "Done. Copy $OUT somewhere that is NOT this PC as well."
