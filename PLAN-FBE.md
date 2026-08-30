# TWRP A37f dengan dukungan FBE — recovery dulu, baru sistem

> **Status: SELESAI.** FBE berjalan di ROM (Fase 3-4, terukur), **TWRP 12.1
> berhasil mendekripsi `/data`** (Fase 6), dan **adb + MTP berjalan
> berdampingan** (Fase 7). Semua terverifikasi di perangkat.

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

### Fase 0 — Kernel ber-FBE  ✅ SELESAI (`kernel_oppo_msm8939@a5e7652c8c5`)
- [x] `CONFIG_FS_ENCRYPTION=y` + `CONFIG_F2FS_FS_ENCRYPTION=y` di
      `lineageos_a37f_defconfig`
- [x] **Penghalang tak terduga:** build pertama gagal dengan
      `fs/crypto/keyinfo.c:218: implicit declaration of function
      'SHASH_DESC_ON_STACK'`. Backport `fs/crypto/` di pohon ini disalin dari
      kernel 4.x tapi **tidak pernah sekali pun dikompilasi**, karena
      `CONFIG_FS_ENCRYPTION` belum pernah dinyalakan — makro pendukungnya tidak
      ikut terbawa. Diperbaiki dengan menyalin definisi upstream dari kernel
      a6010 (`include/crypto/hash.h:61-64`), basis sama 3.10.108, berkas identik
      byte-per-byte sampai baris 60.
- [x] Build bersih: `fs/crypto/{crypto,fname,policy,keyinfo,bio}.o` →
      `fscrypto.o`. `.config` memuat `FS_ENCRYPTION`, `F2FS_FS_ENCRYPTION`, dan
      `CRYPTO_XTS/CTS/ECB` yang diseleksi otomatis.
- [x] `Image` 18.429.944 B (dari 18.327.160). Jauh di bawah
      `BOARD_RAMDISK_OFFSET` 0x02000000.
- [ ] Verifikasi `/proc/crypto` di perangkat — menunggu flash (Fase 2)
- **fstab belum disentuh**, sesuai rencana: kernel yang mampu enkripsi tapi tidak
  dipakai adalah no-op yang aman.

### Fase 1 — TWRP dengan FBE  ✅ SELESAI (`android_device_oppo_A37f@3e0b507`)
- [x] `prebuilt/Image` ← kernel Fase 0, sha256 `a0f0a318bb21…`
- [x] `TARGET_USERIMAGES_USE_F2FS := true` — **tidak redundan**, tanpanya
      `mkfs.f2fs`/`fsck.f2fs` tidak ikut dibangun (`Android.mk:581-585`) dan TWRP
      tidak bisa memformat `/data` jadi f2fs
- [x] `TW_INCLUDE_CRYPTO_FBE := true` — **ternyata redundan**:
      `Android.mk:347-358` sudah menyetelnya sendiri saat `TW_INCLUDE_CRYPTO=true`
      dan SDK ≥ 24, dan BoardConfig sudah punya itu sejak dulu. Artinya build TWRP
      sebelumnya **kemungkinan sudah memuat kode FBE**. Tetap ditulis eksplisit
      karena syaratnya bergantung versi SDK lingkungan build.
- [x] `twrp.fstab:9` → f2fs + `fileencryption=aes-256-xts:aes-256-cts`
      - **tanpa sufiks `:v1`** — parser TWRP 9.0 memecah pada titik dua PERTAMA
        (`partition.cpp:904-918`) lalu menyetel `fbe.contents`/`fbe.filenames`,
        jadi `:v1` akan mengotori nilai filenames. Sufiks itu hanya untuk fstab LOS.
      - `aes-256-cts` **wajib eksplisit** — default TWRP `aes-256-heh`
        (`Ext4CryptPie.cpp:301`), bukan yang dipakai Android
- [x] `recovery.img` terbangun: **27.740.160 B**, margin 5.814.272 B di bawah
      `BOARD_RECOVERYIMAGE_PARTITION_SIZE` (33.554.432)
      sha256 `7f67083a1e0a4149…`

**Verifikasi isi image** (bukan sekadar "terbentuk"):

| Yang diperiksa | Hasil |
|---|---|
| Kernel di dalam | sha256 `a0f0a318bb21…` — **identik** dengan `prebuilt/Image` dan keluaran build LOS |
| `etc/twrp.fstab:24` | `/data f2fs defaults fileencryption=aes-256-xts:aes-256-cts` |
| `sbin/libe4crypt.so` | ada, 148.048 B |
| Titik masuk FBE | `e4crypt_initialize_global_de()`, `e4crypt_unlock_user_key(...)`, `Decrypt_User` |
| Awalan keyring di biner | `fscrypt`, `f2fs`, `ext4`, `logon`, `e4crypt` — kelimanya ada |
| Keymaster | `android.hardware.keymaster@3.0` **dan** `@4.0` dirujuk; perangkat punya 3.0 |
| Perkakas f2fs | `mkfs.f2fs`, `fsck.f2fs`, `sload.f2fs` — bukti `TARGET_USERIMAGES_USE_F2FS` memang perlu |

Artefak disimpan sebagai **berkas nyata** (bukan symlink) di
`/root/a37-twrp/out/fbe-artifacts/` dengan `SHA256SUMS` — pelajaran dari build
Agustus lalu, yang hilang begitu pohon sumbernya dihapus.

### Penghalang yang ditemukan saat Fase 1

