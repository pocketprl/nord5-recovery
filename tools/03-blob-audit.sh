#!/bin/bash
# Run with the phone in a recovery that has root adb.
# Compares every ELF/firmware blob in recovery/root against the phone's own
# /vendor, /odm, /system and /system_ext, matched by file name.
#   PULL=1  also copies the phone's version over every differing ramdisk blob
# Writes nothing to the phone (partitions get mounted read-only).
set -uo pipefail
TREE="$(cd "$(dirname "$0")/.." && pwd)"
. "$TREE/tools/lib/log.sh"
ROOT="$TREE/recovery/root"
OUT="${OUT:-$PWD/lexus-device-logs/$(date +%Y%m%d-%H%M%S)-blobs}"
mkdir -p "$OUT"

adb get-state >/dev/null 2>&1 || { err "no adb device."; exit 1; }

act "mounting stock partitions read-only (errors are fine if already mounted)"
adb shell 'for m in /vendor /odm /system_root /system /system_ext /vendor_dlkm; do mount -o ro $m 2>&1 | sed "s|^|     $m: |"; done' | tr -d '\r'

act "indexing phone files (sha256 of .so/.bin/.mbn/.fw/.img + */bin/*)"
adb shell 'for d in /vendor /odm /system_root/system /system /system_ext; do
  [ -d $d ] && find $d -type f \( -name "*.so" -o -name "*.bin" -o -name "*.mbn" -o -name "*.fw" -o -name "*.img" -o -path "*/bin/*" \) 2>/dev/null
done | xargs sha256sum 2>/dev/null' | tr -d '\r' > "$OUT/device-index.txt"
info "$(wc -l < "$OUT/device-index.txt") files indexed"

printf '%-9s %-60s %s\n' STATUS RAMDISK_PATH DEVICE_PATH > "$OUT/audit.txt"
same=0; diff=0; miss=0; failed=0
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
    # exec-out exits 0 even when cat fails, so only the hash proves the copy
    want="$(echo "$hits" | head -1 | awk '{print $1}')"
    adb exec-out "cat $src" < /dev/null > "$f.new"
    if [ "$(sha256sum "$f.new" | cut -d' ' -f1)" = "$want" ]; then
      mv "$f.new" "$f"; ok "pulled $src -> $rel (sha256 verified)"
    else
      rm -f "$f.new"; err "$src: copy does NOT match the phone's hash, kept the old file"; failed=$((failed+1))
    fi
  fi
done < <(find "$ROOT" -type f -not -name '*.rc' -not -name '*.xml' -not -name '*.sh' -not -name '*.prop' -not -name '*.txt' -not -name '*.json' -not -name '*.conf' -not -name '*.config' -not -name '*.flags')

hdr "blobs that are not identical to the phone"
grep -vE '^same' "$OUT/audit.txt" | column -t | sed 's/^/     /'
echo
info "same=$same differs=$diff missing_on_device=$miss  (full report: $OUT/audit.txt)"
[ "${PULL:-0}" = 1 ] || [ "$diff" = 0 ] || warn "re-run with PULL=1 to take the phone's versions of the DIFFERS rows."
[ "$failed" = 0 ] || { err "$failed pull(s) FAILED verification"; exit 1; }
