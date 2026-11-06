#!/bin/bash
# Run with the phone in a WORKING RECOVERY that has root adb (official TWRP first).
# Read-only on the phone: copies small/critical partitions to the PC.
# Lists sizes and asks before transferring anything. Skips super and userdata.
set -uo pipefail
. "$(dirname "$0")/lib/log.sh"
OUT="${OUT:-$PWD/lexus-device-backup/$(date +%Y%m%d-%H%M%S)}"
MAX_MB="${MAX_MB:-256}"   # skip anything bigger than this (super/userdata are excluded regardless)

adb get-state >/dev/null 2>&1 || { err "no adb device. is recovery up?"; exit 1; }
[ "$(adb shell id -u | tr -d '\r')" = "0" ] || { err "adb is not root."; exit 1; }

# Needed first no matter what: IMEI/calibration/sensor data and OnePlus-specific bits
CRITICAL='persist modemst1 modemst2 fsg fsc oplusstanvbk_a oplusstanvbk_b oplus_sec_a oplus_sec_b oplusreserve1 oplusreserve2 devinfo frp'
is_critical() { case " $CRITICAL " in *" $1 "*) return 0;; esac; return 1; }
mbs() { echo "$1/1048576" | bc -l | xargs printf '%.1f mb'; }

act "reading partition table (blockdev --getsize64 over /dev/block/by-name)"
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
    info "skip $(printf '%-24s %6d mb' "$n" "$mb") (over MAX_MB=$MAX_MB)"
  fi
done < /tmp/lexus-parts.txt

[ -s /tmp/lexus-parts.txt ] || { err "could not read the partition table (is adb root?). NOTHING BACKED UP."; exit 1; }
hdr "critical partitions"
missing=0
for c in $CRITICAL; do
  line=$(grep -E "^$c " /tmp/lexus-plan.txt || true)
  if [ -n "$line" ]; then ok "$(printf '%-22s %s' "$c" "$(mbs "${line#* }")")"
  else err "$(printf '%-22s' "$c") MISSING (absent or size unreadable)"; missing=$((missing+1)); fi
done
if [ "$missing" -gt 0 ] && [ "${ALLOW_MISSING_CRITICAL:-0}" != 1 ]; then
  err "$missing critical partition(s) missing. check the names above; set ALLOW_MISSING_CRITICAL=1 only if you know why."
  exit 1
fi
hdr "plan"
info "$(wc -l < /tmp/lexus-plan.txt) partitions, $(mbs "$total") total -> $OUT"
if [ "${YES:-0}" != 1 ]; then read -r -p "$(warn 'proceed? [y/N] ')" a; [ "$a" = "y" ] || exit 0; fi

mkdir -p "$OUT"; cp /tmp/lexus-parts.txt "$OUT/partition-table.txt"
hdr "copy + verify (sha256 on both ends)"
# Critical ones first so a cable yank still leaves the important stuff saved
{ while read -r n s; do is_critical "$n" && echo "$n $s"; done < /tmp/lexus-plan.txt
  while read -r n s; do is_critical "$n" || echo "$n $s"; done < /tmp/lexus-plan.txt; } |
while read -r n s; do
  act "$(printf '%-24s %s' "$n" "$(mbs "$s")")"
  adb exec-out "cat /dev/block/by-name/$n" < /dev/null > "$OUT/$n.img"
  got=$(stat -c %s "$OUT/$n.img")
  if [ "$got" != "$s" ]; then err "$n: SIZE MISMATCH ($got != $s)"; echo "$n" >> "$OUT/FAILED"; continue; fi
  # exec-out exits 0 even on read errors; compare hashes on both ends
  dev=$(adb shell "sha256sum /dev/block/by-name/$n" < /dev/null | tr -d '\r' | cut -d' ' -f1)
  loc=$(sha256sum "$OUT/$n.img" | cut -d' ' -f1)
  if [ -n "$dev" ] && [ "$dev" = "$loc" ]; then ok "$n  sha256 ${loc:0:16}… matches"; echo "$loc  $n.img" >> "$OUT/SHA256SUMS"
  else err "$n: HASH MISMATCH (device ${dev:-<none>}, local $loc)"; echo "$n" >> "$OUT/FAILED"; fi
done
if [ -s "$OUT/FAILED" ]; then
  err "backup INCOMPLETE. failed: $(tr '\n' ' ' < "$OUT/FAILED")"
  err "re-run before flashing anything."; exit 1
fi
ok "done: every partition verified -> $OUT"
warn "copy it somewhere that is NOT this pc as well."