**Pohon sumber sudah tidak ada.** `/root/twrp` dihapus setelah build Agustus dan
`recovery.img` hasilnya ikut hilang (`out/share/recovery-twrp-ramoops.img`
menjadi symlink putus; yang tersisa 30 MB di `los21-artifacts` adalah recovery
LineageOS). Tidak ada ruang mudah dibebaskan: ke-39 ZIP ROM di `los23/out`
semuanya hardlink ke **satu** inode (844 MB total), ccache hanya 282 MB. Sync
ulang `twrp-9.0` dijalankan dengan 34 GB bebas → pohon 22 GB, sisa 12 GB.

**Dua jebakan lingkungan build — keduanya BUKAN soal kode:**

1. `PATH=/opt/python2/bin:$PATH` **wajib** diekspor sebelum build. Tanpanya
   `build/make/tools/check_radio_versions.py` gagal parse
   (`SyntaxError: Missing parentheses in call to 'print'`) karena
   `/usr/bin/python` di host ini Python 3.12. Interpreter 2.7.18 sudah terpasang
   di `/opt/python2` sejak 12 Agustus. **Jangan tambal skripnya** — itu repo
   hulu yang di-sync, tambalannya hilang pada sync berikutnya, dan masalahnya
   memang di lingkungan.

2. Build yang gagal di tengah meninggalkan `java-source-list` **0 byte** di
   `out/host/common/obj/JAVA_LIBRARIES/dumpkey_intermediates/`. Build berikutnya
   menganggapnya mutakhir, memberi javac daftar kosong, dan menghasilkan
   `dumpkey.jar` berisi 1088 kelas bouncycastle tapi **nol** `com/android/` —
   **tanpa pesan error**. Log bahkan mencetak "Host Java: dumpkey" seolah
   sukses; kegagalannya baru muncul jauh kemudian sebagai
   `ClassNotFoundException: com.android.dumpkey.DumpPublicKey`. Obatnya: hapus
   direktori intermediate modul itu saja, jangan seluruh `out/`.

### Fase 2 — Pasang TWRP, uji SEBELUM enkripsi  ✅ LOLOS
- [x] Flash recovery, boot ke TWRP — `ro.twrp.boot=1`, `ro.build.product=A37f`,
      TWRP 3.7.0_9-0, build `Sat Aug 29 05:15:58 UTC 2026`
- [x] Kernel yang berjalan: `3.10.108-lineageos-gbe67c444ba1-dirty`. Sufiks
      `-dirty` adalah penanda kernel FBE kita (dibangun sebelum perubahan
      di-commit); sistem lama berjalan tanpa sufiks itu.
- [x] **Verifikasi Fase 0 yang tertunda:** `/proc/crypto` memuat
      `xts(aes)` → `xts-aes-neon` prio 200. (`cts(cbc(aes))` belum muncul karena
      CTS adalah template yang baru di-instantiate saat diminta — bukan tanda
      hilang.)
- [x] **GERBANG LOLOS.** `/data` ter-mount dan terbaca:
      ```
      /dev/block/mmcblk0p38 on /data type ext4 (rw,seclabel,relatime,data=ordered)
      /data/         adb anr apex app app-asec app-lib backup ...
      /data/media/0/ Alarms Android Audiobooks DCIM Documents Download Movies
      packages.list  com.android.fmradio 1000 0 /data/user/0/... (isi terbaca)
      ```
      Nama direktori wajar, bukan sampah terenkripsi. Deteksi blkid bekerja:
      fstab menyebut f2fs, partisi sebenarnya ext4, TWRP mount sebagai ext4.
- [x] Properti FBE tersetel **benar** dari fstab:
      ```
      I:FBE contents 'aes-256-xts', filenames 'aes-256-cts'
      Fstab_File_System: f2fs
      Flags: ... Can_Be_Encrypted Use_Userdata_Encryption ...
      ```
      `fbe.filenames` = `aes-256-cts` — bukan `aes-256-heh` (default TWRP) dan
      bukan `aes-256-cts:v1` (yang akan terjadi kalau sufiks `:v1` dibiarkan).
      Kedua keputusan di baris fstab terbukti benar di perangkat.
- [x] `/sbin/mkfs.f2fs`, `fsck.f2fs`, `libe4crypt.so` semuanya ada

### Fase 3 — Aktifkan FBE di ROM  ✅ SELESAI (`rb_device_oppo_A37@09e3e2e1`, `kernel@d055d768d26`)
- [x] `fstab.qcom:25` + `fileencryption=aes-256-xts:aes-256-cts:v1`
- [x] ROM `lineage-23.2-20260829_085630` dibangun dan diflash
- [x] **BOOTLOOP** pada percobaan pertama — berhenti di logo OPPO, reboot ke
      recovery. Didiagnosis dari ramoops:

      F2FS-fs (mmcblk0p38): Mounted with checkpoint version = 3137a167
      init: [libfs_mgr] __mount(target=/data,type=f2fs)=0: Success
      init: [libfs_mgr] /data is file encrypted
      vold  Kernel doesn't support FS_IOC_ADD_ENCRYPTION_KEY. Falling back to
            session keyring
      vold  Unable to find device keyring: Function not implemented   <-- ENOSYS

      Mount, deteksi FBE, dan pemilihan jalur v1 semuanya BENAR. Yang gagal
      langkah terakhir: `keyctl()` mengembalikan ENOSYS.

      Sebab: di kernel 3.10 `KEYS_COMPAT` hanya didefinisikan per-arsitektur
      (`arch/x86/Kconfig:2312`, `s390:265`, `powerpc:1014`, `sparc:537`) dan
      **tidak ada di arm64**. `security/keys/Makefile:18` karena itu tidak pernah
      membangun `compat.o`, `compat_sys_keyctl` yang dirujuk `unistd32.h:647`
      tidak ada, dan linker mengisi entri syscall 311 dengan `sys_ni_syscall`.

      Ini khas A37 — kernel arm64 dengan userspace 32-bit. Rujukan a6010 secara
      struktural tidak bisa mengajari ini: kernel mereka arm 32-bit murni,
      lapisan compat tidak pernah terlibat.

      Perbaikan: tiga baris di `arch/arm64/Kconfig`, bentuk sama dengan
      `SYSVIPC_COMPAT` yang sudah ada tepat di atasnya. Terverifikasi:
      `compat.o` terbangun (3.488 B), `CONFIG_KEYS_COMPAT=y`, dan
      `ffffffc00024a344 T compat_sys_keyctl` ada di System.map.
