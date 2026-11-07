#
# Copyright (C) 2026 The Android Open Source Project
# Copyright (C) 2026 AERA Recovery Project contributors
#
# SPDX-License-Identifier: Apache-2.0
#
# OnePlus Nord 5 (lexus) - SM8635 "cliffs" on the pineapple platform.
#
# Every value below comes from a published source, tagged inline:
#   [TW]  TeamWin/android_device_oneplus_lexus (official TWRP, targets CPH2709)
#   [LOS] LineageOS/android_device_oneplus_lexus + sm8650-common
#   [AERA-peridot] / [AERA-waffle] AERA trees for SM8635 / OnePlus pineapple
# Values marked VERIFY are checked against `fastboot getvar all` on first plug-in.
#

DEVICE_PATH := device/oneplus/lexus

ALLOW_MISSING_DEPENDENCIES := true
BUILD_BROKEN_DUP_RULES := true
BUILD_BROKEN_ELF_PREBUILT_PRODUCT_COPY_FILES := true
BUILD_BROKEN_NINJA_USES_ENV_VARS += RTIC_MPGEN
BUILD_BROKEN_PLUGIN_VALIDATION := soong-libaosprecovery_defaults soong-libguitwrp_defaults soong-libminuitwrp_defaults soong-vold_defaults

# Architecture [AERA-waffle]
TARGET_ARCH := arm64
TARGET_ARCH_VARIANT := armv8-a
TARGET_CPU_ABI := arm64-v8a
TARGET_CPU_VARIANT := kryo

# Platform [LOS] board-info.txt: require board=pineapple|OP6131L1
PRODUCT_PLATFORM := pineapple
TARGET_BOARD_PLATFORM := pineapple
TARGET_BOOTLOADER_BOARD_NAME := pineapple
TARGET_NO_BOOTLOADER := true
TARGET_USES_UEFI := true
QCOM_BOARD_PLATFORMS += pineapple
# Adreno 735 (gen7_11_0) [LOS] proprietary-files: gen71100_*.fw
TARGET_BOARD_PLATFORM_GPU := qcom-adreno735
TARGET_USES_VULKAN := true

# Assert [LOS][TW]
TARGET_OTA_ASSERT_DEVICE := OP6131L1,lexus,CPH2709,CPH2707

# Kernel [TW][LOS]
# The recovery partition carries only a ramdisk; ABL boots it with the kernel from
# boot_[ab]. That keeps vendor_dlkm modules matched to whatever kernel is installed.
BOARD_BOOT_HEADER_VERSION := 4
BOARD_KERNEL_PAGESIZE := 4096
BOARD_KERNEL_IMAGE_NAME := Image
BOARD_MKBOOTIMG_ARGS += --header_version $(BOARD_BOOT_HEADER_VERSION)
BOARD_MKBOOTIMG_ARGS += --pagesize $(BOARD_KERNEL_PAGESIZE)
BOARD_RAMDISK_USE_LZ4 := true
BOARD_EXCLUDE_KERNEL_FROM_RECOVERY_IMAGE := true
TARGET_PREBUILT_KERNEL := $(DEVICE_PATH)/prebuilt/kernel

# A/B [LOS] BoardConfigCommon AB_OTA_PARTITIONS
AB_OTA_UPDATER := true
AB_OTA_PARTITIONS += \
    boot \
    dtbo \
    init_boot \
    odm \
    product \
    recovery \
    system \
    system_dlkm \
    system_ext \
    vbmeta \
    vbmeta_system \
    vbmeta_vendor \
    vendor \
    vendor_boot \
    vendor_dlkm

# Partition sizes [LOS] BoardConfigCommon (TW agrees on all fixed partitions)
BOARD_FLASH_BLOCK_SIZE := 262144 # (BOARD_KERNEL_PAGESIZE * 64)
BOARD_BOOTIMAGE_PARTITION_SIZE := 201326592
BOARD_DTBOIMG_PARTITION_SIZE := 25165824
BOARD_INIT_BOOT_IMAGE_PARTITION_SIZE := 8388608
BOARD_RECOVERYIMAGE_PARTITION_SIZE := 104857600
BOARD_VENDOR_BOOTIMAGE_PARTITION_SIZE := 201326592

