#!/bin/bash
# Usage: 04-test-image.sh <recovery.img> [--also-other-slot]
#
# Phone in BOOTLOADER. Flashes the image to recovery on the CURRENT slot (the
# only one that boots), reboots into it, proves the partition holds exactly
# this image, then collects everything worth reading.
#
#   --also-other-slot  also write the inactive slot's recovery, so a later slot
#                      switch or OTA keeps it. That copy is NOT booted or tested.
#
# Never switches slots. Every check runs before anything is written, and any
# failure stops the script before it reboots.
set -euo pipefail
. "$(dirname "$0")/lib/log.sh"

IMG="${1:-}"
[ -n "$IMG" ] || die "usage: $0 <recovery.img> [--also-other-slot]"
ALSO_OTHER=0
case "${2:-}" in
  "") ;;
  --also-other-slot) ALSO_OTHER=1 ;;
  *) die "unknown option: $2 (slots are chosen automatically; see the header)" ;;
esac
[ -f "$IMG" ] || die "no such file: $IMG"
OUT="${OUT:-$PWD/lexus-device-logs/$(date +%Y%m%d-%H%M%S)-test}"
BOOT_TIMEOUT="${BOOT_TIMEOUT:-150}"

# ---------------------------------------------------------------- preflight
[ "$(head -c 8 "$IMG")" = "ANDROID!" ] || die "not an android boot image (no ANDROID! magic)"

ndev=$(fastboot devices | grep -c . || true)
[ "$ndev" -eq 1 ] || die "need exactly one fastboot device, found $ndev"

gv() {
  local out
  out=$(fastboot getvar "$1" 2>&1) || die "fastboot getvar $1 failed: $out"
  sed -nE "s/^$1: ?//p" <<<"$out" | head -1
}

[ "$(gv unlocked)" = "yes" ] || die "bootloader is NOT unlocked"

cur="$(gv current-slot)"; cur="${cur#_}"
case "$cur" in a|b) ;; *) die "unexpected current-slot: '$cur'" ;; esac
other=$([ "$cur" = a ] && echo b || echo a)

slots="$cur"
if [ "$ALSO_OTHER" = 1 ]; then slots="$cur $other"; fi

img_sz=$(stat -c %s "$IMG")
img_sha=$(sha256sum "$IMG" | cut -d' ' -f1)
for s in $slots; do
  [ "$(gv "slot-unbootable:$s")" != "yes" ] || die "slot $s is marked unbootable (normal after an ota); not touching it"
  raw=$(gv "partition-size:recovery_$s")
  part_sz=$(printf '%d' "$raw" 2>/dev/null) || die "unreadable partition-size for recovery_$s: '$raw'"
  [ "$part_sz" -gt 0 ] && [ "$img_sz" -le "$part_sz" ] || die "recovery_$s: image $img_sz B does not fit $part_sz B"
  ok "recovery_$s: image $img_sz b fits in $part_sz b"
done

mkdir -p "$OUT"
cp "$IMG" "$OUT/flashed.img"
echo "$img_sha  flashed.img" > "$OUT/flashed.sha256"
hdr "plan"
kv "image" "$IMG"
kv "sha256" "$img_sha"
kv "will flash" "$(for s in $slots; do printf 'recovery_%s ' "$s"; done)"
kv "will boot" "recovery_$cur (current slot)"
if [ "$ALSO_OTHER" = 1 ]; then warn "recovery_$other gets written but will NOT be booted or verified."; fi

# ---------------------------------------------------------------- flash
hdr "flash"
for s in $slots; do
  log="$OUT/fastboot-flash-$s.txt"
  act "fastboot flash recovery_$s"
  if ! fastboot flash "recovery_$s" "$IMG" 2>&1 | tee "$log"; then
    die "fastboot flash recovery_$s failed; NOT REBOOTING. log: $log"
  fi
  ! grep -qiE 'FAILED|error' "$log" || die "fastboot reported an error for recovery_$s; NOT REBOOTING. log: $log"
done

act "fastboot reboot recovery"
fastboot reboot recovery 2>&1 | tee "$OUT/fastboot-reboot.txt" \
  || die "fastboot reboot recovery failed; phone should still be in the bootloader"

# ---------------------------------------------------------------- boot
hdr "boot"
info "waiting up to ${BOOT_TIMEOUT}s for adb in recovery"
if ! timeout "$BOOT_TIMEOUT" adb wait-for-recovery; then
  err "NO ADB after ${BOOT_TIMEOUT}s. recovery_$cur holds the new image but did not come up."
  warn "stuck/black screen: hold power + vol up ~10s, then power + vol down for the bootloader"
  warn "then: fastboot flash recovery_$cur <known-good image>"
  exit 2
fi