- [x] Flash `boot.img` perbaikan → **boot normal**

### Fase 4 — Verifikasi dan pengukuran  ✅ SELESAI

**FBE aktif, terverifikasi berlapis:**

```
ro.crypto.state = encrypted        ro.crypto.type = file
/data           = f2fs (rw,seclabel,...,inline_xattr,inline_data,...)
kernel          = 3.10.108-lineageos-ga5e7652c8c5-dirty
/data/unencrypted/mode = aes-256-xts:aes-256-cts:v1     <- persis isi fstab
/data/unencrypted/ref  = 50 88 32 d3 5b 01 b5 de        <- 8 byte, deskriptor v1
am_crash 0   am_anr 0   tombstone 0   SIM LTE normal
```

**Biaya kinerja — diisolasi dengan eksperimen terkontrol.** `/data/unencrypted/`
ada di f2fs yang sama tapi sengaja tidak dienkripsi, jadi satu-satunya variabel
yang berbeda adalah enkripsi:

| 256 MB, governor performance @1209,6 MHz | f2fs polos | f2fs + FBE | selisih |
|---|---|---|---|
| Tulis (`conv=fsync`) | 37 MB/s | 29 MB/s | −22% |
| Baca (cache dingin) | **141 MB/s** | **37 MB/s** | **−74%** |

Pembanding baseline lama (ext4 polos): baca 138, tulis 34 MB/s. Jadi **f2fs
sendiri sedikit lebih cepat** dari ext4 — seluruh penurunan berasal dari
enkripsi, bukan dari pergantian filesystem.

Angka baca 37 MB/s mendarat nyaris tepat di langit-langit AES-256 bulk yang
diukur `bssl` sebelumnya (35 MB/s). Pembacaan berurutan sekarang **terikat
kripto, bukan flash** — persis yang diprediksi dari `/proc/cpuinfo` tanpa
instruksi AES dan dari `qcom-xts(aes)` yang tidak pernah cocok dengan permintaan
`xts(aes)` fscrypt.

Tulis hanya turun 22% karena 34-37 MB/s memang sudah di bawah langit-langit itu.

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

---

## Fase 5 — TWRP 12.1: dibangun, tidak boot (terpecahkan di Fase 6)

Setelah jalur TWRP 9.0 buntu, rujukan acroreiser twrp-12.1 (`android_device_
lenovo_a6010`, `android_kernel_lenovo_a6010`) menunjukkan susunan yang berjalan
di msm8916/kernel 3.10 — perangkat yang praktis sama dengan A37.

**Analisis awalnya benar dan tetap berlaku.** Dua hal diverifikasi dari sumber
sebelum sebaris kode ditulis:

| | |
|---|---|
| vold TeamWin android-12.1 | `KeyStorage.cpp:74` memuat komentar IDENTIK dengan Android 16 ("old key directories may contain a file named 'stretching'"), `:438` memakai `appId = secdiscardable_hash + auth.secret` yang juga identik, set berkas kunci identik, prefix hash identik. Masalah `stretching` yang butuh tambalan di 9.0 **tidak ada** di 12.1. |
| Kernel twrp-12.1 a6010 | Tidak punya apa pun yang kita butuhkan. ext4+Adiantum, F2FS bahkan tidak dibangun, dan **tidak ada `CONFIG_KEYS_COMPAT`** — kernel mereka arm 32-bit murni. |

Koreksi atas analisis sebelumnya di bagian 0: kesimpulan "12.1 butuh keystore2 +
authsecret + metadata encryption" **keliru**. Itu hasil memeriksa
`bootable/recovery` saja; implementasi FBE-nya sebenarnya di fork `system/vold`
milik TeamWin, yang mendukung `TW_USE_FSCRYPT_POLICY := 1`.

### Yang dibangun

Device tree lengkap di `android_device_oppo_A37f` branch **`twrp-12.1`**
(`b13d0ce`, lalu `7c36e94`). `recovery.img` 32.055.296 B, margin 1.499.136 B.

Isinya diverifikasi dengan membongkar ramdisk, bukan dari status build:

