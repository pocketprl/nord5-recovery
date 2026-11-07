#!/bin/bash
# Copyright (C) 2026 AERA Recovery Project contributors
# SPDX-License-Identifier: GPL-3.0-or-later

FDEVICE="lexus"

aera_get_target_device() {
local chkdev=$(echo "$BASH_SOURCE" | grep -w $FDEVICE)
   if [ -n "$chkdev" ]; then
      AERA_BUILD_DEVICE="$FDEVICE"
   else
      chkdev=$(set | grep BASH_ARGV | grep -w $FDEVICE)
      [ -n "$chkdev" ] && AERA_BUILD_DEVICE="$FDEVICE"
   fi
}

if [ -z "$1" -a -z "$AERA_BUILD_DEVICE" ]; then
   aera_get_target_device
fi

if [ "$1" = "$FDEVICE" -o "$AERA_BUILD_DEVICE" = "$FDEVICE" ]; then
	export ALLOW_MISSING_DEPENDENCIES=true
	export LC_ALL="C"
	export AERA_AB_DEVICE=1
	export AERA_VIRTUAL_AB_DEVICE=1
	export AERA_USE_TAR_BINARY=1
	export AERA_USE_SED_BINARY=1
	export AERA_USE_LZ4_BINARY=1
	export AERA_USE_ZSTD_BINARY=1
	export AERA_USE_DATE_BINARY=1
	export AERA_USE_GREP_BINARY=1
	export AERA_USE_BUSYBOX_BINARY=1
	export AERA_USE_XZ_UTILS=1
	export AERA_USE_UPDATED_MAGISKBOOT=1
	export AERA_USE_FSCK_EROFS_BINARY=1
	export AERA_USE_PATCHELF_BINARY=1
	export AERA_VANILLA_BUILD=1
	export AERA_ALLOW_EARLY_SETTINGS_LOAD=1
	export AERA_SETTINGS_ROOT_DIRECTORY=/data/recovery
	export AERA_MISCELLANEOUS_ROOT_DIRECTORY=/sdcard
	export AERA_PRODUCT_PREFIX=AERA
	export AERA_BUILD_STATUS=Unofficial
	export AERA_BUILD_TYPE=Alpha

	# OnePlus Nord 5: global/EU (CPH2709, prjname 24881) and India (CPH2707) [TW]
	export TARGET_DEVICE_ALT="lexus,OP6131L1,CPH2709,CPH2707"
	export AERA_TARGET_DEVICES="$TARGET_DEVICE_ALT"
	export AERA_USE_DMSETUP=1
	# KernelSU / KernelSU-Next / SukiSU-Ultra root manager (kernel 6.1 assets only)
	export AERA_ENABLE_ROOT_MANAGER=1
fi
