#!/bin/bash
# Usage: 05-repack.sh <base-recovery.img> [out.img] [overlay-dir]
# Fast loop without a rebuild: unpack a built AERA (or TWRP) recovery image,
# overlay files from the tree's recovery/root (or overlay-dir), repack.
# Only ramdisk content changes; anything that needs BoardConfig flags or C++ changes
# still needs a real build.
set -eu
BASE="${1:?usage: $0 <base-recovery.img> [out.img] [overlay-dir]}"
OUTIMG="${2:-$(dirname "$BASE")/$(basename "$BASE" .img)-repacked.img}"
TREE="$(cd "$(dirname "$0")/.." && pwd)"
OVERLAY="${3:-$TREE/recovery/root}"
MB="${MAGISKBOOT:-$HOME/aera-lexus/bin/magiskboot}"
[ -x "$MB" ] || { echo "magiskboot not found at $MB"; exit 1; }

BASE="$(realpath "$BASE")"; OUTIMG="$(realpath -m "$OUTIMG")"; OVERLAY="$(realpath "$OVERLAY")"
W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT
cd "$W"
"$MB" unpack -h "$BASE"
[ -f ramdisk.cpio ] || { echo "No ramdisk in image."; exit 1; }

# unpack leaves ramdisk.cpio decompressed; repack recompresses it in the original format

cmds=()
while IFS= read -r d; do
  rel="${d#$OVERLAY/}"; [ "$d" = "$OVERLAY" ] && continue
  cmds+=("mkdir 0755 $rel")
done < <(find "$OVERLAY" -type d | sort)
n=0
while IFS= read -r f; do
  rel="${f#$OVERLAY/}"
  mode=0644; [ -x "$f" ] && mode=0755
  cmds+=("add $mode $rel $f"); n=$((n+1))
done < <(find "$OVERLAY" -type f | sort)
"$MB" cpio ramdisk.cpio "${cmds[@]}"
echo "overlaid $n files from $OVERLAY"

"$MB" repack "$BASE" "$OUTIMG"
ls -la "$OUTIMG"
