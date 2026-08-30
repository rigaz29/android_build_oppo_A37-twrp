#
# BoardConfig TWRP untuk OPPO A37f, basis twrp-12.1.
#
# Diturunkan dari device tree A37f basis android-9.0 (rigaz29/android_device_
# oppo_A37f@3e0b507) dengan struktur 12.1 dari rujukan acroreiser
# (android_device_lenovo_a6010, branch twrp-12.1) -- perangkat msm8916/kernel
# 3.10 yang sudah terbukti mendekripsi FBE dari recovery.
#
# Alasan pindah dari 9.0 ke 12.1, keduanya terverifikasi dari sumber:
#
#   1. vold TeamWin android-12.1 sudah memakai format kunci modern.
#      system/vold/KeyStorage.cpp:74 memuat komentar yang IDENTIK dengan
#      Android 16 ("old key directories may contain a file named 'stretching'")
#      dan :438 memakai appId = secdiscardable_hash + auth.secret yang juga
#      identik. TWRP 9.0 masih menuntut berkas "stretching" yang vold Android 16
#      tidak pernah tulis, sehingga butuh tambalan (diarsipkan di repo rencana,
#      patches-twrp9/).
#
#   2. Layout /system/bin di ramdisk 12.1 menghilangkan masalah interpreter ELF.
#      Di 9.0 biner HAL meminta /system/bin/linker sementara ramdisk hanya punya
#      /sbin/linker, sehingga execve gagal dengan ENOENT yang menyesatkan.
#

FORCE_32_BIT := true
DEVICE_PATH := device/oppo/A37f

# Platform
TARGET_BOARD_PLATFORM := msm8916
TARGET_BOARD_PLATFORM_GPU := qcom-adreno306
TARGET_BOOTLOADER_BOARD_NAME := MSM8916
TARGET_NO_BOOTLOADER := true

# Arsitektur -- kernel arm64, userspace 32-bit
TARGET_BOARD_SUFFIX := _32
TARGET_ARCH := arm
TARGET_ARCH_VARIANT := armv8-a
TARGET_CPU_ABI := armeabi-v7a
TARGET_CPU_ABI2 := armeabi
TARGET_CPU_VARIANT := cortex-a53

PRODUCT_ENFORCE_VINTF_MANIFEST_OVERRIDE := true
PRODUCT_VENDOR_MOVE_ENABLED := true
TARGET_COPY_OUT_VENDOR := vendor
TARGET_USES_64_BIT_BINDER := true

# Kernel
#
# cmdline mempertahankan parameter ramoops dari pekerjaan sebelumnya -- itu yang
# memungkinkan mendiagnosis bootloop FBE kemarin lewat console-ramoops. Tanpa
# itu "berhenti di logo lalu reboot" adalah gejala buta.
#
# BOARD_RAMDISK_OFFSET WAJIB 0x02000000 di sini, BUKAN 0x01000000 seperti LOS.
# Kernel kita jauh lebih besar dari kernel stock; dengan offset 0x01000000
# ramdisk tumpang tindih dengan kernel dan isinya rusak. Ubah keduanya atau
# tidak sama sekali.
BOARD_KERNEL_BASE := 0x80000000
BOARD_KERNEL_CMDLINE := console=ttyHSL0,115200,n8 androidboot.console=ttyHSL0 androidboot.hardware=qcom ehci-hcd.park=3 androidboot.bootdevice=7824900.sdhci lpm_levels.sleep_disabled=1 androidboot.selinux=permissive ramoops.mem_address=0x9ff00000 ramoops.mem_size=0x400000 ramoops.record_size=0x40000 ramoops.console_size=0x100000 ramoops.pmsg_size=0x40000 ramoops.dump_oops=1 ramoops.ecc=1
BOARD_KERNEL_PAGESIZE := 2048
BOARD_KERNEL_TAGS_OFFSET := 0x00000100
BOARD_RAMDISK_OFFSET := 0x02000000
BOARD_KERNEL_IMAGE_NAME := Image

