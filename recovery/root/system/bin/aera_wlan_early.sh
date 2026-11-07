#!/system/bin/sh
# Wi-Fi bring-up for lexus (WCN6750/qca6750 on WPSS). Adapted from AERA's
# peridot tree (same chip) with lexus facts:
#  - real MAC from persist (/mnt/vendor/persist/qca6750/wlan_mac.bin, the target
#    of the stock vendor symlink), not a generated one
#  - WPSS firmware name from the device tree: qca6750/wpss.mdt. Its location on
#    lexus is unconfirmed (not in modem, dsp, bluetooth, vendor/firmware, odm),
#    so every candidate is checked and logged
#  - boot sequence from the stock /vendor/etc/init/init.vendor.wlan.rc
PATH=/system/bin:/sbin:/vendor/bin
export PATH
LOG=/tmp/aera_wlan_early.log
log() {
    echo "[aera-wlan-early] uptime=$(cut -d ' ' -f 1 /proc/uptime) $*" >> "$LOG"
    echo "[aera-wlan-early] $*" > /dev/kmsg 2>/dev/null || true
}
fail() { log "STOP: $*"; exit 1; }
prop() { getprop "$1" 2>/dev/null; }
loaded() { grep -Eq "^($1|wlan) " /proc/modules 2>/dev/null; }

if [ -e /sys/class/net/wlan0 ]; then
    log "wlan0 already present; no WPSS re-boot"
    [ "$(prop wifi.driver.ready)" = true ] || setprop wifi.driver.ready true
    exit 0
fi
case "$(prop ro.aera.fastbootd)" in 1|true) log "fastbootd: skipping WLAN"; exit 0;; esac

# Modules come from AERA_POST_DECRYPT_MODULES; wait briefly for them
count=0
while [ "$count" -lt 100 ]; do
    ok=1
    for mod in cfg80211 icnss2 qca_cld3_qca6750; do loaded "$mod" || ok=0; done
    [ "$ok" = 1 ] && break
    sleep 0.1; count=$((count + 1))
done
for mod in cfg80211 icnss2 qca_cld3_qca6750; do loaded "$mod" || log "MISSING_MODULE: $mod"; done

# Real MAC: the driver requests wlan/qca_cld/qca6750/wlan_mac.bin
mac_src=/mnt/vendor/persist/qca6750/wlan_mac.bin
mac_dst=/vendor/firmware/wlan/qca_cld/qca6750/wlan_mac.bin
if [ -r "$mac_src" ]; then
    mkdir -p "$(dirname "$mac_dst")"
    ln -sf "$mac_src" "$mac_dst" && log "MAC: using $mac_src"
else
    log "MAC: $mac_src not readable; the driver will fall back to a random MAC"
fi

# Locate the WPSS image the kernel will request ("qca6750/wpss.mdt")
found=""
for dir in /vendor/firmware /vendor/firmware_mnt/image /firmware/image /odm/firmware /vendor/odm/firmware /mnt/vendor/persist; do
    if [ -r "$dir/qca6750/wpss.mdt" ]; then found="$dir/qca6750/wpss.mdt"; break; fi
done
if [ -n "$found" ]; then
    log "WPSS firmware: $found"
else
    log "WPSS firmware: qca6750/wpss.mdt NOT FOUND in any known location; booting anyway so the kernel log shows what it looked for"
fi
for f in bdwlan.b0e regdb.bin; do
    [ -r "/vendor/firmware/qca6750/$f" ] || log "board data missing: /vendor/firmware/qca6750/$f"
done

[ -w /sys/kernel/icnss/wlan_en_delay ] || fail "missing /sys/kernel/icnss/wlan_en_delay (icnss2 not loaded?)"
[ -w /sys/kernel/icnss/wpss_boot ] || fail "missing /sys/kernel/icnss/wpss_boot"
if [ ! -e /tmp/aera_wlan_wpss_requested ]; then
    : > /tmp/aera_wlan_wpss_requested || fail "cannot save WPSS boot marker"
    log "requesting WPSS boot (as the stock init.vendor.wlan.rc does)"
    printf '1000\n' > /sys/kernel/icnss/wlan_en_delay || fail "cannot set WLAN delay"
    printf '1\n' > /sys/kernel/icnss/wpss_boot || fail "cannot start WPSS"
else
    log "WPSS already requested; waiting without repeating boot"
fi

count=0
while [ "$count" -lt 45 ] && [ ! -e /sys/class/net/wlan0 ]; do
    sleep 1; count=$((count + 1))
done
if [ ! -e /sys/class/net/wlan0 ]; then
    dmesg 2>/dev/null | grep -iE 'wpss|icnss|cnss|firmware|qca6750' | tail -20 >> "$LOG"
    fail "wlan0 absent after 45s (kernel log tail saved to $LOG)"
fi
log "wlan0 up after ${count}s"
[ "$(prop wifi.driver.ready)" = true ] || setprop wifi.driver.ready true
