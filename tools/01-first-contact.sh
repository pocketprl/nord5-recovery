#!/bin/bash
# Run with the phone in the BOOTLOADER (Power + Vol Down from off).
# Read-only: dumps `fastboot getvar all` and checks it against the tree's
# VERIFY values. Writes nothing to the phone.
set -uo pipefail
TREE="$(cd "$(dirname "$0")/.." && pwd)"
. "$TREE/tools/lib/log.sh"
OUT="${OUT:-$PWD/lexus-device-logs/$(date +%Y%m%d-%H%M%S)-getvar}"
mkdir -p "$OUT"

act "fastboot devices"
fastboot devices | tee "$OUT/devices.txt"
[ -s "$OUT/devices.txt" ] || { err "no fastboot device. bootloader mode + cable?"; exit 1; }

# getvar writes to stderr
act "fastboot getvar all"
fastboot getvar all 2>&1 | tee "$OUT/getvar-all.txt"
gv() { grep -m1 -E "^\(bootloader\) $1:" "$OUT/getvar-all.txt" | sed -E "s/^\(bootloader\) $1: ?//"; }
hex2dec() { [ -n "$1" ] && printf '%d' "$1" 2>/dev/null; }
mk() { grep -hE "^\s*$1\s*:=" "$TREE"/BoardConfig.mk "$TREE"/aera_lexus.mk | head -1 | sed -E 's/.*:= *//; s/ *#.*//'; }

hdr "lexus first contact"
kv product      "$(gv product)"
kv unlocked     "$(gv unlocked)"
kv current-slot "$(gv current-slot)"
kv is-userspace "$(gv is-userspace)"
kv secure       "$(gv secure)"
kv hw-revision  "$(gv hw-revision)"

hdr "partition sizes vs tree"
check() { # name, device value, tree value
  local line
  line=$(printf '%-16s device=%-14s tree=%s' "$1" "${2:-?}" "$3")
  if [ -z "$2" ]; then warn "$line  (not reported, check by hand)"
  elif [ "$2" = "$3" ]; then ok "$line"
  else err "$line  MISMATCH, update the tree"; fi
}
check super       "$(hex2dec "$(gv partition-size:super)")"       "$(mk BOARD_SUPER_PARTITION_SIZE)"
check recovery_a  "$(hex2dec "$(gv partition-size:recovery_a)")"  "$(mk BOARD_RECOVERYIMAGE_PARTITION_SIZE)"
check boot_a      "$(hex2dec "$(gv partition-size:boot_a)")"      "$(mk BOARD_BOOTIMAGE_PARTITION_SIZE)"
check vendor_boot_a "$(hex2dec "$(gv partition-size:vendor_boot_a)")" "$(mk BOARD_VENDOR_BOOTIMAGE_PARTITION_SIZE)"
check dtbo_a      "$(hex2dec "$(gv partition-size:dtbo_a)")"      "$(mk BOARD_DTBOIMG_PARTITION_SIZE)"
check init_boot_a "$(hex2dec "$(gv partition-size:init_boot_a)")" "$(mk BOARD_INIT_BOOT_IMAGE_PARTITION_SIZE)"

hdr "logical partitions (my_* should match recovery.fstab)"
grep -E '^\(bootloader\) is-logical:[^:]+:yes' "$OUT/getvar-all.txt" | sed -E 's/.*is-logical:([^:]+):yes/     \1/' | sort -u
echo
[ "$(gv unlocked)" = "yes" ] || err "bootloader reports LOCKED. stop here."
info "saved: $OUT"