# Kernel dari build LineageOS 23.2 (kernel_oppo_msm8939@d055d768d26), memuat
# CONFIG_FS_ENCRYPTION, CONFIG_F2FS_FS_ENCRYPTION, dan CONFIG_KEYS_COMPAT.
# Yang terakhir itu WAJIB dan tidak ada di kernel 3.10 hulu untuk arm64: tanpanya
# security/keys/compat.o tidak dibangun, compat_sys_keyctl tidak ada, dan setiap
# keyctl() dari userspace 32-bit mengembalikan ENOSYS -- sistem bootloop saat FBE
# aktif. Rujukan a6010 tidak bisa mengajarkan ini; kernel mereka arm 32-bit murni
# sehingga lapisan compat tidak pernah terlibat.
#
# Berbeda dari a6010 yang memakai zImage-dtb (DTB ditempel), kernel kita memakai
# Image terpisah dengan dt.img lewat --dt.
TARGET_PREBUILT_KERNEL := $(DEVICE_PATH)/prebuilt/Image
BOARD_MKBOOTIMG_ARGS += --ramdisk_offset $(BOARD_RAMDISK_OFFSET) --tags_offset $(BOARD_KERNEL_TAGS_OFFSET) --dt $(DEVICE_PATH)/prebuilt/dt.img

# LZMA, BUKAN XZ. Rujukan a6010 memakai XZ, tapi kernel MEREKA punya
# CONFIG_RD_XZ + XZ_DEC + XZ_DEC_ARM; kernel A37 hanya punya CONFIG_RD_BZIP2 dan
# CONFIG_RD_LZMA (lineageos_a37f_defconfig:27-28).
#
# Menyalin XZ dari rujukan membuat kernel PANIC saat memuat ramdisk, sebelum
# userspace sama sekali. Terbaca dari dmesg-ramoops boot yang gagal:
#
#   Process swapper/4 (Pid: 1)
#   Call trace:
#     [<(null)>] (null)
#     [<...>] initrd_load+0x0/0x2d4
#     [<...>] prepare_namespace+0xdc
#     [<...>] kernel_init_freeable
#   Code: (bad PC value)
#
# LZMA adalah yang dipakai device tree basis 9.0 dan terbukti boot di perangkat
# ini. Alternatifnya menambahkan CONFIG_RD_XZ ke kernel, tapi itu menuntut
# membangun ulang kernel dan mem-flash boot.img -- perubahan yang jauh lebih
# luas untuk masalah yang selesai dengan satu baris di sini.
BOARD_RAMDISK_USE_LZMA := true

# Filesystem
BOARD_FLASH_BLOCK_SIZE := 131072
BOARD_BOOTIMAGE_PARTITION_SIZE := 33554432
BOARD_CACHEIMAGE_PARTITION_SIZE := 126877696
BOARD_CACHEIMAGE_FILE_SYSTEM_TYPE := ext4
BOARD_PERSISTIMAGE_PARTITION_SIZE := 33554432
BOARD_RECOVERYIMAGE_PARTITION_SIZE := 33554432
BOARD_SYSTEMIMAGE_PARTITION_SIZE := 2859466752
BOARD_USERDATAIMAGE_PARTITION_SIZE := 11632902144
TARGET_USERIMAGES_USE_EXT4 := true
# f2fs wajib: /data kini f2fs, dan tanpa flag ini mkfs.f2fs/fsck.f2fs tidak ikut
# dibangun sehingga TWRP tidak bisa memformatnya.
TARGET_USERIMAGES_USE_F2FS := true
TARGET_USES_MKE2FS := true
# NTFS dimatikan demi ruang. Ini disalin dari rujukan a6010 dan TIDAK ada di
# device tree A37f basis 9.0, jadi bukan sesuatu yang perangkat ini pernah
# punya. Partisi tetap muat tanpa ini.
TW_INCLUDE_FUSE_NTFS := false

# Recovery
# Di layout 12.1 /etc adalah SYMLINK ke /system/etc. Menaruh direktori
# recovery/root/etc/ membuat build gagal dengan "could not make way for new
# symlink: root/etc". Berkasnya diletakkan di system/etc dan tetap terlihat di
# /etc lewat symlink itu.
TARGET_RECOVERY_FSTAB := $(DEVICE_PATH)/recovery/root/system/etc/recovery.fstab
TARGET_RECOVERY_PIXEL_FORMAT := "RGBA_8888"
TARGET_RECOVERY_QCOM_RTC_FIX := true