# Dynamic partitions. Confirmed by `fastboot getvar` on CPH2709: super is
# 13883146240 ([LOS] was right, [TW]'s 9126805504 was copied from peridot).
# Every fixed partition size above matched too.
BOARD_SUPER_PARTITION_SIZE := 13883146240
BOARD_SUPER_PARTITION_GROUPS := qti_dynamic_partitions
BOARD_QTI_DYNAMIC_PARTITIONS_SIZE := 13878951936 # BOARD_SUPER_PARTITION_SIZE - 4MiB
BOARD_QTI_DYNAMIC_PARTITIONS_PARTITION_LIST := system system_ext product vendor vendor_dlkm system_dlkm odm

BOARD_PROPERTY_OVERRIDES_SPLIT_ENABLED := true
TARGET_COPY_OUT_ODM := odm
TARGET_COPY_OUT_PRODUCT := product
TARGET_COPY_OUT_SYSTEM_DLKM := system_dlkm
TARGET_COPY_OUT_SYSTEM_EXT := system_ext
TARGET_COPY_OUT_VENDOR := vendor
TARGET_COPY_OUT_VENDOR_DLKM := vendor_dlkm
BOARD_USES_VENDOR_DLKMIMAGE := true
# Required for every TARGET_COPY_OUT_* above. All of them are erofs on CPH2709
# OxygenOS 16 (measured via `mount`, including the my_* partitions).
BOARD_SYSTEMIMAGE_FILE_SYSTEM_TYPE := erofs
BOARD_SYSTEM_EXTIMAGE_FILE_SYSTEM_TYPE := erofs
BOARD_PRODUCTIMAGE_FILE_SYSTEM_TYPE := erofs
BOARD_VENDORIMAGE_FILE_SYSTEM_TYPE := erofs
BOARD_ODMIMAGE_FILE_SYSTEM_TYPE := erofs
BOARD_VENDOR_DLKMIMAGE_FILE_SYSTEM_TYPE := erofs
BOARD_SYSTEM_DLKMIMAGE_FILE_SYSTEM_TYPE := erofs

# Filesystems [LOS]
BOARD_USERDATAIMAGE_FILE_SYSTEM_TYPE := f2fs
TARGET_USERIMAGES_USE_EXT4 := true
TARGET_USERIMAGES_USE_F2FS := true
TARGET_USES_MKE2FS := true
BOARD_HAS_LARGE_FILESYSTEM := true

# Recovery
TARGET_RECOVERY_FSTAB := $(DEVICE_PATH)/recovery.fstab
TARGET_RECOVERY_PIXEL_FORMAT := RGBX_8888
TARGET_RECOVERY_QCOM_RTC_FIX := true
RECOVERY_SDCARD_ON_DATA := true

# AVB [TW]
BOARD_AVB_ENABLE := true
BOARD_AVB_RECOVERY_KEY_PATH := external/avb/test/data/testkey_rsa4096.pem
BOARD_AVB_RECOVERY_ALGORITHM := SHA256_RSA4096
BOARD_AVB_RECOVERY_ROLLBACK_INDEX := 1
BOARD_AVB_RECOVERY_ROLLBACK_INDEX_LOCATION := 1

# Encryption: FBEv2 + metadata, wrapped keys [LOS] fstab.qcom
BOARD_USES_METADATA_PARTITION := true
BOARD_USES_QCOM_FBE_DECRYPTION := true
AERA_INCLUDE_CRYPTO := true
AERA_INCLUDE_CRYPTO_FBE := true
AERA_INCLUDE_FBE_METADATA_DECRYPT := true
AERA_USE_FSCRYPT_POLICY := 2
PLATFORM_VERSION := 99.87.36
PLATFORM_VERSION_LAST_STABLE := $(PLATFORM_VERSION)
PLATFORM_SECURITY_PATCH := 2099-12-31
VENDOR_SECURITY_PATCH := $(PLATFORM_SECURITY_PATCH)
BOOT_SECURITY_PATCH := $(PLATFORM_SECURITY_PATCH)

# Props
TARGET_SYSTEM_PROP += $(DEVICE_PATH)/system.prop
TARGET_VENDOR_PROP += $(DEVICE_PATH)/vendor.prop

