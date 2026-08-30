PRODUCT_RELEASE_NAME := A37f

# Basis 12.1 memakai aosp_base_telephony + vendor/twrp, BUKAN full_base_telephony
# + vendor/omni seperti basis 9.0. Manifest twrp-12.1 adalah varian AOSP
# (platform_manifest_twrp_aosp); varian omni tidak punya branch 12.1.
$(call inherit-product, $(SRC_TARGET_DIR)/product/aosp_base_telephony.mk)
$(call inherit-product, vendor/twrp/config/common.mk)
$(call inherit-product, $(SRC_TARGET_DIR)/product/languages_full.mk)
$(call inherit-product, device/oppo/A37f/device.mk)

PRODUCT_PACKAGES += \
    charger_res_images \
    charger

# Dipasangkan dengan TW_FORCE_KEYMASTER_VER di BoardConfig. Recovery menjalankan
# servis keymaster 4.1 software sendiri; A37 tidak punya keymaster hardware
# (keystore.msm8916.so tidak pernah diekstrak ke vendor blob, sehingga
# hw_get_module("keystore") gagal dan implementasinya jatuh ke software).
PRODUCT_PROPERTY_OVERRIDES += \
    keymaster_ver=4.1

# Warisan dari basis 9.0: adb USB pada kernel 3.10 butuh jalur FunctionFS lama.
PRODUCT_PROPERTY_OVERRIDES += \
    sys.usb.ffs.aio_compat=1

PRODUCT_VENDOR_PROPERTIES += \
    ro.logd.kernel=false

ifneq ($(wildcard bionic/libc/zoneinfo),)
    TZDATAPATH := bionic/libc/zoneinfo
else ifneq ($(wildcard system/timezone),)
    TZDATAPATH := system/timezone/output_data/iana
endif
ifdef TZDATAPATH
PRODUCT_COPY_FILES += \
    $(TZDATAPATH)/tzdata:recovery/root/system/usr/share/zoneinfo/tzdata
endif

PRODUCT_DEVICE := A37f
PRODUCT_NAME := omni_A37f
PRODUCT_BRAND := Oppo
PRODUCT_MODEL := A37f
PRODUCT_MANUFACTURER := Oppo

ALLOW_MISSING_DEPENDENCIES := true