# TWRP
BOARD_HAS_REMOVABLE_STORAGE := true
BOARD_HAS_NO_SELECT_BUTTON := true
BOARD_SUPPRESS_SECURE_ERASE := true
RECOVERY_SDCARD_ON_DATA := true
TW_THEME := portrait_hdpi
TW_MAX_BRIGHTNESS := 100
TW_DEFAULT_BRIGHTNESS := "70"
TW_BRIGHTNESS_PATH := "/sys/class/leds/lcd-backlight/brightness"
# Bahasa tambahan dimatikan demi ruang: twres/languages berisi 23 berkas,
# 1,2 MB tak terkompresi. Dengan LZMA (wajib, kernel tidak punya RD_XZ) image
# melewati batas partisi 33.554.432 B sebesar 485.376 B. Ini pangkasan paling
# besar yang murni kosmetik.
TW_EXTRA_LANGUAGES := false
# Berkas bahasanya bernama en.xml, BUKAN en-US.xml. Menyetel "en-US"
# membuat pages.cpp:1325 mencari /twres/languages/en-US.xml yang tidak ada,
# menghasilkan dua error di log (fallback ke en.xml di pages.cpp:1361
# menyelamatkan tampilan, jadi dampaknya kosmetik). Default bawaan TWRP
# memang sudah "en" (Android.mk:427), jadi nilai ini disetel eksplisit ke en.
# Catatan: a6010 memakai "en-US" dan mengalami error yang sama.
TW_DEFAULT_LANGUAGE := en
TW_NO_SCREEN_TIMEOUT := true
TW_NO_EXFAT := false
TW_NO_USB_STORAGE := false
TW_USE_TOOLBOX := true
# TW_IGNORE_ABS_MT_TRACKING_ID SENGAJA TIDAK DISETEL.
# synaptics-s3203 adalah multitouch tipe B: report/input-devices.txt mencatat
# ABS=2658000 0, yang setelah didekode (word tinggi ditulis lebih dulu) berarti
# bit 47 ABS_MT_SLOT, 48 TOUCH_MAJOR, 50 WIDTH_MAJOR, 53 POSITION_X,
# 54 POSITION_Y, dan 57 ABS_MT_TRACKING_ID. Tipe B menandai jari diangkat
# lewat TRACKING_ID = -1.
#
# Dengan flag itu menyala, minuitwrp/events.cpp:617 melakukan `return 1` di
# case ABS_MT_TRACKING_ID sebelum sempat mencapai blok `if (ev->value < 0)`
# yang menyetel touchReleaseOnNextSynReport. Akibatnya pelepasan sentuhan tidak
# pernah terdaftar: layar tampak menekan sendiri dan sentuhan asli sulit masuk.
# lis3dh-accel diblokir bersama hbtp_vm. Keduanya TERBUKTI ada di A37 --
# report/input-devices.txt mencatat sembilan perangkat input: synaptics-s3203,
# synaptics-s3203-kpd, hbtp_vm, compass, lis3dh-accel, light, proximity,
# qpnp_pon, gpio-keys. Default TWRP hanya memblokir bma250/bma150
# (minuitwrp/events.cpp:243) sehingga tidak menolong di sini.
#
# Pemisahnya "\n", BUKAN "\x0a" seperti yang disarankan komentar TWRP
# (events.cpp:242). Basis 12.1 mengekspor nilai ini ke out/soong/soong.variables
# sebagai JSON, dan "\x" bukan escape JSON yang sah -- soong gagal dengan
# "invalid character 'x' in string escape code" sebelum build dimulai.
# "\n" sah di JSON MAUPUN di string literal C, dan strtok(bl, "\n")
# (events.cpp:250) memang memisah pada newline.
#
# WHITELIST_INPUT bukan alternatif: ia hanya menerima SATU nama perangkat
# (events.cpp:236), sehingga tombol fisik ikut diabaikan.
# compass, light, dan proximity ikut diblokir. events.cpp:241-259 hanya
# mencocokkan NAMA perangkat -- tidak ada penyaringan berdasar kemampuan --
# sehingga setiap perangkat yang tidak diblokir ikut dibaca sebagai masukan.
# compass (event3) melaporkan ABS=7 yaitu ABS_X, ABS_Y, ABS_Z, dan
# events.cpp:510 menerjemahkan ABS_X langsung menjadi koordinat penunjuk
# (e->p.x = ev->value). Magnetometer yang mengalir terus itu menyuntikkan
# koordinat palsu. light dan proximity hanya ABS_MISC/ABS_DISTANCE, tapi
# tidak ada gunanya dibaca.
# Yang TETAP dibaca: synaptics-s3203 (sentuh), synaptics-s3203-kpd,
# qpnp_pon (tombol daya), gpio-keys (tombol volume).
# Pemisah KOMA, bukan "\n" apalagi "\x0a". Rinciannya ada di tambalan
# minuitwrp/events.cpp: pada basis soong 12.1, "\x0a" ditolak parser JSON
# soong.variables, sedangkan "\n" diterjemahkan jadi newline sungguhan yang
# kemudian dilipat preprocessor sehingga seluruh nama berdempet jadi satu
# kata. Koma lolos keduanya tanpa berubah.
TW_INPUT_BLACKLIST := "hbtp_vm,lis3dh-accel,compass,light,proximity"

