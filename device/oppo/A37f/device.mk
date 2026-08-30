LOCAL_PATH := device/oppo/A37f

# Servis yang dibutuhkan TWRP untuk mendekripsi /data ber-FBE.
#
# Keduanya implementasi SOFTWARE, bukan HAL vendor. Itu disengaja: A37 tidak
# punya keymaster hardware, dan percobaan menjalankan HAL vendor 3.0 di recovery
# basis 9.0 berakhir dengan hwservicemanager SIGABRT dan proses recovery ikut
# crash-loop. Rujukan a6010 memakai pendekatan software ini dan terbukti jalan.
# Didaftarkan agar modulnya DIBANGUN. Tapi PRODUCT_PACKAGES saja TIDAK cukup:
# modulnya mendarat di out/.../vendor/bin/hw/, bukan di ramdisk recovery --
# diverifikasi dengan membongkar recovery.img hasil build pertama, keduanya
# tidak ada. Karena itu binernya juga dikirim sebagai prebuilt di
# recovery/root/system/bin/, sama seperti rujukan a6010.
PRODUCT_PACKAGES += \
    android.hardware.keymaster@4.1-service \
    android.hardware.gatekeeper@1.0-service.software
