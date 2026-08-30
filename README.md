# TWRP 12.1 untuk OPPO A37f

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