```
offset 40 = 210944                      ukuran dt.img — tambalan QCDT bekerja
kernel sha256 5d4ee856…                 cocok dengan prebuilt/Image
etc -> /system/etc                      symlink terbentuk
ramdisk magic 5d0000                    LZMA
keymaster@4.1-service                   6.068 B
gatekeeper@1.0-service.software        20.832 B
libkeymaster4.so / libkeymaster41.so   57.432 / 23.092 B
vendor/manifest.xml + system/etc/vintf/manifest.xml
system/etc/recovery.fstab               fileencryption=aes-256-xts:aes-256-cts:v1
```

### Enam penghalang build

Sepuluh percobaan build. Tidak satu pun menyentuh keputusan desain dari rujukan;
device tree-nya benar sejak `lunch` pertama.

| # | Penghalang | Sifat |
|---|---|---|
| 1 | `\x0a` di `TW_INPUT_BLACKLIST` bukan escape JSON yang sah — soong mati saat menulis `soong.variables`. Diganti `\n`, sah di JSON **dan** string C. | lingkungan |
| 2 | ccache read-only di dalam sandbox build 12.1 (build LOS memakai bind-mount `-B /root/.ccache`, 12.1 tidak). | lingkungan |
| 3 | `USE_CCACHE=0` kalah oleh `CCACHE_EXEC` yang diset `/root/.bashrc`. Diselesaikan dengan mengarahkan `CCACHE_DIR` ke dalam pohon `out/`. | lingkungan |
| 4 | `mkbootimg` AOSP 12 membuang `--dt`; A37 memakai QCDT. Tiga hunk disalin dari mkbootimg LineageOS. | platform |
| 5 | `/etc` adalah symlink ke `/system/etc` di layout 12.1; direktori `recovery/root/etc/` menghalanginya. | layout |
| 6 | Sisa `root/etc` di `out/` membuat perbaikan #5 tidak berlaku — errornya menunjuk gejala, bukan sebab. | artefak basi |

### Kegagalan boot pertama: kernel panic — TERDIAGNOSIS

`BOARD_RAMDISK_USE_XZ := true` disalin dari a6010. Kernel mereka punya
`CONFIG_RD_XZ`; kernel A37 hanya `CONFIG_RD_BZIP2` dan `CONFIG_RD_LZMA`
(`lineageos_a37f_defconfig:27-28`). Kernel panic saat memuat ramdisk:

```
Process swapper/4 (Pid: 1)
Call trace:
  [<(null)>] (null)
  initrd_load+0x0/0x2d4
  prepare_namespace+0xdc
  kernel_init_freeable
Code: (bad PC value)
```

Diperbaiki dengan LZMA. **Ini kelas kesalahan yang sama dengan `KEYS_COMPAT`,
hanya arah sebaliknya**: menyalin dari rujukan pada hal yang justru bergantung
pada perbedaan antara kedua kernel. Rujukan mengajari struktur, bukan apa yang
kernel kita dukung.

### Kegagalan boot kedua: "offline" — BELUM TERDIAGNOSIS

Setelah perbaikan LZMA, kernel memuat ramdisk dan **USB ter-enumerasi dengan
serial yang benar** (`23bb7d0`) — kemajuan nyata dari panic yang mati sebelum
userspace. Tapi `adb devices` berhenti di `offline`, `adb reconnect` tidak
menolong, dan TWRP tidak pernah menampilkan UI.

Yang sudah disingkirkan sebagai penyebab, dengan membandingkan ramdisk 12.1
terhadap ramdisk 9.0 yang adb-nya bekerja:

```
sys.usb.ffs.aio_compat=1   ADA di keduanya (prop.default:65)
ro.debuggable=1            sama
ro.secure=0                sama
persist.sys.usb.config=adb sama
ro.build.type=eng          sama
```

**Penyebabnya belum diketahui.**

### Kenapa berhenti: bukti hilang tiga kali

Ramoops akan memuat log kegagalan, tapi **hilang tiga kali** karena pemulihan
lewat EDL memutus daya dan mengosongkan RAM.

Prosedur yang BENAR, untuk siapa pun yang melanjutkan:

1. Flash `recovery.img` **dari sistem yang berjalan**, bukan EDL:
   `dd if=<img> of=/dev/block/mmcblk0p23 bs=1048576` — aman, recovery tidak
   sedang dipakai. Verifikasi dengan membaca balik jumlah byte yang PERSIS sama.
2. `adb reboot recovery`
3. Kalau gagal: **tahan Power sampai mati, lalu nyalakan biasa**. JANGAN EDL,
   JANGAN kombinasi recovery. BCB di `misc` terbukti kosong, jadi dijamin masuk
   sistem.
4. Sistem boot normal dan `/sys/fs/pstore/console-ramoops` memuat log recovery
   yang gagal.

Semua prasyaratnya terverifikasi: root di sistem (`u:r:su:s0`), partisi recovery
bisa ditulis dari sistem, sistem boot normal, pstore terbaca, BCB kosong.

### Keadaan akhir

Perangkat berfungsi penuh. FBE aktif dan terukur. TWRP 9.0 lama terpasang dan
bisa flash, wipe, sideload, mount.

**Keterbatasan yang diketahui: TWRP tidak bisa mendekripsi `/data` selama FBE
aktif.** Backup partisi data lewat recovery tidak berguna — isinya blob
terenkripsi. Yang tetap berfungsi: `adb sideload`, flash ROM, wipe, flash dari
kartu SD.

Device tree 12.1 lengkap dan siap dipakai kalau ada yang mau melanjutkan; yang
kurang hanya diagnosis satu kegagalan userspace, dan prosedur untuk
mendapatkannya sudah tertulis di atas.