# Display: 1272x2800, panel modes 60/90/120/144 Hz (dumpsys display on CPH2709)
AERA_THEME := portrait_hdpi
AERA_FRAMERATE := 120
AERA_DRM_FIXED_REFRESH_RATE := 120
AERA_DEVICE_VERSION := Nord_5
AERA_BRIGHTNESS_PATH := "/sys/devices/platform/soc/ae00000.qcom,mdss_mdp/backlight/panel0-backlight/brightness" # [TW]
# Brightness from the panel node in stock dtbo (16.0.5.1301 EX01): sysfs scale
# qcom,mdss-brightness-max-level = 0xfff (4095); oplus normal (non-HBM) max
# 0xdbb (3515); oplus default 0x666 (1638). Capped at the normal max so recovery
# never drives the OLED into high-brightness mode without the system's thermal
# control. Must be a number: vendor/twrp's twrp_defaults emits
# -DTW_MAX_BRIGHTNESS=%s even when unset, and minuitwrp then fails to compile.
AERA_MAX_BRIGHTNESS := 3515
AERA_DEFAULT_BRIGHTNESS := 1638
AERA_NO_SCREEN_BLANK := true
AERA_SCREEN_BLANK_ON_BOOT := true
AERA_INPUT_BLACKLIST := "hbtp_vm"

# Status bar. [TW] used thermal_zone45, which is "shell_front" (skin temp) on
# CPH2709. zone3 is "cpuss-0" (tsens, registered early so the index should hold
# in recovery). VERIFY: 04-test-image.sh dumps zone types from recovery.
AERA_CUSTOM_CPU_TEMP_PATH := "/sys/class/thermal/thermal_zone3/temp"
AERA_QCOM_ATS_OFFSET := 1666528204500

# Kernel modules: [TW] base set, corrected against /proc/modules on CPH2709
# OxygenOS 16.0.5.1301 (EX01). Touch on 24881 is the "touchpanel" device on the
# HBP stack (oplus_hbp_core + hbp_syna_s3910 + synaptics_tcm2). Dropped from [TW]:
# qcom_esoc.ko and oplus_bsp_tp_tcm_oncell.ko (not shipped on this firmware).
# Panel-vendor alternates stay listed; modules that don't match just fail to probe.
AERA_LOAD_VENDOR_MODULES := "adsp_loader_dlkm.ko rproc_qcom_common.ko q6_dlkm.ko qcom_q6v5.ko qcom_q6v5_pas.ko qcom_sysmon.ko qcom-hv-haptics.ko haptic_feedback.ko oplus_chg_v2.ko oplus_bsp_tp_custom.ko oplus_bsp_tp_common.ko oplus_bsp_tp_notify.ko oplus_hbp_core.ko oplus_bsp_synaptics_tcm2.ko oplus_bsp_tp_syna_common.ko oplus_bsp_tp_hbp_syna_s3910.ko oplus_bsp_tp_tcm_S3910.ko oplus_bsp_tp_tcm_S3908.ko goodix_ts.ko oplus_bsp_tp_hbp_goodix_gt99x6.ko oplus_bsp_tp_gt9966.ko oplus_bsp_tp_gt9916.ko oplus_bsp_tp_novatek_common.ko oplus_bsp_tp_nt36532_noflash.ko msm_kgsl.ko"
AERA_LOAD_VENDOR_MODULES_EXCLUDE_GKI := true
# After decryption: the audio chain (AERA waffle's list, every module verified
# present in lexus vendor_dlkm) and Wi-Fi (qca6750 on WPSS via icnss2; waffle's
# kiwi_v2 PCIe driver swapped out). rfkill is built into the lexus kernel.
AERA_POST_DECRYPT_MODULES := "icnss2.ko cnss_prealloc.ko cnss_nl.ko wlan_firmware_service.ko cnss_plat_ipc_qmi_svc.ko cnss_utils.ko cnss2.ko cfg80211.ko gsim.ko rmnet_mem.ko ipam.ko qca_cld3_qca6750.ko q6_pdr_dlkm.ko q6_notifier_dlkm.ko snd_event_dlkm.ko gpr_dlkm.ko spf_core_dlkm.ko audpkt_ion_dlkm.ko audio_pkt_dlkm.ko q6_dlkm.ko audio_prm_dlkm.ko pinctrl_lpi_dlkm.ko swr_dlkm.ko swr_ctrl_dlkm.ko slimbus.ko wcd_core_dlkm.ko mbhc_dlkm.ko sdca_registers_dlkm.ko wcd9xxx_dlkm.ko stub_dlkm.ko lpass_cdc_dlkm.ko lpass_cdc_wsa2_macro_dlkm.ko lpass_cdc_wsa_macro_dlkm.ko lpass_cdc_va_macro_dlkm.ko lpass_cdc_rx_macro_dlkm.ko lpass_cdc_tx_macro_dlkm.ko wsa884x_dlkm.ko wsa883x_dlkm.ko wcd937x_dlkm.ko wcd937x_slave_dlkm.ko wcd938x_dlkm.ko wcd938x_slave_dlkm.ko wcd9378_dlkm.ko wcd9378_slave_dlkm.ko wcd939x_dlkm.ko wcd939x_slave_dlkm.ko swr_dmic_dlkm.ko oplus_audio_extend.ko swr_haptics_dlkm.ko oplus_audio_tfa98xx_v6.ko oplus_audio_sipa.ko oplus_audio_sipa_tuning.ko oplus_audio_aw882xx.ko msm_ext_display.ko hdmi_dlkm.ko btpower.ko bt_fm_slim.ko machine_dlkm.ko frpc-adsprpc.ko"

