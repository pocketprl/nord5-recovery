#!/bin/bash
# Run with the phone in a recovery that has root adb.
# Compares every ELF/firmware blob in recovery/root against the phone's own
# /vendor, /odm, /system and /system_ext, matched by file name.
#   PULL=1  also copies the phone's version over every differing ramdisk blob
# Writes nothing to the phone (partitions get mounted read-only).
set -u
TREE="$(cd "$(dirname "$0")/.." && pwd)"
ROOT="$TREE/recovery/root"
OUT="${OUT:-$HOME/aera-lexus/device-logs/$(date +%Y%m%d-%H%M%S)-blobs}"
mkdir -p "$OUT"

adb get-state >/dev/null 2>&1 || { echo "No adb device."; exit 1; }

echo "Mounting stock partitions read-only (errors are fine if already mounted)..."
adb shell 'for m in /vendor /odm /system_root /system /system_ext /vendor_dlkm; do mount -o ro $m 2>&1 | sed "s|^|  $m: |"; done' | tr -d '\r'

echo "Indexing phone files (hashing .so/.bin/.mbn/.fw/.img/hw bins)..."
adb shell 'for d in /vendor /odm /system_root/system /system /system_ext; do
  [ -d $d ] && find $d -type f \( -name "*.so" -o -name "*.bin" -o -name "*.mbn" -o -name "*.fw" -o -name "*.img" -o -path "*/bin/*" \) 2>/dev/null
done | xargs sha256sum 2>/dev/null' | tr -d '\r' > "$OUT/device-index.txt"
echo "  $(wc -l < "$OUT/device-index.txt") files indexed"

printf '%-9s %-60s %s\n' STATUS RAMDISK_PATH DEVICE_PATH > "$OUT/audit.txt"
same=0; diff=0; miss=0
while IFS= read -r f; do
  rel="${f#$ROOT/}"; base="$(basename "$f")"
  file -b "$f" | grep -qE 'ELF|data' || continue
  mine="$(sha256sum "$f" | cut -d' ' -f1)"
  hits="$(awk -v b="/$base" 'substr($2, length($2)-length(b)+1) == b' "$OUT/device-index.txt")"
  if [ -z "$hits" ]; then
    printf '%-9s %-60s %s\n' MISSING "$rel" "-" >> "$OUT/audit.txt"; miss=$((miss+1)); continue
  fi
  if echo "$hits" | grep -q "^$mine "; then
    printf '%-9s %-60s %s\n' same "$rel" "$(echo "$hits" | grep "^$mine " | head -1 | awk '{print $2}')" >> "$OUT/audit.txt"; same=$((same+1)); continue
  fi
  src="$(echo "$hits" | head -1 | awk '{print $2}')"
  printf '%-9s %-60s %s\n' DIFFERS "$rel" "$src" >> "$OUT/audit.txt"; diff=$((diff+1))
  if [ "${PULL:-0}" = 1 ]; then
    adb exec-out "cat $src" < /dev/null > "$f.new" && mv "$f.new" "$f" && echo "  pulled $src -> $rel"
  fi
done < <(find "$ROOT" -type f -not -name '*.rc' -not -name '*.xml' -not -name '*.sh' -not -name '*.prop' -not -name '*.txt' -not -name '*.json' -not -name '*.conf' -not -name '*.config' -not -name '*.flags')

grep -vE '^same' "$OUT/audit.txt" | column -t
echo
echo "same=$same differs=$diff missing_on_device=$miss  (full report: $OUT/audit.txt)"
[ "${PULL:-0}" = 1 ] || [ "$diff" = 0 ] || echo "Re-run with PULL=1 to take the phone's versions of the DIFFERS rows."