---

## Fase 6 — TWRP 12.1 berhasil. Dekripsi FBE tercapai.

> Ditulis 29 Agustus 2026, setelah Fase 5 dihentikan. Yang membuka jalan buntu
> Fase 5 bukan ide baru, melainkan satu pertanyaan yang belum pernah ditanyakan:
> **kenapa adb selalu `offline`?** Begitu adb hidup, sisanya terbaca dari log
> dalam hitungan menit.

### 6.0 Ringkas: apa yang sebenarnya salah

Fase 5 berhenti dengan tiga gejala yang tampak seperti tiga masalah besar:
recovery tidak menampilkan UI, adb selalu `offline`, dan diagnosis mustahil
karena ramoops hilang berulang kali. Ternyata ketiganya **satu rantai**, dan
tidak ada yang mendasar:

| Gejala | Sebab sebenarnya | Ukuran perbaikan |
|---|---|---|
| adb `offline` | kernel tanpa AIO di FunctionFS | 4 commit backport |
| tidak ada UI | satu pustaka hilang dari ramdisk | 1 berkas prebuilt |
| sentuhan liar | 1 flag salah + blacklist yang tidak pernah bekerja | 1 baris + 1 tambalan |
| adb mati 5 detik | MTP merobohkan gadget USB | 1 baris |

### 6.1 adb `offline`: kernel, bukan TWRP

Gejalanya menyesatkan: USB ter-enumerasi dengan serial benar, tapi handshake
CNXN tidak pernah terjadi.

Sebabnya `ffs_epfile_operations` di kernel A37 hanya punya `.read`/`.write`,
tanpa `.aio_read`/`.aio_write` — nol kemunculan `aio_` dan `kiocb` di
`drivers/usb/gadget/f_fs.c`. Akibatnya `io_submit()` ke fd endpoint
mengembalikan `-EINVAL`.

Dan adbd AOSP 12 **tidak punya jalur mundur sama sekali**:

```
twrp12  packages/modules/adb/daemon/usb.cpp:604
    if (io_submit(aio_context_.get(), 1, &iocb) != 1) {
        HandleError(...);   // tidak ada penanganan EINVAL
        return false;
    }

usb_init_legacy          : 0 kemunculan
daemon/usb_legacy.cpp    : TIDAK ADA (dihapus AOSP 12)
Android.bp:540-541       : hanya usb.cpp + usb_ffs.cpp
```

**Jebakan yang mahal:** kita SUDAH memperbaiki bug ini untuk ROM — commit
`1781bd85` memulihkan `usb_init_legacy` dan deteksi `gFfsAioSupported` di
`packages/modules/adb` **LineageOS**. Tapi TWRP memakai `packages/modules/adb`
**AOSP**, repo yang sama sekali berbeda. Tambalan itu tidak pernah terbawa.

> **Aturan yang lahir dari sini:** kalau ROM dan recovery sama-sama butuh sebuah
> perbaikan, kerjakan di KERNEL. Keduanya berbagi kernel
> (`TARGET_PREBUILT_KERNEL := prebuilt/Image`), tapi tidak berbagi pohon
> userspace mana pun.

Perbaikannya meniru a6010 yang tidak pernah punya masalah ini karena kernelnya
sudah membackport AIO. Empat commit, urutan kronologis wajib:

```
e7252e046c6  add poll for endpoint 0                   (+41)
f446497f1d0  add aio support                           (+210/-67)
704a347f6eb  Fix use after free as part of queue failure  (+1)
0b55453c8df  Fix use-after-free                          (-1)
```

Dua commit terakhir memperbaiki bug **di dalam kode aio itu sendiri** —
mengambil aio tanpa keduanya berarti menanam use-after-free. Urutan poll dulu
wajib: patch aio butuh `#include <linux/poll.h>` sebagai konteks di baris 29.

Keempatnya apply bersih. Dugaan awal bahwa `f_fs.c` kita terlalu menyimpang
ternyata meleset: acroreiser membackport di atas varian Qualcomm yang sama
(`MAX_BUF_LEN`, `atomic epfile->error`, `goto first_try`).

Ada di `rigaz29/kernel_oppo_msm8939` branch **`twrp-12.1`**, sengaja dipisah
dari `lineage-23`.

`.poll` di ep0 masalah kedua yang lebih halus: tanpa `.poll`, `fs/select.c:452`
memberi `DEFAULT_POLLMASK` yang selalu "siap", sehingga cabang timeout
`usb.cpp:277` tidak pernah aktif dan adbd langsung memblokir di `adb_read`.

**Yang ternyata BUKAN masalah:** format deskriptor. Kedua kernel hanya V1
(`FUNCTIONFS_DESCRIPTORS_MAGIC = 1`), dan adbd punya fallback sendiri
(`usb_ffs.cpp:282` coba V2, gagal, mundur ke V1 di `:285`). Justru inilah yang
menjelaskan kenapa USB tetap ter-enumerasi dengan serial benar.

### 6.2 Tidak ada UI: satu pustaka

Dengan adb hidup, jawabannya keluar dalam satu perintah:

```
init.svc.recovery = restarting          ← crash tiap 5 detik
$ /system/bin/recovery
CANNOT LINK EXECUTABLE: library "libresetprop.so" not found
```

Logo OPPO itu framebuffer yang tidak pernah ditimpa karena UI mati sebelum
menggambar. Dari **51** pustaka yang di-NEEDED biner recovery, **tepat satu**
tidak ada di ramdisk.