# ---------------------------------------------------------------- verify
ok "adb is up"
hdr "verify"
booted=$(adb shell getprop ro.boot.slot_suffix | tr -d '\r')
[ "$booted" = "_$cur" ] || die "booted slot is '$booted', expected _$cur"

if [ "$(adb shell id -u | tr -d '\r')" = "0" ]; then
  dev_sha=$(adb shell "head -c $img_sz /dev/block/by-name/recovery_$cur | sha256sum" | tr -d '\r' | cut -d' ' -f1)
  [ "$dev_sha" = "$img_sha" ] \
    || die "recovery_$cur does NOT match the image (device $dev_sha, image $img_sha); the flash did not take"
  ok "booted slot _$cur"
  ok "recovery_$cur on the phone matches the image (sha256 $img_sha)"
else
  warn "adb is not root, so the flashed partition could NOT be verified"
fi

# ---------------------------------------------------------------- collect
hdr "collect"
act "pulling logs -> $OUT"
a() { adb shell "$1" 2>&1 | tr -d '\r' > "$OUT/$2" || true; }
adb pull /tmp/recovery.log "$OUT/recovery.log" >/dev/null 2>&1 || warn "no /tmp/recovery.log"
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
a 'for z in /sys/class/thermal/thermal_zone*; do echo "${z##*/} $(cat $z/type)"; done' thermal.txt
# GPU: AERA only falls back to software when GPU *setup* fails; a GPU that
# initialises but rejects frames leaves the screen black (see gpu/README.md)
a 'aera-gpu-probe 2>&1; echo "probe_exit=$?"' gpu-probe.txt
a 'logcat -d 2>/dev/null | grep -iE "adreno|kgsl|gpu display|software mode|rejected the lvgl" | tail -20' gpu-log.txt
# Remote processors: name, firmware file and state. Answers where qca6750/wpss.mdt
# really comes from (not found in any OTA partition before unlock).
a 'for r in /sys/class/remoteproc/remoteproc*; do echo "$(cat $r/name 2>/dev/null) firmware=$(cat $r/firmware 2>/dev/null) state=$(cat $r/state 2>/dev/null)"; done' remoteproc.txt
a 'cat /tmp/aera_wlan_early.log 2>/dev/null; ip link show wlan0 2>&1' wlan.txt
a 'logcat -d -s AERA-Audio 2>/dev/null | tail -40' audio.txt

first() { grep -m1 "$@" 2>/dev/null || true; }
hdr "services"
grep -E '^\[init\.svc\.' "$OUT/getprop.txt" 2>/dev/null | sed 's/^/     /' || true
hdr "summary"
kv "cpu temp zone3:" "$(first -E '^thermal_zone3 ' "$OUT/thermal.txt") (tree expects cpuss-0)"
kv "touch input:" "$(first -iE '^N: Name=.*(touchpanel|touch|tcm|syna|s3910)' "$OUT/input-devices.txt")"
kv "modules loaded prop:" "$(first -F '[twrp.modules.loaded]' "$OUT/getprop.txt")"
kv "crypto state:" "$(grep -E '^\[ro\.crypto\.(state|type)\]' "$OUT/getprop.txt" 2>/dev/null | tr '\n' ' ' || true)"
kv "decrypted:" "$(first -F '[twrp.all.users.decrypted]' "$OUT/getprop.txt")"
kv "backlight max/cur:" "$(tr '\n' ' ' < "$OUT/backlight.txt")"
kv "battery %:" "$(cat "$OUT/battery.txt")"
gpu=$(first -E '^AERA GPU ready|aera-gpu-probe:' "$OUT/gpu-probe.txt")
kv "gpu probe:" "${gpu:-<no output>} ($(first -oE 'probe_exit=[0-9]+' "$OUT/gpu-probe.txt"))"
if grep -qiE 'rejected the lvgl' "$OUT/gpu-log.txt" 2>/dev/null; then
  err "AERA logged rejected GPU frames: the screen may be black. software fallback: REMOVE=vendor/lib64/egl tools/05-repack.sh <img>"
fi
kv "wpss remoteproc:" "$(first -iE 'wpss' "$OUT/remoteproc.txt")"
kv "wlan:" "$(grep -E 'STOP:|wlan0 up|WPSS firmware:' "$OUT/wlan.txt" 2>/dev/null | tail -2 | tr '\n' ' ' || true)"
kv "audio stage:" "$(grep -oE '(FAILED )?stage=[a-z0-9-]+.*|backend is ready' "$OUT/audio.txt" 2>/dev/null | tail -1 || true)"
hdr "errors in recovery.log (first 25)"
grep -iE '^E:|failed|unable' "$OUT/recovery.log" 2>/dev/null | head -25 | sed 's/^/     /' || true
echo
info "full logs: $OUT"
