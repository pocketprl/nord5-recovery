#!/bin/bash
# Usage: 04-test-image.sh <recovery.img> [a|b|both]
# Phone in BOOTLOADER. Flashes ONLY recovery_<slot> (default: current slot),
# reboots to recovery, waits for adb, then collects everything worth reading.
# Refuses anything that isn't a sane boot image that fits the partition.
set -u
IMG="${1:?usage: $0 <recovery.img> [a|b|both]}"
WHICH="${2:-current}"
OUT="${OUT:-$HOME/aera-lexus/device-logs/$(date +%Y%m%d-%H%M%S)-test}"
BOOT_TIMEOUT="${BOOT_TIMEOUT:-150}"
mkdir -p "$OUT"; cp "$IMG" "$OUT/flashed.img"

[ "$(head -c 8 "$IMG")" = "ANDROID!" ] || { echo "Not an Android boot image (no ANDROID! magic). Refusing."; exit 1; }
fastboot devices | grep -q . || { echo "No fastboot device."; exit 1; }
gv() { fastboot getvar "$1" 2>&1 | sed -nE "s/^$1: ?//p" | head -1; }
[ "$(gv unlocked)" = "yes" ] || { echo "Bootloader not unlocked. Refusing."; exit 1; }

cur="$(gv current-slot)"; cur="${cur#_}"
case "$WHICH" in current) slots="$cur";; a|b) slots="$WHICH";; both) slots="a b";; *) echo "bad slot"; exit 1;; esac

img_sz=$(stat -c %s "$IMG")
for s in $slots; do
  part_sz=$(printf '%d' "$(gv partition-size:recovery_$s)" 2>/dev/null || echo 0)
  if [ "$part_sz" -le 0 ] || [ "$img_sz" -gt "$part_sz" ]; then
    echo "recovery_$s: image $img_sz B vs partition $part_sz B. Refusing."; exit 1
  fi
  echo "recovery_$s: image $img_sz B fits in $part_sz B"
done

for s in $slots; do fastboot flash "recovery_$s" "$IMG" 2>&1 | tee -a "$OUT/fastboot.txt"; done
fastboot reboot recovery 2>&1 | tee -a "$OUT/fastboot.txt"

echo "Waiting up to ${BOOT_TIMEOUT}s for adb in recovery..."
if ! timeout "$BOOT_TIMEOUT" adb wait-for-recovery; then
  echo
  echo "!! No adb after ${BOOT_TIMEOUT}s. Check the screen:"
  echo "   - Stuck/black: hold Power + Vol Up ~10s, then Power + Vol Down for bootloader."
  echo "   - Then: fastboot flash recovery_$cur <known-good twrp.img>"
  exit 2
fi

echo "adb is up. Collecting logs -> $OUT"
a() { adb shell "$1" 2>&1 | tr -d '\r' > "$OUT/$2"; }
adb pull /tmp/recovery.log "$OUT/recovery.log" >/dev/null 2>&1
a 'dmesg' dmesg.txt
a 'logcat -d -b all' logcat.txt
a 'getprop' getprop.txt
a 'cat /proc/bus/input/devices' input-devices.txt
a 'lsmod' lsmod.txt
a 'mount' mount.txt
a 'ls -la /dev/block/by-name/' by-name.txt
a 'cat /sys/class/backlight/*/max_brightness /sys/class/backlight/*/brightness' backlight.txt
a 'cat /sys/class/power_supply/battery/capacity' battery.txt
a 'cat /sys/class/drm/card0-*/modes 2>/dev/null; wm size 2>/dev/null' display.txt

echo
echo "================ summary ================"
grep -E '^\[init\.svc\.' "$OUT/getprop.txt" | sed 's/^/  /'
printf '  %-22s %s\n' "touch input:" "$(grep -iE '^N: Name=.*(touch|tcm|syna|s3910)' "$OUT/input-devices.txt" | head -1 || echo none)"
printf '  %-22s %s\n' "modules loaded prop:" "$(grep -F '[twrp.modules.loaded]' "$OUT/getprop.txt" || echo unset)"
printf '  %-22s %s\n' "crypto state:" "$(grep -E '^\[ro\.crypto\.(state|type)\]' "$OUT/getprop.txt" | tr '\n' ' ')"
printf '  %-22s %s\n' "decrypted:" "$(grep -F '[twrp.all.users.decrypted]' "$OUT/getprop.txt" || echo unset)"
printf '  %-22s %s\n' "backlight max/cur:" "$(tr '\n' ' ' < "$OUT/backlight.txt")"
printf '  %-22s %s\n' "battery %:" "$(cat "$OUT/battery.txt")"
echo "  errors in recovery.log:"
grep -iE '^E:|failed|unable' "$OUT/recovery.log" 2>/dev/null | head -25 | sed 's/^/    /'
echo "Full logs: $OUT"