`bootable/recovery/Android.mk:368` menyalakan `TW_INCLUDE_LIBRESETPROP` otomatis
begitu `TW_INCLUDE_CRYPTO` aktif — jadi kita tidak pernah memintanya secara
sadar. Modulnya Soong dengan `recovery_available: true`, tapi varian recovery-nya
**tidak pernah dibangun**: nol direktori `*_recovery` di seluruh `out/soong`.
Pustakanya hanya mendarat di `out/.../system/lib/`.

Dipasang sebagai prebuilt lewat `TARGET_RECOVERY_DEVICE_DIRS`
(`build/make/core/Makefile:2073`) — pola yang sudah dipakai keempat prebuilt
lain di device tree ini, dan sama dengan cara a6010 mengirim service keymaster.

### 6.3 Sentuhan liar: dua sebab

**Pertama, flag yang kita setel sendiri.** `report/input-devices.txt` mencatat
`synaptics-s3203` dengan `ABS=2658000 0`. Didekode (format `/proc/bus/input/devices`
menulis word tinggi lebih dulu) menjadi bit 47, 48, 50, 53, 54, 57:

```
47  ABS_MT_SLOT          53  ABS_MT_POSITION_X
48  ABS_MT_TOUCH_MAJOR   54  ABS_MT_POSITION_Y
50  ABS_MT_WIDTH_MAJOR   57  ABS_MT_TRACKING_ID
```

Multitouch **tipe B**, yang menandai jari diangkat lewat `TRACKING_ID = -1`.
`TW_IGNORE_ABS_MT_TRACKING_ID := true` membuat `events.cpp:617` melakukan
`return 1` sebelum mencapai blok yang menyetel `touchReleaseOnNextSynReport`.
Pelepasan sentuhan tidak pernah terdaftar.

**Kedua — dan ini yang paling mudah terlewat — blacklist masukan tidak pernah
bekerja.** Pemeriksaan `strings` sempat menyatakan aman; `strings` justru
menyembunyikan masalahnya karena ia memecah pada newline. Pemeriksaan byte:

```
b'"hbtp_vmlis3dh-accelcompasslightproximity"'
```

Pemisah hilang, tanda kutip ikut ke dalam string. Jadi `hbtp_vm` dan
`lis3dh-accel` yang kita kira sudah diblokir sejak awal **tidak pernah**
terblokir. Rinciannya di `patches-twrp121/README.md`.

Yang paling merusak adalah `compass`: `ABS=7` yaitu `ABS_X`, `ABS_Y`, `ABS_Z`,
dan `events.cpp:510` menerjemahkan `ABS_X` langsung menjadi `e->p.x`.
Magnetometer yang mengalir terus menyuntikkan koordinat palsu.
`events.cpp:241-259` hanya mencocokkan NAMA — tanpa penyaringan kemampuan —
sehingga apa pun yang tidak diblokir ikut dibaca.

### 6.4 adb mati 5 detik: MTP

```
890: I:Starting MTP
910: E:[MTP] Failed to start usb driver!
```

`Enable_MTP()` di `partitionmanager.cpp` menyetel `sys.usb.config` ke `"none"`
lebih dulu — merobohkan **seluruh** gadget USB termasuk adb — lalu gagal
mengikatnya ulang sebagai `mtp,adb`.

Ironisnya MTP baru dijalankan **karena dekripsi berhasil**: `twrp.cpp:256`
mensyaratkan `TW_IS_DECRYPTED`. Jadi gejala ini justru bukti bahwa tujuan utama
sudah tercapai.

### 6.5 Dekripsi: berhasil

```
recovery.log:107   I:User 0 is not decrypted.
             110   Attempting to decrypt FBE for user 0...
             113   fscrypt_unlock_user_key returned fail
             119   Attempting to decrypt user's synthetic password
             122   using secdis to decrypt spblob
             123   spblob v2 / v3
             128   User 0 Decrypted Successfully!
             132   Data successfully decrypted
             135   I:New storage path after decryption: /data/media/0
```

`fscrypt_unlock_user_key` memang gagal — kernel 3.10 tidak punya keyring fscrypt,
persis seperti diperkirakan di Fase 1. Tapi TWRP mundur ke **synthetic password**
lewat `secdiscardable`, dan itu berhasil. Keymaster 4.1 yang dipaksa lewat
`TW_FORCE_KEYMASTER_VER` terpakai (`Keymaster_Ver::Using keymaster version '4.1'`),
sehingga error `keymaster@4.0::IKeymasterDevice` yang berulang di dmesg ternyata
hanya derau.

### 6.6 Keadaan akhir terverifikasi

Diukur langsung lewat adb di dalam recovery:

```
init.svc.recovery = running          (sebelumnya: restarting)
uptime adb        = 619 detik+       (sebelumnya: ~5 detik)
sys.usb.config    = adb              gadget functions = ffs
/data             = f2fs, termount, isi nyata terlihat
blacklist         = 5 perangkat, tercatat di log
dmesg             = 0 segfault / BUG / panic
error di log      = 0
```

Perangkat masukan yang tetap dibaca hanya empat yang dibutuhkan:
`synaptics-s3203`, `synaptics-s3203-kpd`, `qpnp_pon`, `gpio-keys`.

### 6.7 Pelajaran

