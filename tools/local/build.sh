#!/bin/bash
# Local AERA build after tools/local/sync.sh finished.
#   tools/local/build.sh [eng|userdebug|user]
#
#   SRC   source root (default ~/aera-lexus/src)
#   CCACHE_DIR  default $SRC/out/.ccache (must be under out/, see below)
#   JOBS  ninja jobs (default: one per ~1.2 GB of RAM, capped at nproc;
#         32 parallel clang jobs on 14 GB would OOM)
#
# The device tree is copied (not symlinked: soong does not follow symlinked
# directories) into $SRC/device/oneplus/lexus before every build.
set -euo pipefail
. "$(dirname "$(readlink -f "$0")")/../lib/log.sh"
TREE="$(cd "$(dirname "$(readlink -f "$0")")/../.." && pwd)"
SRC="${SRC:-$HOME/aera-lexus/src}"
VARIANT="${1:-eng}"
mem_gb=$(awk '/^MemTotal/{printf "%d", $2/1048576}' /proc/meminfo)
JOBS="${JOBS:-$(( mem_gb * 10 / 12 < $(nproc) ? mem_gb * 10 / 12 : $(nproc) ))}"

[ -f "$SRC/.sync-complete" ] || die "source not synced yet ($SRC/.sync-complete missing); run tools/local/start-sync.sh"

hdr "local build: twrp_lexus-bp2a-$VARIANT"
kv "source" "$SRC"
kv "jobs" "$JOBS (RAM ${mem_gb}G, $(nproc) threads)"
swapon --show=NAME,SIZE,PRIO --noheadings 2>/dev/null | while read -r n s p; do kv "swap" "$n $s prio $p"; done
[ "$(free -g | awk '/^Swap/{print $2}')" -ge 16 ] \
  || warn "under 16G of swap: soong_build peaked at ~12.5G RSS + 9G swap in CI; analysis may get OOM-killed"

act "syncing device tree -> device/oneplus/lexus"
mkdir -p "$SRC/device/oneplus"
rsync -a --delete --exclude .git --exclude 'lexus-device-*' "$TREE/" "$SRC/device/oneplus/lexus/"

# Inside out/: Android 16 runs build actions in a sandbox where everything
# outside out/ is read-only, so a cache in ~/.cache fails with EROFS. (CI
# doesn't hit this: Ubuntu 26.04 blocks the user namespaces the sandbox needs.)
export USE_CCACHE=1 CCACHE_EXEC="$(command -v ccache)" CCACHE_DIR="${CCACHE_DIR:-$SRC/out/.ccache}"
mkdir -p "$CCACHE_DIR"
ccache -M 20G >/dev/null
ccache -z >/dev/null

cd "$SRC"
set +u   # envsetup.sh is not nounset-clean
source build/envsetup.sh >/dev/null
lunch "twrp_lexus-bp2a-$VARIANT"
set -u

"$TREE/tools/ci/heartbeat.sh" "$SRC" 60 & hb=$!
trap 'kill $hb 2>/dev/null || true' EXIT
start=$(date +%s)
rc=0
build/soong/soong_ui.bash --make-mode -j"$JOBS" adbd recoveryimage || rc=$?
mins=$(( ($(date +%s) - start) / 60 ))

ccache -s | grep -iE 'hits|misses' | sed 's/^/     /' || true
if [ $rc -ne 0 ]; then
  err "build FAILED after ${mins} min (exit $rc)"
  tail -40 out/error.log 2>/dev/null | sed 's/^/     /' || true
  exit $rc
fi
img="out/target/product/lexus/recovery.img"
ok "built in ${mins} min: $SRC/$img"
kv "size" "$(stat -c %s "$img") bytes"
kv "sha256" "$(sha256sum "$img" | cut -d' ' -f1)"
