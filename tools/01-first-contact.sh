#!/bin/bash
# Run with the phone in the BOOTLOADER (Power + Vol Down from off).
# Read-only: dumps `fastboot getvar all` and checks it against the tree's
# VERIFY values. Writes nothing to the phone.
set -u
TREE="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${OUT:-$HOME/aera-lexus/device-logs/$(date +%Y%m%d-%H%M%S)-getvar}"
mkdir -p "$OUT"

fastboot devices | tee "$OUT/devices.txt"
[ -s "$OUT/devices.txt" ] || { echo "No fastboot device. Bootloader mode + cable?"; exit 1; }

# getvar writes to stderr
fastboot getvar all 2>&1 | tee "$OUT/getvar-all.txt"
gv() { grep -m1 -E "^\(bootloader\) $1:" "$OUT/getvar-all.txt" | sed -E "s/^\(bootloader\) $1: ?//"; }
hex2dec() { [ -n "$1" ] && printf '%d' "$1" 2>/dev/null; }
mk() { grep -hE "^\s*$1\s*:=" "$TREE"/BoardConfig.mk "$TREE"/aera_lexus.mk | head -1 | sed -E 's/.*:= *//; s/ *#.*//'; }

echo
echo "================ lexus first contact ================"
printf '%-24s %s\n' product "$(gv product)" unlocked "$(gv unlocked)" \
  current-slot "$(gv current-slot)" is-userspace "$(gv is-userspace)" \
  secure "$(gv secure)" hw-revision "$(gv hw-revision)"

check() { # name, device value, tree value
  local s="OK"; [ "$2" = "$3" ] || s="MISMATCH -> update tree"
  [ -z "$2" ] && s="not reported (check by hand)"
  printf '%-24s device=%-14s tree=%-14s %s\n' "$1" "${2:-?}" "$3" "$s"
}
check super       "$(hex2dec "$(gv partition-size:super)")"       "$(mk BOARD_SUPER_PARTITION_SIZE)"
check recovery_a  "$(hex2dec "$(gv partition-size:recovery_a)")"  "$(mk BOARD_RECOVERYIMAGE_PARTITION_SIZE)"
check boot_a      "$(hex2dec "$(gv partition-size:boot_a)")"      "$(mk BOARD_BOOTIMAGE_PARTITION_SIZE)"
check vendor_boot_a "$(hex2dec "$(gv partition-size:vendor_boot_a)")" "$(mk BOARD_VENDOR_BOOTIMAGE_PARTITION_SIZE)"
check dtbo_a      "$(hex2dec "$(gv partition-size:dtbo_a)")"      "$(mk BOARD_DTBOIMG_PARTITION_SIZE)"
check init_boot_a "$(hex2dec "$(gv partition-size:init_boot_a)")" "$(mk BOARD_INIT_BOOT_IMAGE_PARTITION_SIZE)"

echo
echo "Logical partitions on this firmware (my_* should match recovery.fstab):"
grep -E '^\(bootloader\) is-logical:[^:]+:yes' "$OUT/getvar-all.txt" | sed -E 's/.*is-logical:([^:]+):yes/  \1/' | sort -u
[ "$(gv unlocked)" = "yes" ] || echo "!! Bootloader reports LOCKED. Stop here."
echo "Saved: $OUT"
