#
# Copyright (C) 2026 The Android Open Source Project
#
# SPDX-License-Identifier: Apache-2.0
#

LOCAL_PATH := device/oneplus/lexus

# API: lexus shipped Android 15 [TW XDA thread]
BOARD_SHIPPING_API_LEVEL := 35
PRODUCT_SHIPPING_API_LEVEL := 35
PRODUCT_TARGET_VNDK_VERSION := 35

# Dynamic partitions
PRODUCT_USE_DYNAMIC_PARTITIONS := true
PRODUCT_OTA_ENFORCE_VINTF_KERNEL_REQUIREMENTS := false

PRODUCT_PACKAGES += \
    lpflash \
    lpmake \
    lpunpack

# fastbootd [TW]
PRODUCT_PACKAGES += \
    fastbootd \
    android.hardware.fastboot@1.1-impl-mock

# Decryption uses the phone's own Android 16 keymint/gatekeeper/qseecom
# services (recovery/root/vendor), not twrp-common's qcom_decrypt scripts.

# f2fs tools [TW]
PRODUCT_PACKAGES += \
    sg_write_buffer \
    f2fs_io \
    check_f2fs

# OTA certs [TW]
PRODUCT_EXTRA_RECOVERY_KEYS += \
    $(LOCAL_PATH)/security/otacert

# Adreno 735 GPU acceleration (see gpu/README.md). aera-gpu-probe goes into the
# ramdisk through TARGET_RECOVERY_DEVICE_MODULES in BoardConfig.mk.
PRODUCT_VENDOR_PROPERTIES += ro.hardware.egl=adreno

# Soong namespaces
PRODUCT_SOONG_NAMESPACES += $(LOCAL_PATH)

# UFS framework for librecovery_updater [TW]
SOONG_CONFIG_NAMESPACES += ufsbsg
SOONG_CONFIG_ufsbsg += ufsframework
SOONG_CONFIG_ufsbsg_ufsframework := bsg

PRODUCT_PROPERTY_OVERRIDES += \
    persist.sys.fuse.passthrough.enable=true

# AERA recovery settings
$(call inherit-product, $(LOCAL_PATH)/aera_lexus.mk)
