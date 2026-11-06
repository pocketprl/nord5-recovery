#!/bin/bash
# Usage: aera-lint.sh <bootable/recovery dir> <vendor/recovery dir> [device_tree_dir]
# Checks a device tree against AERA's sources before an expensive build:
#  - AERA_* flags that AERA never reads (typos, flags copied from other projects)
#  - flag combinations aera_build.mk rejects with $(error)
#  - TARGET_COPY_OUT_* without the filesystem type build/make requires
# Exits 1 if anything is reported.
rec="$1"; ven="$2"; tree="${3:-$(cd "$(dirname "$0")/.." && pwd)}"
cfg="$rec/aera_config.mk"
[ -f "$cfg" ] || { echo "aera_config.mk not found in $rec"; exit 2; }
known=$( {
  grep -oE 'aera-map-config,[A-Z0-9_]+' "$cfg" | cut -d, -f2
  awk '/^aera-legacy-[a-z-]+-options :=/{f=1;next} f&&/^\$\(foreach/{f=0} f{gsub(/[\\ ]/,""); if($0!="") print}' "$cfg"
  grep -oE 'origin AERA_[A-Z0-9_]+' "$cfg" | sed 's/origin AERA_//'
} | sort -u )
report() {
grep -rhoE '^\s*(export\s+)?AERA_[A-Z0-9_]+' "$tree" --include=*.mk --include=*.sh | sed -E 's/^\s*(export\s+)?AERA_//' | sort -u | while read -r f; do
  if echo "$known" | grep -qx "$f"; then continue; fi
  # Fall back to direct consumers anywhere in the AERA sources
  if grep -rqw "AERA_$f" "$rec" "$ven" --exclude-dir=.git 2>/dev/null; then continue; fi
  echo "UNKNOWN: AERA_$f"
done

# Combos AERA's aera_build.mk rejects with $(error ...). Values may come from
# makefiles (VAR := x) or vendorsetup.sh (export VAR=x).
val() { grep -rhoE "^\s*(export\s+)?AERA_$1\s*(:=|=)\s*\S+" "$tree" --include=*.mk --include=*.sh | tail -1 | sed -E 's/.*(:=|=)\s*//; s/"//g'; }
[ -n "$(val USE_DMSETUP)" ] && [ -n "$(val USE_DMCTL)" ] && echo "CONFLICT: AERA_USE_DMSETUP and AERA_USE_DMCTL are mutually exclusive"
[ "$(val FORCE_DATA_FORMAT_F2FS)" = 1 ] && [ "$(val FORCE_DATA_FORMAT_EXT4)" = 1 ] && echo "CONFLICT: FORCE_DATA_FORMAT_F2FS and _EXT4"
t="$(val BUILD_TYPE)"; [ -n "$t" ] && ! echo " Alpha Beta Nightly Stable " | grep -q " $t " && echo "INVALID: AERA_BUILD_TYPE=$t"
s="$(val BUILD_STATUS)"; [ -n "$s" ] && ! echo " Official Unofficial " | grep -q " $s " && echo "INVALID: AERA_BUILD_STATUS=$s"
# Every TARGET_COPY_OUT_<P> needs BOARD_<P>IMAGE_FILE_SYSTEM_TYPE (build/make board_config.mk)
for p in $(grep -rhoE '^\s*TARGET_COPY_OUT_[A-Z_]+\s*:=\s*[a-z_]+' "$tree" --include=*.mk | sed -E 's/^\s*TARGET_COPY_OUT_([A-Z_]+).*/\1/' | sort -u); do
  grep -rqE "^\s*BOARD_${p}IMAGE_FILE_SYSTEM_TYPE\s*:=" "$tree" --include=*.mk || echo "MISSING: BOARD_${p}IMAGE_FILE_SYSTEM_TYPE (needed for TARGET_COPY_OUT_$p)"
done
}
out="$(report)"
[ -z "$out" ] && { echo "aera-lint: OK"; exit 0; }
echo "$out"; exit 1