# Logging -- dibutuhkan untuk mendiagnosis kegagalan dekripsi
TARGET_USES_LOGD := true
TWRP_INCLUDE_LOGCAT := true
TWRP_EVENT_LOGGING := true

# MTP AKTIF, lewat jalur /dev/mtp_usb (MtpDevHandle), bukan FunctionFS.
#
# MtpServer.cpp:122 memilih otomatis: kalau /dev/usb-ffs/mtp/ep0 bisa ditulis
# ia memakai MtpFfsHandle, kalau tidak memakai MtpDevHandle. init.rc TWRP
# hanya me-mount instance functionfs "adb" dan "fastboot" (etc/init.rc:149-153),
# jadi jalur MtpDevHandle yang terpilih -- dan itu memang yang cocok untuk
# kernel ini, yang menyediakan f_mtp di /dev/mtp_usb.
#
# JANGAN me-mount /dev/usb-ffs/mtp. Gadget android kernel ini hanya punya SATU
# struct functionfs_config dengan satu 'struct ffs_data *data'
# (drivers/usb/gadget/android.c), dan functionfs_ready_callback() menimpanya
# tanpa syarat. Instance FFS yang menulis deskriptor terakhir menendang yang
# sebelumnya keluar dari gadget -- itulah yang dulu mematikan adb.
#
# Kegagalan "Failed to start usb driver!" sebelumnya bukan soal MTP-nya, tapi
# bug open ganda di MtpDevHandle::start(); lihat tambalan
# patches-twrp121/0003.
TW_EXCLUDE_APEX := true

BOARD_ALWAYS_INSECURE := true

# FBE
#
# TW_USE_FSCRYPT_POLICY := 1 WAJIB. Kernel A37 hanya punya kebijakan fscrypt v1
# -- fs/crypto/ tidak memuat keyring.c maupun hkdf.c, jadi
# FS_IOC_ADD_ENCRYPTION_KEY tidak ada dan hanya FS_IOC_SET_ENCRYPTION_POLICY
# yang tersedia. Nilai ini cocok dengan fstab ROM yang memakai
# fileencryption=aes-256-xts:aes-256-cts:v1.
#
# TW_FORCE_KEYMASTER_VER dipasangkan dengan properti keymaster_ver=4.1 di
# omni_A37f.mk. Keymaster di A37 murni software ("Could not find any keystore
# module, using software-only implementation" -- keystore.msm8916.so memang tidak
# pernah diekstrak ke vendor blob kita), jadi recovery menjalankan servis
# keymaster software sendiri, bukan HAL vendor.
TW_INCLUDE_CRYPTO := true
TW_INCLUDE_CRYPTO_FBE := true
TW_USE_FSCRYPT_POLICY := 1
TW_FORCE_KEYMASTER_VER := true

TARGET_OTA_ASSERT_DEVICE := a37f,A37f,A37fw,a37fw,msm8916,msm8939

PLATFORM_VERSION             := 99.87.36
PLATFORM_VERSION_LAST_STABLE := $(PLATFORM_VERSION)
PLATFORM_SECURITY_PATCH      := 2099-12-31
VENDOR_SECURITY_PATCH        := $(PLATFORM_SECURITY_PATCH)
BOOT_SECURITY_PATCH          := $(PLATFORM_SECURITY_PATCH)