# Haptics [TW]
AERA_SUPPORT_INPUT_AIDL_HAPTICS := true

# Prop overrides [TW]
AERA_OVERRIDE_SYSTEM_PROPS := \
    "ro.build.product;ro.build.fingerprint=ro.vendor.build.fingerprint;ro.build.version.incremental"
AERA_OVERRIDE_PROPS_ADDITIONAL_PARTITIONS := vendor

# Tools
AERA_EXCLUDE_APEX := true
AERA_EXCLUDE_DEFAULT_USB_INIT := true
AERA_EXTRA_LANGUAGES := true
AERA_DEFAULT_LANGUAGE := en
AERA_USE_SERIALNO_PROPERTY_FOR_DEVICE_ID := true
AERA_INCLUDE_RESETPROP := true
AERA_INCLUDE_LIBRESETPROP := true
AERA_INCLUDE_REPACKTOOLS := true
AERA_INCLUDE_LPDUMP := true
AERA_INCLUDE_LPTOOLS := true
AERA_INCLUDE_FASTBOOTD := true
AERA_USE_TOOLBOX := true
AERA_INCLUDE_NTFS_3G := true
AERA_INCLUDE_FUSE_EXFAT := true
AERA_INCLUDE_FUSE_NTFS := true
AERA_INCLUDE_7ZA := true
AERA_INCLUDE_ZSTD := true
AERA_ENABLE_FS_COMPRESSION := true

# Debug: keep these until bring-up is done
TARGET_USES_LOGD := true
AERA_INCLUDE_LOGCAT := true
TARGET_RECOVERY_DEVICE_MODULES += debuggerd strace aera-gpu-probe
RECOVERY_BINARY_SOURCE_FILES += \
    $(TARGET_OUT_EXECUTABLES)/debuggerd \
    $(TARGET_OUT_EXECUTABLES)/strace \
    $(TARGET_OUT_EXECUTABLES)/aera-gpu-probe

# System libraries the ramdisk needs built in. [TW] set for display/debug, plus
# libjsoncpp (ssgtzd, vibrator) and common-V2-ndk (qseecom AIDL) for the A16 stack
TARGET_RECOVERY_DEVICE_MODULES += \
    android.hidl.allocator@1.0 \
    android.hidl.memory@1.0 \
    android.hidl.memory.token@1.0 \
    libdmabufheap \
    libhidlmemory \
    libion \
    libnetutils \
    vendor.display.config@1.0 \
    vendor.display.config@2.0 \
    libdebuggerd_client \
    libjsoncpp \
    android.hardware.common-V2-ndk
RECOVERY_LIBRARY_SOURCE_FILES += \
    $(TARGET_OUT_SHARED_LIBRARIES)/libjsoncpp.so \
    $(TARGET_OUT_SHARED_LIBRARIES)/android.hardware.common-V2-ndk.so \
    $(TARGET_OUT_SHARED_LIBRARIES)/android.hidl.allocator@1.0.so \
    $(TARGET_OUT_SHARED_LIBRARIES)/android.hidl.memory@1.0.so \
    $(TARGET_OUT_SHARED_LIBRARIES)/android.hidl.memory.token@1.0.so \
    $(TARGET_OUT_SHARED_LIBRARIES)/libdmabufheap.so \
    $(TARGET_OUT_SHARED_LIBRARIES)/libhidlmemory.so \
    $(TARGET_OUT_SHARED_LIBRARIES)/libion.so \
    $(TARGET_OUT_SHARED_LIBRARIES)/libnetutils.so \
    $(TARGET_OUT_SHARED_LIBRARIES)/libdebuggerd_client.so \
    $(TARGET_OUT_SYSTEM_EXT_SHARED_LIBRARIES)/vendor.display.config@1.0.so \
    $(TARGET_OUT_SYSTEM_EXT_SHARED_LIBRARIES)/vendor.display.config@2.0.so