1. **Diagnosis mengalahkan tebakan.** Fase 5 berhenti karena ramoops hilang
   tiga kali. Yang mengubah keadaan adalah membuat saluran diagnosis hidup
   (adb), bukan menebak lebih keras. Setelah itu tiga masalah selesai dalam
   satu sore.

2. **Perbaikan userspace tidak menyeberang antar-pohon.** ROM dan TWRP tidak
   berbagi repo adb. Kernel adalah satu-satunya lapisan yang keduanya bagi.

3. **`strings` bukan alat verifikasi untuk string yang mengandung pemisah.**
   Ia memecah pada newline dan menyembunyikan justru apa yang sedang diperiksa.
   Pemeriksaan byte yang menemukan bug blacklist.

4. **Rujukan mengajari struktur, bukan kemampuan kernel.** a6010 tidak punya
   `CONFIG_KEYS_COMPAT` tapi kita butuh; a6010 punya `CONFIG_RD_XZ` tapi kita
   tidak. Keduanya memakan siklus flash. Sebaliknya, backport AIO mereka apply
   bersih karena basis `f_fs.c`-nya memang sama.

5. **Ramdisk basi menipu dua kali di proyek ini.** Kalau sebuah perubahan
   tampak tidak berefek, hapus `out/target/product/A37f/recovery` sebelum
   mencari sebab lain.

### 6.8 Yang masih terbuka

- `TW_EXTRA_LANGUAGES := false` **tidak berpengaruh** — kesembilan belas berkas
  bahasa (960 KB) tetap ikut. Tidak mendesak: partisi masih sisa 1,48 MB dari
  33.554.432 byte. Berarti pemangkasan bahasa yang dilakukan di Fase 5 untuk
  mengejar ukuran sebenarnya percuma; yang menyelamatkan waktu itu adalah
  pergantian XZ ke LZMA.
- Perekaman video, dan uji backup/restore penuh lewat TWRP di atas `/data`
  yang terdekripsi, belum dicoba.

---

## Fase 7 — MTP dan adb berdampingan. SELESAI.

> Ditulis 29-30 Agustus 2026, lanjutan Fase 6. Terverifikasi di perangkat:
> adbd memegang ep0/ep1/ep2 sementara recovery memegang /dev/mtp_usb, nol
> penolakan.

### 7.1 MTP: bug open ganda — SELESAI, terverifikasi

MTP dimatikan di akhir Fase 6 lewat `TW_EXCLUDE_MTP` karena diduga
merobohkan adb. Dugaan itu **salah**; MTP hanya korban.

`MtpServer::run()` selalu gagal dengan `Failed to start usb driver!` karena
`/dev/mtp_usb` dibuka dua kali — `mtp_MtpServer.cpp:77` untuk `controlFd`,
lalu `MtpDevHandle::start()` membukanya lagi. `unique_fd::reset()` menutup fd
lama, tapi argumennya dievaluasi lebih dulu, jadi open kedua bertabrakan
dengan kunci eksklusif `mtp_lock(&_mtp_dev->open_excl)` di `f_mtp`.

Terbukti langsung: membuka `/dev/mtp_usb` dua kali di perangkat menghasilkan
`Device or resource busy` pada yang kedua. Setelah ditambal, MTP berjalan dan
PC mendeteksi storage. Lihat `patches-twrp121/0003`.

### 7.2 adb setelah komposisi USB berganti — SELESAI

Dengan MTP hidup, adb jatuh ke `offline`. Logcat dari perangkat memberi
mekanismenya tanpa ruang tebakan:

```
02:09:58  adbd PID 276  opening control endpoint /dev/usb-ffs/adb/ep0
02:09:58  adbd PID 276  USB event: FUNCTIONFS_BIND / FUNCTIONFS_ENABLE
02:10:01  adbd PID 308  cannot open control endpoint: Device or resource busy
```

**PID 276 tidak pernah menerima `FUNCTIONFS_UNBIND`.** `android_disable()`
tidak memanggil `functionfs_unbind`; ia bergantung pada adbd melepas `ep0`
(commit CAF `ac76de240429` menyebutnya eksplisit). Jadi adbd tidak bisa tahu
gadget dirobohkan — ia harus dihentikan dari luar.

Perbaikannya: `Release_ADB_FFS()` menghentikan adbd lewat `ctl.stop` dan
menunggu `init.svc.adbd` berhenti `running`, dipanggil sebelum
`sys.usb.config` disentuh di `Enable_MTP()` dan `Disable_MTP()`.
Lihat `patches-twrp121/0004`.

### 7.3 Tiga percobaan yang gagal, dan kenapa

Dicatat karena masing-masing memakan satu siklus flash dan pelajarannya sama.

| Percobaan | Hasil | Kenapa gagal |
|---|---|---|
| `TW_EXCLUDE_MTP := true` | adb jalan, MTP hilang | menyerang gejala; MTP bukan penyebabnya |
| `TW_MTP_DEFAULT_DISABLED` | tidak berpengaruh | `mPersist.SetValue()` hanya menetapkan DEFAULT; nilai `tw_mtp_enabled=1` sudah tersimpan di `/data` dan menang |
| komposisi statis `mtp,adb` sejak boot | **keduanya mati** | mengubah jalur boot yang belum pernah terbukti; gadget tidak naik |
| `restart adbd` di init | adb tetap offline | `restart` = stop+start tanpa menunggu; proses lama masih memegang `ep0` |

