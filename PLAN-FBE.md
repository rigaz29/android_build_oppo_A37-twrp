# TWRP A37f dengan dukungan FBE — recovery dulu, baru sistem

Tujuan tunggal: **recovery yang bisa mendekripsi `/data` ber-FBE.** Ini prasyarat,
bukan pelengkap. Tanpa ini, mengaktifkan FBE di ROM berarti membuat perangkat yang
recovery-nya tidak bisa menyentuh datanya sendiri — dan satu-satunya jalan keluar
adalah wipe.

Ditulis 29 Agustus 2026. Sub-proyek dari
[`android_build_oppo_A37-22`](https://github.com/rigaz29/android_build_oppo_A37-22),
melanjutkan [`PLAN.md`](PLAN.md) (TWRP dengan kernel sendiri, sudah selesai).

---

## 0. Keputusan: tetap di `android-9.0`

Pertanyaannya 9.0 atau 12.1. Jawabannya **9.0**, dan bukan karena inersia — 12.1
justru menabrak tiga hal yang perangkat ini tidak punya.

### Apa yang dibutuhkan TWRP 12.1

```
bootable/recovery android-12.1  Android.mk:341-342
    android.frameworks.stats@1.0
    android.hardware.authsecret@1.0
    android.security.authorization-ndk_platform
bootable/recovery android-12.1  Android.mk:556-563
    keystore2  keystore_auth  vold_prepare_subdirs  fscryptpolicyget.recovery
bootable/recovery android-12.1  partitionmanager.cpp:599
    android::vold::fscrypt_mount_metadata_encrypted(...)
```

Tiga penghalang, semuanya terukur:

| Kebutuhan 12.1 | Keadaan A37 |
|---|---|
| `authsecret@1.0`, `stats@1.0` | tidak ada HAL-nya |
| keystore2 di ramdisk recovery | perangkat pakai `keymaster@3.0` (Android 8) |
| `fscrypt_mount_metadata_encrypted` | mustahil — `dm-default-key` tidak ada di kernel 3.10 kita |

Direktori `crypto/` di 12.1 hanya berisi `scrypt`. Seluruh FBE-nya dipinjam dari
`system/vold` platform Android 12.

### Apa yang dibutuhkan TWRP 9.0

```
crypto/ext4crypt/Android.mk:20     android.hardware.keymaster@3.0
crypto/ext4crypt/Decrypt.cpp:19    #include "Ext4CryptPie.h"
crypto/ext4crypt/Decrypt.cpp:165   e4crypt_initialize_global_de()
crypto/ext4crypt/KeyUtil.cpp:103   NAME_PREFIXES[] = { "ext4", "f2fs", "fscrypt" }
crypto/ext4crypt/KeyUtil.cpp:150   add_key("logon", ref, ...)
```

FBE-nya mandiri di `crypto/ext4crypt/`, dan **`keymaster@3.0` adalah HAL yang
persis dimiliki A37** — terverifikasi jalan di perangkat, PID 349.

### Yang menutup perkara

`NAME_PREFIXES` TWRP 9.0 **identik** dengan milik Android 16:

```
TWRP 9.0   crypto/ext4crypt/KeyUtil.cpp:103   { "ext4", "f2fs", "fscrypt" }
LOS 23.2   system/vold/KeyUtil.cpp:142        { "ext4", "f2fs", "fscrypt" }
```

Format nama sama (`prefix:hex`), tipe kunci sama (`logon`), keyring sama. Recovery
2018 dan sistem 2026 berbicara protokol yang sama persis — karena keduanya bicara
ke kernel v1 yang sama.

**Bonus struktural:** device tree TWRP kita memakai
`TARGET_PREBUILT_KERNEL := $(DEVICE_PATH)/prebuilt/Image` (`BoardConfig.mk:50`),
yaitu kernel yang kita bangun sendiri. Jadi **satu kernel melayani boot.img dan
recovery.img sekaligus** — mustahil terjadi ketidakcocokan config di antara
keduanya. Bandingkan dengan jebakan di rujukan a6010 di bagian 4.

---

## 1. Fakta yang sudah diverifikasi

### Kernel kita — fscrypt v1, hanya f2fs

| | |
|---|---|
| `fs/crypto/` | ada: `bio.c crypto.c fname.c keyinfo.c policy.c` — **tanpa `keyring.c`/`hkdf.c`** → v1 saja |
| ioctl | `include/uapi/linux/fs.h:198,200` hanya `FS_IOC_SET/GET_ENCRYPTION_POLICY`. Tidak ada `FS_IOC_ADD_ENCRYPTION_KEY` |
| awalan kunci | `fs.h:203` `FS_KEY_DESC_PREFIX "fscrypt:"`, deskriptor 8 byte (`fs.h:171`) |
| tipe kunci | `fs/crypto/keyinfo.c:110` `request_key(&key_type_logon, ...)` |
| urutan pencarian | `keyinfo.c:325-330` — `fscrypt:` dulu, lalu `s_cop->key_prefix` |
| f2fs tersambung | `fs/f2fs/super.c:1222` `f2fs_cryptops`, `:1223` `.key_prefix = "f2fs:"` |
| **ext4 TIDAK tersambung** | `fs/ext4/` nol rujukan: `fscrypt` 0, `ext4_encrypt` 0, `INCOMPAT_ENCRYPT` 0 |
| defconfig | `lineageos_a37f_defconfig:603,620` — `EXT4_FS` dan `F2FS_FS` menyala, sub-opsi enkripsi **tidak ada** |
| metadata encryption | mustahil — `dm-default-key` tidak ada |

### Android 16 masih mau bicara v1

| | |
|---|---|
| fstab menerima | `libfstab/fstab.cpp:289` `fileencryption=` |
| FDE ditolak keras | `fstab.cpp:243` `forceencrypt=` → `LERROR` + `return false` (fstab gagal parse) |
| versi v1 diterima | `libfscrypt/fscrypt.cpp:219` `if (flag == "v1")` |
| kebijakan v1 disusun | `fscrypt.cpp:305-325` → `fscrypt_policy_v1` |
| vold mundur otomatis | `vold/KeyUtil.cpp:91-99` — deteksi `ENOTTY`, "Falling back to session keyring" |

### Recovery LineageOS tidak bisa dipakai

`bootable/recovery` LOS 23.2: **nol** rujukan fscrypt. Yang ada hanya logika format
metadata encryption (`recovery_utils/roots.cpp:311-330`) dan flag warisan
`--set_encrypted_filesystem` (`recovery.cpp:92`). Ia bisa mount dan format `/data`,
tapi isinya sampah terenkripsi.

### Keadaan device tree TWRP sekarang

```
BoardConfig.mk:50   TARGET_PREBUILT_KERNEL := $(DEVICE_PATH)/prebuilt/Image
BoardConfig.mk:67   TW_INCLUDE_CRYPTO := true          <- FDE, sudah ada
                    TW_INCLUDE_CRYPTO_FBE              <- BELUM ADA
recovery/root/etc/twrp.fstab:9
  /dev/block/bootdevice/by-name/userdata  /data  ext4  defaults  length=-16384,encryptable=footer
```

`encryptable=footer` itu **FDE**, bukan FBE. Dan `length=-16384` menyisihkan ruang
untuk footer FDE — tidak diperlukan pada FBE.

### Biaya kinerja — sudah diukur, bukan ditebak

| | |
|---|---|
| baca `/data` (cache dingin, 1 GB) | **138 MB/s** |
| tulis `/data` (`conv=fsync`, 1 GB) | **34 MB/s** |
| AES-256 bulk (bssl, 1 utas, @1209,6 MHz) | **35 MB/s** |
| CPU punya instruksi AES? | **tidak** — `Features` tanpa `aes sha1 sha2 pmull` |
| QCE hardware akan dipakai? | **tidak** — kernel minta `xts(aes)` (`keyinfo.c:149`), QCE mendaftar sebagai `qcom-xts(aes)`. Nama beda, tidak pernah cocok |

Konsekuensinya: baca berurutan kemungkinan besar jatuh dari 138 MB/s ke kisaran
kripto. Tulis 34 MB/s nyaris tidak terpengaruh karena sudah di bawah langit-langit.

---

## 2. Rantai kunci — kenapa ini bisa jalan

```
  TWRP 9.0                              LOS 23.2
  Decrypt.cpp:165                       vold/KeyUtil.cpp
  e4crypt_initialize_global_de()        installKey()
          |                                     |
          +--- add_key("logon", "fscrypt:<hex>") ---+
                            |
                            v
              kernel fs/crypto/keyinfo.c:110
              request_key(&key_type_logon, ...)
                            |
                            v
              FS_IOC_SET_ENCRYPTION_POLICY (v1)
                            |
                            v
              f2fs_cryptops (fs/f2fs/super.c:1222)
```

Satu jalur, dua konsumen, tanpa penerjemah di tengah.

---

## 3. Urutan kerja SENGAJA dibalik

Rencana awal adalah mengaktifkan FBE di ROM lalu memperbaiki recovery. **Itu salah
urutan.** Kalau FBE menyala sementara recovery belum bisa mendekripsi, perangkat
berada dalam keadaan di mana satu-satunya operasi recovery yang berguna adalah wipe.

Urutan yang benar:

1. Kernel ber-FBE dibangun
2. TWRP dengan kernel itu + `TW_INCLUDE_CRYPTO_FBE` dibangun dan **dipasang**
3. Baru ROM ber-FBE di-flash dan `/data` diformat
4. Verifikasi TWRP masih bisa membaca `/data` setelah terenkripsi

Kalau langkah 4 gagal, langkah 3 bisa dibatalkan dengan format ulang — dan TWRP
dari langkah 2 masih berfungsi untuk melakukannya.

---

## 4. Rute enkripsi: mulai dari yang termurah

**Rute A — f2fs + AES-256-XTS v1** (dipilih untuk iterasi pertama)

- Kernel: dua baris defconfig, `CONFIG_FS_ENCRYPTION=y` + `CONFIG_F2FS_FS_ENCRYPTION=y`
- fstab LOS: baris f2fs sudah ada di `fstab.qcom:6` dan dicoba lebih dulu — tinggal
  tambah `fileencryption=aes-256-xts:aes-256-cts:v1`
- Sepenuhnya reversibel dengan format ulang

**Rute B — ext4 + Adiantum** (kalau Rute A terlalu lambat)

Ini yang dijalankan a6010 (`dt-a6010/rootdir/etc/fstab.qcom:7`
`fileencryption=adiantum`). Ukurannya nyata:

```
fs/ext4/crypto.c 537   crypto_fname.c 465   crypto_key.c 509   crypto_policy.c 236
crypto/adiantum.c 661   nhpoly1305.c 254   poly1305_generic.c 330
```

**Ganjalan yang harus diakui:** kernel a6010 `arch/arm` 32-bit, kernel kita
`arch/arm64`. Akselerasi NEON mereka (`chacha-neon-core.S`,
`nhpoly1305-neon-glue.c`) adalah assembly ARM 32-bit — tidak bisa dipakai langsung.
Versi arm64 ada di upstream 5.x, tapi API kripto kernel berubah banyak sejak 3.10
(`blkcipher`/`ablkcipher` → `skcipher`). **Tanpa NEON, Adiantum jatuh ke C generik
dan mungkin tidak lebih cepat dari AES-NEON** — keunggulan utamanya justru hilang.

Karena itu Rute B tidak dikerjakan sebelum Rute A diukur.

### Jebakan dari rujukan yang harus dihindari

acroreiser menyimpan tiga defconfig, dan salah satunya tidak konsisten:

```
lineageos_a6010_defconfig   EXT4_FS_ENCRYPTION  FS_ENCRYPTION  ADIANTUM  NHPOLY1305  CHACHA20
twrp_a6010_defconfig        EXT4_FS_ENCRYPTION  FS_ENCRYPTION  ADIANTUM  NHPOLY1305  CHACHA20
recovery_a6010_defconfig    FS_ENCRYPTION  F2FS_FS_ENCRYPTION              <- TIDAK COCOK
```

`recovery_a6010_defconfig` tidak akan bisa mendekripsi `/data` ext4+Adiantum milik
mereka sendiri. Kita terhindar dari ini secara struktural karena TWRP kita memakai
kernel yang sama dengan boot (`BoardConfig.mk:50`) — bukan karena kita lebih teliti.

---

## 5. Fase

### Fase 0 — Kernel ber-FBE
- Tambah `CONFIG_FS_ENCRYPTION=y` dan `CONFIG_F2FS_FS_ENCRYPTION=y` ke
  `lineageos_a37f_defconfig`
- Bangun; verifikasi `xts(aes)` dan `cts(cbc(aes))` muncul di `/proc/crypto`
  setelah boot
- **Belum menyentuh fstab** — kernel yang mampu enkripsi tapi tidak dipakai adalah
  no-op yang aman

### Fase 1 — TWRP dengan FBE
- `BoardConfig.mk`: tambah `TW_INCLUDE_CRYPTO_FBE := true`
- `prebuilt/Image`: ganti dengan kernel Fase 0
- `twrp.fstab:9`: `/data` → f2fs, buang `encryptable=footer` dan `length=-16384`
- Bangun `recovery.img`, verifikasi ukurannya masih < 32 MB
  (`BOARD_RECOVERYIMAGE_PARTITION_SIZE`)

### Fase 2 — Pasang TWRP, uji SEBELUM enkripsi
- Flash recovery, boot ke TWRP
- Pastikan `/data` (masih ext4 tanpa enkripsi) tetap ter-mount dan terbaca
- **Ini gerbangnya.** Kalau TWRP baru tidak bisa membaca `/data` yang belum
  terenkripsi sekalipun, berhenti di sini — jangan lanjut

### Fase 3 — Aktifkan FBE di ROM
- `fstab.qcom:6`: tambah `fileencryption=aes-256-xts:aes-256-cts:v1` ke baris f2fs
- Bangun ROM, flash, format `/data` (wipe)
- Verifikasi di `logcat`: vold mencetak "Falling back to session keyring"
  (`KeyUtil.cpp:93`) — itu tanda jalur v1 aktif

### Fase 4 — Verifikasi silang
- Boot ke TWRP, pastikan `/data` bisa didekripsi dengan PIN/sandi
- Ukur ulang throughput dengan metode yang sama persis seperti baseline
  (`dd` 1 GB, `conv=fsync` untuk tulis, `drop_caches` untuk baca) supaya angkanya
  bisa dibandingkan langsung dengan 138/34 MB/s

---

## 6. Risiko yang diakui

- **Wipe `/data` wajib.** Tidak ada jalur migrasi in-place.
- **f2fs belum pernah teruji di perangkat ini.** `fstab.qcom:6` punya baris f2fs
  yang dicoba lebih dulu, tapi `/data` perangkat adalah ext4 — artinya jalur itu
  tidak pernah benar-benar dipakai. f2fs di kernel 3.10 versi awal (21 berkas `.c`).
- **Kebijakan v1 sudah usang.** Android menyimpannya untuk perangkat lama; tidak
  ada jaminan ia bertahan di versi berikutnya.
- **Tanpa metadata encryption**, struktur direktori dan ukuran berkas tetap
  terlihat. Hanya isi dan nama berkas yang terenkripsi.
- **Baca kemungkinan besar melambat** — 138 MB/s bertemu langit-langit kripto
  35–46 MB/s. Angka pastinya baru diketahui di Fase 4.
- **TWRP 9.0 dibangun dengan basis 2018.** Sudah terbukti jalan di A37f, tapi
  makin jauh dari platform yang dienkripsinya.

---

## 7. Yang sengaja TIDAK dikerjakan

- **Migrasi ke TWRP 12.1** — tiga penghalang di bagian 0, semuanya struktural.
- **Adiantum** — sampai Rute A diukur. Masalah NEON arm64 membuatnya belum tentu
  menguntungkan.
- **Backport enkripsi ext4** — 1.747 baris, hanya perlu kalau kita memilih ext4.
- **Metadata encryption** — mustahil, `dm-default-key` tidak ada.
- **Menyentuh `PLAN.md` lama** — itu catatan pekerjaan yang sudah selesai.
