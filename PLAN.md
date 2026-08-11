# TWRP untuk OPPO A37f dengan kernel sendiri

Tujuan tunggal: **recovery yang bisa membaca ramoops.** Bukan menyaingi TWRP resmi,
bukan menambah fitur — hanya menukar kernelnya dengan kernel kita yang sudah punya
patch `pstore/ram`, supaya kegagalan boot LOS 21 akhirnya bisa dibaca.

Ditulis 11 Agustus 2026. Sub-proyek dari
[`android_build_oppo_A37-21`](https://github.com/rigaz29/android_build_oppo_A37-21).

---

## 0. Kenapa ini perlu

TWRP yang terpasang sekarang **tidak bisa** membaca ramoops, dan sebabnya bukan
konfigurasi yang salah — kernelnya memang tidak mampu.

```
TeamWin/android_device_oppo_A37f  android-9.0  BoardConfig.mk:43
    TARGET_PREBUILT_KERNEL := $(DEVICE_PATH)/prebuilt/Image     16.221.688 B
    BOARD_MKBOOTIMG_ARGS += --dt $(DEVICE_PATH)/prebuilt/dt.img    210.944 B
```

Kernel itu **prebuilt** — biner jadi, bukan dibangun dari sumber. Jadi ia tidak
punya patch yang kita buat di
[`kernel_oppo_msm8939@6832040`](https://github.com/rigaz29/kernel_oppo_msm8939):
`ramoops_probe()` di kernel ini hanya membaca device tree dan mengabaikan
`platform_data` dari parameter cmdline, sehingga probe selalu gagal dan pstore
ter-mount **tanpa backend**. `/sys/fs/pstore` kosong melompong — bukan cuma
`console-ramoops` yang hilang.

Diverifikasi di perangkat: TWRP masuk, direktorinya kosong. Dan bugreport LOS 20
menunjukkan gejala yang sama sejak dulu (`incidentd: failed to open
/sys/fs/pstore/console-ramoops`).

Yang menentukan adalah kernel yang **sedang berjalan saat membaca**, bukan yang
menulis. Karena itu recovery-nya yang harus diganti.

### Kenapa tidak pakai recovery LineageOS saja

Bisa, dan itu jalan tercepat: `recovery.img` dari build LOS 21 sudah memakai kernel
yang dipatch (sha256 kernelnya identik dengan `boot.img`). Tapi TWRP punya yang
recovery LineageOS tidak: backup/restore partisi, terminal, file manager, mount
manual. Untuk siklus diagnosis berulang itu jauh lebih nyaman.

Keduanya tidak saling meniadakan — `updater-script` ROM LOS 21 hanya menulis
partisi **boot** (nol penyebutan recovery), jadi TWRP tidak pernah tertimpa oleh
flash ROM.

---

## 1. Fakta yang sudah diverifikasi

| | |
|---|---|
| Device tree | `TeamWin/android_device_oppo_A37f`, branch **`android-9.0`** (commit terakhir `98a46b3ae`, 2023-06-16). Branch lain hanya `android-5.1`. |
| Manifest TWRP | `minimal-manifest-twrp/platform_manifest_twrp_omni` branch **`twrp-9.0`** — cocok dengan branch device tree |
| Platform | `TARGET_ARCH := arm`, `armv8-a`, `TARGET_BOARD_PLATFORM := msm8916` — sama dengan device tree LOS kita |
| Kernel kita | `rigaz29/kernel_oppo_msm8939` branch `lineage-21` @ `6832040` — memuat patch `pstore/ram` **dan** `CONFIG_DETECT_HUNG_TASK`. Biner siap pakai: `out/…/obj/KERNEL_OBJ/arch/arm64/boot/Image`, 18.327.160 B, sha256 `be170546…` — **sha256 itu identik dengan kernel di dalam `boot.img` dan `recovery.img` LOS 21**, jadi Jalur A benar-benar memakai kernel yang sudah teruji |
| `dt.img` | TWRP 210.944 B, ukuran sama dengan milik kita tapi **isinya BERBEDA**: TWRP `57c924d8…` vs kita `459a2a6d…` |
| Partisi recovery | `BOARD_RECOVERYIMAGE_PARTITION_SIZE := 33554432` (32 MB) |

### 1.1 ⚠️ RISIKO UTAMA — kernel kita lebih besar dari offset ramdisk

```
BOARD_RAMDISK_OFFSET := 0x01000000        = 16.777.216 B
kernel TWRP prebuilt      16.221.688 B    muat, sisa 555.528 B
kernel KITA               18.327.160 B    MELEBIHI 1.549.944 B
```

Ramdisk dimuat di `base + 0x01000000`, tepat di tengah kernel kita. Untuk `boot.img`
LOS, tumpang tindih serupa ada dan perangkat tetap boot — jadi LK tampaknya
merelokasi. **Tapi ramdisk TWRP jauh lebih besar** (belasan MB, bukan 1,6 MB), jadi
kalau LK ternyata tidak merelokasi, kerusakannya jauh lebih luas.

Mitigasi, urut dari yang paling aman:

1. **Naikkan `BOARD_RAMDISK_OFFSET` ke `0x02000000`** (32 MB). Jarak jadi 32 MB,
   kernel 18,3 MB muat dengan sisa 13,7 MB. Satu baris, nol efek samping yang
   diketahui — ini yang dipakai.
2. Kalau LK menolak offset itu, turunkan ukuran kernel dengan mematikan modul
   yang tidak dibutuhkan recovery (kamera, audio, Wi-Fi). Lebih banyak kerja dan
   mengubah kernel yang sudah teruji — hindari kecuali (1) gagal.

⚠️ Jangan asumsikan (1) pasti bekerja. LK OPPO tertutup; satu-satunya bukti adalah
recovery yang benar-benar boot.

### 1.2 cmdline TWRP tidak punya parameter ramoops

```
TeamWin BoardConfig.mk:38
    console=ttyHSL0,115200,n8 androidboot.console=ttyHSL0 androidboot.hardware=qcom
    msm_rtb.filter=0x237 ehci-hcd.park=3 androidboot.bootdevice=7824900.sdhci
    lpm_levels.sleep_disabled=1 androidboot.selinux=permissive
```

Nol `ramoops.*`. Kernel yang dipatch pun tidak akan menyalakan ramoops tanpa
parameter itu, karena jalur `platform_data` diisi dari parameter modul cmdline.
**Harus ditambahkan**, sama seperti di `BoardConfig.mk` LOS kita:

```
ramoops.mem_address=0x9ff00000 ramoops.mem_size=0x400000
ramoops.record_size=0x40000 ramoops.console_size=0x100000
ramoops.pmsg_size=0x40000 ramoops.dump_oops=1
```

`msm_rtb.filter=0x237` boleh dibuang — `CONFIG_MSM_RTB` mati di defconfig kita,
jadi parameter itu diabaikan diam-diam. `console=ttyHSL0` sebaiknya
**dipertahankan** di recovery: berbeda dari ROM, di sini tidak ada notifikasi
"Serial console enabled" yang mengganggu, dan kalau pad UART pernah disolder itu
jadi jalur diagnosis paling langsung.

### 1.3 Batas disk — nyata dan mengikat

```
tersedia sekarang   35 GB
/root/los21/out     77 GB
```

Tree TWRP jauh lebih kecil dari Android penuh, tapi 35 GB tetap tipis. Yang aman
dihapus lebih dulu: `/root/los21/out` **setelah** ROM dan `recovery.img` yang
dibutuhkan disalin keluar. Jangan hapus `/root/los21` sendiri — `A37-21-pinned.xml`
memang bisa membangunnya ulang, tapi itu berjam-jam sync.

---

## 2. Dua jalur, dan mana yang dipilih

| | Jalur A — tukar prebuilt | Jalur B — bangun dari sumber |
|---|---|---|
| Cara | ganti `prebuilt/Image` dengan `Image` hasil build LOS kita | setel `TARGET_KERNEL_SOURCE` ke repo kernel kita |
| Ongkos | menit | jam (toolchain, defconfig recovery) |
| Kernel yang dipakai | **persis** yang sudah teruji di ROM LOS 21 | bisa berbeda karena flag build TWRP |
| Kalau perlu ubah config kernel | tidak bisa | bisa |

**Dipilih Jalur A.** Alasannya bukan sekadar cepat: kernel hasil build LOS 21 sudah
diverifikasi memuat `CONFIG_DETECT_HUNG_TASK=y` dan patch `pstore/ram`, dan
memakainya apa adanya berarti recovery menjalankan kernel yang **identik** dengan
yang menulis buffer ramoops. Itu menghilangkan satu variabel dari diagnosis.

Jalur B baru relevan kalau ternyata perlu mengubah config khusus recovery —
misalnya mengecilkan kernel (§1.1 mitigasi 2).

---

## 3. Fase

### Fase 0 — Ruang dan sumber
- [ ] Salin keluar dari `/root/los21/out`: `lineage-*.zip`, `boot.img`, `recovery.img`,
      `obj/KERNEL_OBJ/arch/arm64/boot/Image`, `installed-files.txt`
- [ ] Hapus `/root/los21/out` (77 GB) — **jangan** hapus `/root/los21`
- [ ] `repo init -u https://github.com/minimal-manifest-twrp/platform_manifest_twrp_omni.git -b twrp-9.0 --depth=1`
- [ ] Local manifest: `TeamWin/android_device_oppo_A37f` @ `android-9.0` ke
      `device/oppo/A37f`

**Kriteria selesai:** sync bersih, `device/oppo/A37f` ada, disk sisa ≥ 10 GB.

### Fase 1 — Tukar kernel dan cmdline
- [ ] `prebuilt/Image` ← `Image` dari build LOS 21 (18.327.160 B)
- [ ] `prebuilt/dt.img` ← `dt.img` dari build LOS 21 (`459a2a6d…`). Sudah
      dibandingkan: **berbeda** dari milik TWRP (`57c924d8…`) meski ukurannya sama.
      Dipakai milik kita, karena device tree harus sepadan dengan kernel yang
      memakainya — dan `459a2a6d…` inilah yang byte-identik dengan dt.img ROM LOS 20
      yang terbukti boot di perangkat ini.
- [ ] `BOARD_RAMDISK_OFFSET := 0x02000000` (§1.1)
- [ ] cmdline: tambah enam parameter `ramoops.*` (§1.2), buang `msm_rtb.filter`,
      pertahankan `console=ttyHSL0`

**Kriteria selesai:** `lunch omni_A37f-eng` lalu `mka recoveryimage` rc=0.

### Fase 2 — Verifikasi artefak sebelum menyentuh perangkat
- [ ] `recovery.img` ≤ 33.554.432 B (partisi 32 MB)
- [ ] cmdline di image memuat keenam parameter `ramoops.*`
- [ ] sha256 kernel di dalam `recovery.img` **identik** dengan kernel `boot.img`
      LOS 21 — ini yang membuktikan Jalur A benar-benar terjadi
- [ ] ramdisk memuat `/sbin/recovery` dan `system/etc/init/hw/init.rc` yang
      me-mount pstore

### Fase 3 — Uji di perangkat, tanpa mengorbankan TWRP lama
- [ ] `fastboot boot recovery.img` — jalan dari RAM, partisi tidak tersentuh
- [ ] `adb shell ls -la /sys/fs/pstore` ← **uji kontrol**, lebih penting dari `cat`
- [ ] Kalau TWRP baru boot dan pstore terisi: flash permanen
- [ ] Kalau bootloader menolak `fastboot boot`: flash, uji, dan siapkan TWRP lama
      untuk dipasang balik

**Penanda sukses:** `/sys/fs/pstore` **tidak kosong**. Isinya boleh apa saja —
yang dibuktikan di sini adalah backend ramoops hidup.

---

## 4. Risiko yang diakui

| Risiko | Dampak | Mitigasi |
|---|---|---|
| Kernel 18,3 MB vs offset ramdisk | recovery tidak boot | offset ke `0x02000000` (§1.1) |
| Region `0x9ff00000` tidak dicadangkan di DTS | pstore tetap kosong meski kernel benar | kalau Fase 3 gagal dengan pstore kosong, **inilah** tersangka utama — lihat catatan di `BoardConfig.mk` LOS |
| TWRP `android-9.0` vs kernel branch `lineage-21` | ketidakcocokan userspace↔kernel | recovery hampir tidak memakai API kernel modern; risiko rendah tapi tidak nol |
| `twrp-9.0` sudah tua (2019) | prebuilt/toolchain mungkin bermasalah | branch itu yang cocok dengan device tree; `android-5.1` jelas lebih buruk |
| Disk 35 GB | sync gagal di tengah | Fase 0 mengosongkan 77 GB lebih dulu |
| `fastboot boot` tidak didukung | harus flash, TWRP lama hilang sementara | unduh TWRP lama dulu sebagai jalan pulang |

## 5. Yang sengaja TIDAK dikerjakan

| | Alasan |
|---|---|
| TWRP 3.7 / `twrp-12.1` | device tree A37f hanya sampai `android-9.0`; memaksa base baru berarti menulis device tree recovery dari nol |
| Membangun kernel dari sumber di tree TWRP | Jalur B — hanya kalau kernel perlu dikecilkan |
| Menambah fitur TWRP (enkripsi, tema) | di luar tujuan; `TW_INCLUDE_CRYPTO := true` yang sudah ada dibiarkan apa adanya |
| Memakai dt.img TWRP dengan kernel kita | sha256-nya berbeda dari milik kita; mencampur DT satu build dengan kernel build lain menambah variabel tanpa alasan |
