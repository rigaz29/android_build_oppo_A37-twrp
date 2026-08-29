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
