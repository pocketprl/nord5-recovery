#!/bin/bash
# Mock-driven behaviour tests for tools/02-backup.sh and tools/04-test-image.sh.
# Prints one line per scenario: name, exit code, and a hash of the exact
# fastboot/adb call sequence. Cosmetic changes must leave this output identical.
#
#   tools/test/run-tool-tests.sh tools | diff tools/test/expected.txt -
#
# Update expected.txt only for intended behaviour changes, and review the diff.
T=$(realpath "${1:?tools dir}"); H=$(mktemp -d); trap 'rm -rf $H' EXIT; mkdir -p $H/bin $H/dev
cat > $H/bin/fastboot <<'EOF'
#!/bin/bash
echo "fastboot $*" >> "$H_CALLS"
case "$1" in
  devices) for i in $(seq ${NDEV:-1}); do echo "SERIAL$i	fastboot"; done;;
  getvar) case "$2" in
     unlocked) echo "unlocked: yes" >&2;; current-slot) echo "current-slot: a" >&2;;
     slot-unbootable:a) echo "slot-unbootable:a: no" >&2;; slot-unbootable:b) echo "slot-unbootable:b: ${UNBOOT_B:-yes}" >&2;;
     partition-size:recovery_*) echo "$2: 0x6400000" >&2;; esac;;
  flash) if [ "${FLASH_FAIL:-0}" = 1 ]; then echo "FAILED (remote: 'not allowed')" >&2; exit 1; fi; echo "Sending '$2' OKAY" >&2;;
  reboot) echo "Rebooting OKAY" >&2;;
esac
EOF
cat > $H/bin/adb <<'EOF'
#!/bin/bash
echo "adb $*" >> "$H_CALLS"
last="${@: -1}"; last="${last##*/}"; D=$MOCKDEV
case "$1 ${2%% *}" in
  "get-state ") echo device;;
  "wait-for-recovery ") exit 0;;
  "shell getprop") [ "$3" = ro.boot.slot_suffix ] && echo "${BOOTED:-_a}";;
  "shell id") echo 0;;
  "shell head") echo "${DEV_SHA:-$(sha256sum "$IMG_PATH" | cut -d' ' -f1)}  -";;
  "shell for") [ "${EMPTY:-0}" = 1 ] || for f in $D/*; do echo "$(basename $f) $(stat -c %s $f)"; done;;
  "exec-out cat") if [ "$last" = "${CORRUPT:-none}" ]; then head -c $(stat -c %s $D/$last) /dev/zero; else cat $D/$last; fi;;
  "shell sha256sum") sha256sum $D/$last;;
esac
EOF
chmod +x $H/bin/*
printf 'ANDROID!' > $H/img; head -c 8184 /dev/urandom >> $H/img
for n in persist modemst1 modemst2 fsg fsc oplusstanvbk_a oplusstanvbk_b oplus_sec_a oplus_sec_b oplusreserve1 oplusreserve2 devinfo frp boot_a dtbo_a; do
  head -c $(( $(printf '%s' "$n" | cksum | cut -d' ' -f1) % 50000 + 4096 )) /dev/urandom > $H/dev/$n; done
# run <name> "<VAR=x ...>" <script> [args...]
run() { name=$1; vars=$2; script=$3; shift 3; : > $H/calls
  (cd $H && env PATH=$H/bin:$PATH H_CALLS=$H/calls IMG_PATH=$H/img MOCKDEV=$H/dev YES=1 OUT=$H/out $vars bash $T/$script "$@" >$H/stdout 2>&1); rc=$?
  rm -rf $H/out
  printf '%-36s exit=%s calls=%s %s\n' "$name" $rc "$(sed "s|$H|H|g" $H/calls | sha256sum | cut -c1-12)" "$(grep -cE 'reboot' $H/calls)reboots"; }
run "04 flash fails" "FLASH_FAIL=1" 04-test-image.sh $H/img
run "04 also-other b unbootable" "" 04-test-image.sh $H/img --also-other-slot
run "04 also-other b bootable" "UNBOOT_B=no" 04-test-image.sh $H/img --also-other-slot
run "04 happy" "" 04-test-image.sh $H/img
run "04 hash mismatch" "DEV_SHA=deadbeef" 04-test-image.sh $H/img
run "04 wrong slot" "BOOTED=_b" 04-test-image.sh $H/img
run "04 two devices" "NDEV=2" 04-test-image.sh $H/img
run "04 bad option" "" 04-test-image.sh $H/img b
run "02 clean" "" 02-backup.sh
run "02 modemst2 corrupt" "CORRUPT=modemst2" 02-backup.sh
run "02 table unreadable" "EMPTY=1" 02-backup.sh
mv $H/dev/fsg $H/fsg.bak; run "02 critical missing" "" 02-backup.sh ; mv $H/fsg.bak $H/dev/fsg