**Pelajarannya berulang dan sama seperti Fase 6:** ketiga percobaan itu
dibangun dari penalaran tanpa data perangkat. Yang akhirnya memberi jawaban
adalah satu berkas logcat. Ambil data dulu, baru bangun.

Rujukan acroreiser diperiksa untuk masalah ini dan **tidak ada yang bisa
diambil**: `android.c` mereka beda 4 baris dari kita (satu pragma, satu gaya
kurung kurawal), `struct functionfs_config` mereka tetap instance tunggal, dan
commit CAF yang relevan sudah ada di pohon kita. Nilainya justru pada pesan
commit `ac76de240429` yang menjelaskan ketergantungan unbind pada adbd.

### 7.4 Sebab sebenarnya: kebocoran referensi AIO

Enam percobaan berbasis penalaran meleset. Yang menyelesaikannya adalah
pelacakan di kernel — `pr_info` pada setiap buka/tutup endpoint FunctionFS
beserta nilai `state`, `opened`, dan `ref`:

```
CLOSE ep0   (opened=3 sebelum) -> 2
CLOSE       (opened=2 sebelum) -> 1
(tutup ketiga TIDAK PERNAH datang)
ffs: ep0 open DITOLAK: state=2 opened=1 ref=4     <- berulang selamanya
```

`state=2` = `FFS_ACTIVE`, jadi penolakan datang dari `opened != 0` — tepat satu
berkas terbuka, sementara pemindaian `/proc/*/fd` menemukan **nol** pemegang.
Berkas yang hidup tanpa fd hanya bisa ditahan referensi kernel: `io_submit()`
mengambil `fget()` (`fs/aio.c:1110`), dilepas hanya saat request selesai
(`:542`). Antrean baca AIO adbd di `ep1` tidak pernah diselesaikan saat
komposisi USB berganti.

**Regresi dari backport AIO kita sendiri** (Fase 6.1). Backport itu wajib —
adbd AOSP 12 tidak punya jalur legacy — jadi tidak bisa sekadar dicabut.

Perbaikannya menghindari pemicu, bukan menambal kebocoran: `sys.usb.config`
disetel `mtp,adb` di `init.rc` sebelum adbd pertama kali berjalan, sehingga
`Enable_MTP()` melihat nilainya sudah benar dan tidak pernah memutar komposisi.
adbd mengikat sekali, ke komposisi final. Lihat `patches-twrp121/0005`.

Menambal kebocorannya sendiri butuh pelacakan request yang menggantung di
`f_fs.c` — backport AIO tidak menyimpan daftarnya, jadi tidak ada yang bisa
dibatalkan. Itu pekerjaan besar di jalur yang sudah dua kali membuat perangkat
tidak boot, dan sengaja tidak dikerjakan.

### 7.5 Jebakan terakhir: idProduct

Setelah komposisi benar, perangkat justru **tidak terdeteksi sama sekali** di
PC — bukan `offline`. `on fs` menulis `idProduct D001`, PID untuk adb tunggal;
`Enable_MTP()` yang biasanya menggantinya ke `4EE2` kini dilewati seluruhnya.
Perangkat mengumumkan PID adb-tunggal padahal menyajikan dua antarmuka, dan
host tidak mencocokkan antarmuka adb-nya.

Keadaan internal sepenuhnya benar; hanya identitas yang diumumkan yang salah.
Itu sebabnya log terlihat sehat sementara PC kosong — perbedaan gejala
"tidak terdeteksi" versus "offline" ternyata informasi diagnostik yang penting.

### 7.6 Bug sampingan yang ditemukan

`ffs_epfiles_create()` memakai `epfiles->name` (basis array) alih-alih
`epfile->name` (kursor loop):

```c
sprintf(epfiles->name, "ep%u", i);
```

Semua iterasi menimpa `epfiles[0].name`, sehingga `epfiles[1].name` tidak
pernah diisi. Nama endpoint di log tertukar; jumlahnya tetap benar. Justru nama
kosong itulah yang mengidentifikasi `ep1` sebagai berkas yang bocor. Belum
diperbaiki, supaya sumber kernel tetap sama persis dengan Image yang diuji.

### 7.7 Rekapitulasi percobaan yang gagal

| Percobaan | Hasil | Kenapa gagal |
|---|---|---|
| `TW_EXCLUDE_MTP := true` | adb jalan, MTP hilang | menyerang gejala |
| `TW_MTP_DEFAULT_DISABLED` | tidak berpengaruh | `mPersist` hanya default; nilai tersimpan menang |
| komposisi statis + `on fs` diubah | keduanya mati | menulis `mtp,adb` ke sysfs sebelum ffs ter-mount |
| `restart adbd` di init | tetap offline | `restart` = stop+start tanpa menunggu; balapan `ep0` |
| `Release_ADB_FFS()` | tetap offline | adbd memang berhenti bersih; bukan itu masalahnya |
| pemulihan `FFS_CLOSING` | tetap offline | `state` ternyata `FFS_ACTIVE`, bukan `FFS_CLOSING` |

Enam kali. Setiap kali penalarannya masuk akal dan setiap kali salah, karena
menebak di antara beberapa mekanisme yang sama-sama mungkin. Yang mengakhirinya
satu putaran instrumentasi yang mencetak angkanya.

**Pelajaran yang sama untuk ketiga kalinya di proyek ini** (lihat 6.7 dan
Fase 5): kalau sebuah kegagalan sudah dua kali salah tebak, berhenti menambal
dan pasang pengukuran. Itu satu siklus flash yang menggantikan enam.
