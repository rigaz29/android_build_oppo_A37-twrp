# TWRP 12.1 untuk OPPO A37f

> **14 September 2026 — varian 64-bit.** Cabang pohon perangkat
> [`twrp-12.1-64bit`](https://github.com/rigaz29/android_device_oppo_A37f/tree/twrp-12.1-64bit)
> membangun recovery dengan userspace **arm64**, dan image-nya dirilis di
> [`twrp-3.7.1_12-64bit-20260914`](https://github.com/rigaz29/android_build_oppo_A37-twrp/releases/tag/twrp-3.7.1_12-64bit-20260914).
> Alasannya di §"Kenapa 64-bit" di bawah. Cabang `twrp-12.1` (32-bit) tetap ada
> dan tetap yang terbukti mendekripsi FBE — **pertahankan image-nya sebagai
> jalan mundur** sampai varian 64-bit terbukti membuka `/data`.


Isi repo ini: pohon perangkat TWRP, tambalan terhadap `bootable/recovery`, dan
bukti perangkat.

Rencana dan catatan kerjanya ada di dua tempat: `PLAN.md` (basis 9.0, sejarah)
dan **`PLAN-FBE.md`** (basis 12.1, yang dipakai sekarang -- termasuk Fase 7 soal
adb dan MTP berdampingan).

## Susunan

```
device/oppo/A37f/           pohon perangkat, lengkap KECUALI prebuilt/
patches-twrp121/            tambalan terhadap sumber TWRP hulu
patches-twrp9/              tambalan basis 9.0 (sejarah)
local_manifest.xml          untuk repo init pohon build
report/                     log dari perangkat (dmesg, recovery.log, input, usb)
```

## Yang sengaja TIDAK ada di sini

`device/oppo/A37f/prebuilt/Image` — kernel recovery, 18 MB. Artefak build, bisa
dihasilkan ulang:

```
repo   : https://github.com/rigaz29/kernel_oppo_msm8939
branch : twrp-12.1-adiantum
config : lineageos_a37f_defconfig
salin  : arch/arm64/boot/Image -> device/oppo/A37f/prebuilt/Image
```

Branch `twrp-12.1-adiantum` = `twrp-12.1` (FunctionFS AIO, pemulihan
FFS_CLOSING) digabung dengan `adiantum` (f2fs 201 commit, cipher Adiantum,
NEON arm64, mode fscrypt).

Branch itu kini **sudah memuat** commit `b4799b06c556`
(`FS_POLICY_FLAG_DIRECT_KEY`), digabung sebagai `f43ae9632fe7`. Tanpa commit
tersebut libfscrypt akan ditolak `-EINVAL` saat membuka `/data` ber-Adiantum,
karena ia selalu menyalakan flag itu
(`system/extras/libfscrypt/fscrypt.cpp:261`).

Recovery yang dipakai sekarang dikemas ulang, bukan dibangun ulang: ramdisk
TWRP tidak berubah sejak build sebelumnya, jadi hanya bagian kernel di dalam
`recovery.img` yang ditukar. Field `id`-nya dihitung ulang dengan rumus yang
dipakai mkbootimg kita — `sha1(kernel|len, ramdisk|len, second|len)`, **tanpa
DT**; rumus lain menghasilkan id yang tidak cocok.

## Tambalan `bootable/recovery`

Arsipnya di `patches-twrp121/`, berlaku di atas `bootable/recovery`
`5c3d206a5eeb`. Rincian tiap tambalan ada di `patches-twrp121/README.md`;
`PLAN-FBE.md` merujuknya per nomor.

| Berkas | Perbaikan |
|---|---|
| `minuitwrp/events.cpp` | daftar-hitam masukan: buang tanda kutip, pisahkan dengan koma — tanpa ini sentuh liar (tekan-tekan sendiri) |
| `mtp/ffs/MtpDevHandle.cpp` | `mFd.reset()` sebelum membuka ulang, supaya MTP dan adb hidup bersamaan |
| `partitionmanager.cpp` | `Release_ADB_FFS()` |
| `etc/init.rc` | `setprop sys.usb.config mtp,adb` |
| `etc/init.recovery.usb.rc` | idProduct 4EE2/D001 |

Cara pasang:

```
cd bootable/recovery && git checkout 5c3d206a5eeb
git apply /path/ke/patches-twrp121/000[2-5]-*.patch
```

## Keadaan yang sudah terbukti di perangkat

```
UI tampil, sentuh normal (tanpa tekan liar)
adb USB dan MTP hidup BERSAMAAN
dekripsi FBE /data berjalan (AES)
```

Dan sejak 31 Agustus 2026, **dekripsi Adiantum juga terbukti**. Setelah
`/data` diformat ulang dengan `fileencryption=adiantum:adiantum:v1`, TWRP
meminta PIN dan membuka `/data`. Log recovery menunjukkan kedua kunci
terpasang, bukan hanya satu:

```
recovery: Added key ... (fscrypt:07808c2397205753) to keyring
recovery: fscrypt_prepare_user_storage  user 0, flags 1     <- DE
recovery: fscrypt_unlock_user_key 0
recovery: Added key ... (fscrypt:24f0d587075ede30) to keyring
recovery: fscrypt_prepare_user_storage  user 0, flags 2     <- CE
```

`flags 1` device-encrypted, `flags 2` credential-encrypted.

Catatan untuk yang akan memformat: pada perangkat FBE, TWRP **sengaja tidak
membuat ulang** `/data/media` (`partition.cpp:2190`). Penyimpanan internal
baru ada setelah ROM boot sekali. Itu perlindungan, bukan kekurangan — fscrypt
hanya bisa memasang kebijakan pada direktori kosong.


---

## Kenapa 64-bit (14 September 2026)

Recovery 32-bit **menolak paket GApps arm64**. Installer MindTheGapps membaca
`getprop ro.bionic.arch` dari lingkungan **recovery**, bukan dari ROM, lalu
membandingkannya dengan arsitektur paket:

```sh
GAPPS_ARCH=$(getprop2 $TMP/build.prop arch)   # arm64
CPU_ARCH=$(getprop ro.bionic.arch)            # arm  <- dari recovery
if [ $GAPPS_ARCH != $CPU_ARCH ]; then
  error "This package is built for $GAPPS_ARCH but your device is $CPU_ARCH! Aborting"
fi
```

Properti itu datang langsung dari build system:
`build/make/core/main.mk` menyetel `ro.bionic.arch=$(TARGET_ARCH)`. Jadi selama
`TARGET_ARCH := arm`, recovery ini akan selalu melaporkan `arm` walau ROM yang
terpasang arm64. `setprop` tidak bisa menimpanya (properti `ro.`).

Kernelnya sendiri sudah sanggup, dan itu diuji lebih dulu: `toybox` aarch64
bawaan paket GApps dijalankan di recovery 32-bit dan berhasil.

### Yang berubah di cabang 64-bit

| | |
|---|---|
| `TARGET_ARCH` | `arm` → `arm64`, `TARGET_CPU_ABI` → `arm64-v8a`, suffix `_32` → `_64` |
| `TARGET_SUPPORTS_64_BIT_APPS := false` | wajib; `board_config.mk:244-249` menolak build tanpanya |
| arch kedua | **tidak ada**. Ramdisk recovery hanya memuat pustaka arch utama, jadi arch kedua tak akan punya runtime |
| keymaster + gatekeeper | dibangun ulang dari sumber sebagai arm64 — keduanya implementasi **software AOSP**, bukan blob vendor |
| `system/lib` 32-bit | dihapus; `libkeymaster4`, `libkeymaster41`, `libresetprop` kini di `system/lib64` |
| `vm_bms`, `qseecomd`, `vendor/lib/*` QSEECom | **dibuang** — blob vendor yang hanya ada 32-bit, mustahil dieksekusi. `qseecomd` toh sudah `disabled`, dan `readelf` membuktikan keymaster/gatekeeper tidak menautnya |

`CONFIG_KEYS_COMPAT` menjadi tidak relevan di varian ini: ia hanya dibutuhkan
ketika `keyctl()` dipanggil dari userspace 32-bit.

### Hasil verifikasi build

```
ro.bionic.arch = arm64
223 berkas ELF di ramdisk, SELURUHNYA 64-bit, nol 32-bit
penutupan pustaka jalur kripto lengkap (audit rekursif seluruh lib64: nol hilang)
header boot: kernel @0x80008000, ramdisk @0x82000000, pagesize 2048,
             QCDT 210.944 byte -- sama persis dengan boot.img LineageOS 20
```

### Belum diuji di perangkat

Dua hal yang wajib diperiksa setelah flash: **dekripsi FBE** (biner kripto
dibangun ulang, penutupan pustaka terverifikasi, tetapi belum terbukti
berjalan) dan **persentase baterai** tanpa `vm_bms`.

### Catatan: `local_manifest-twrp121.xml` sempat ditolak repo

Komentarnya memuat tanda hubung ganda (`12.1 -- hanya varian AOSP`), yang
terlarang di dalam komentar XML. `repo sync` berhenti dengan
`not well-formed (invalid token): line 6, column 52`. Sudah diperbaiki memakai
em dash.
