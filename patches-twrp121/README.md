# Tambalan basis twrp-12.1

## 0001 — mkbootimg: dukung `--dt` (QCDT)

`system/tools/mkbootimg/mkbootimg.py` di AOSP 12 hanya menyediakan `--dtb`
(header v2). A37 memakai **format QCDT**: `dt.img` terpisah berisi tabel device
tree yang dipilih aboot saat boot. Tanpa tambalan ini build gagal di langkah
terakhir dengan `usage: mkbootimg ...` karena `--dt` tidak dikenal.

Tiga hunk, disalin dari `mkbootimg` LineageOS 23.2 yang dipakai membangun
`boot.img` A37 yang terbukti boot:

1. argumen `--dt`
2. offset 40 dipakai ganda — ukuran `dt.img` kalau `--dt` diberikan, kalau tidak
   `header_version`
3. `write_padded_file(args.output, args.dt, pagesize)` setelah `second`

Diff penuh antara kedua berkas 126 baris, tapi sisanya perbedaan GKI signing
antara Android 12 dan 16 — **sengaja tidak disalin**, menyalinnya akan merusak
hal lain.

Terverifikasi: `recovery.img` hasil build memuat **210944** di offset 40, persis
ukuran `dt.img`.

Repo hulu yang di-sync, jadi tambalan ini **hilang pada `repo sync` berikutnya**.

## 0002 — minuitwrp: blacklist masukan yang tahan soong

`TW_INPUT_BLACKLIST` **tidak pernah bekerja** pada basis 12.1. Pemeriksaan byte
pada `libminuitwrp.so` hasil build menunjukkan isinya:

```
b'"hbtp_vmlis3dh-accelcompasslightproximity"'
```

Pemisahnya hilang dan tanda kutip ikut masuk ke dalam string, sehingga
`strcmp(e->deviceName, blacklist)` di `events.cpp:253` tidak pernah cocok dan
seluruh perangkat tetap dibaca.

Sebabnya rantai penyandian yang berubah antara make dan soong:

| | Android.mk (basis lama) | Soong (12.1) |
|---|---|---|
| tanda kutip | dilucuti shell | dipertahankan, ikut ke dalam string |
| `\x0a` | escape C yang sah -> newline | **ditolak** parser JSON soong.variables |
| `\n` | escape C yang sah -> newline | jadi newline SUNGGUHAN, dilipat preprocessor |

Terlihat langsung di `out/soong/build.ninja`:

```
'-DTW_INPUT_BLACKLIST="hbtp_vm$
```

`$` itu pelolosan newline milik ninja — definisi makro menerima newline asli,
lalu preprocessor melipatnya menjadi satu kata.

Tambalan ini melucuti tanda kutip yang menempel dan memisah pada **koma maupun
newline**, sehingga kedua gaya penulisan tetap bekerja. Pasangannya di
`BoardConfig.mk`:

```
TW_INPUT_BLACKLIST := "hbtp_vm,lis3dh-accel,compass,light,proximity"
```

Terverifikasi di byte setelah tambalan:
`b'"hbtp_vm,lis3dh-accel,compass,light,proximity"'`, dan di log perangkat kelima
perangkat tercatat `I:Blacklisting input device: ...`.

**Kenapa penting:** `compass` melaporkan `ABS=7` yaitu `ABS_X`, `ABS_Y`, `ABS_Z`,
dan `events.cpp:510` menerjemahkan `ABS_X` langsung menjadi koordinat penunjuk
(`e->p.x = ev->value`). Magnetometer yang mengalir terus menyuntikkan sentuhan
palsu. `events.cpp:241-259` hanya mencocokkan NAMA perangkat — tidak ada
penyaringan berdasar kemampuan — jadi apa pun yang tidak diblokir ikut dibaca.

Repo hulu yang di-sync, jadi tambalan ini **hilang pada `repo sync` berikutnya**.

---

## Catatan: tambalan kernel TIDAK diarsipkan di sini

Backport AIO FunctionFS ada sebagai commit di
`rigaz29/kernel_oppo_msm8939` branch **`twrp-12.1`** (empat commit dari
acroreiser/a6010: poll ep0, aio support, dan dua perbaikan use-after-free yang
memperbaiki bug di kode aio itu sendiri). Repo itu milik sendiri dan tidak
tertimpa `repo sync`, jadi tidak perlu diarsipkan sebagai patch.

## 0003 — MTP: perbaiki open ganda `/dev/mtp_usb`

`MtpServer::run()` selalu gagal dengan `Failed to start usb driver!` di
perangkat ini. Sebabnya `/dev/mtp_usb` dibuka **dua kali**:

```
mtp_MtpServer.cpp:77   controlFd = open("/dev/mtp_usb", O_WRONLY);
MtpDevHandle::start()  mFd.reset(open(mtp_dev_path, O_RDWR));
```

`unique_fd::reset()` memang menutup fd lama, tapi argumennya — `open()` itu —
dievaluasi lebih dulu. Jadi open kedua terjadi selagi yang pertama masih
terbuka, dan driver `f_mtp` memakai kunci eksklusif:

```c
static int mtp_open(struct inode *ip, struct file *fp) {
	if (mtp_lock(&_mtp_dev->open_excl))
		return -EBUSY;
```

Terbukti langsung di perangkat: membuka `/dev/mtp_usb` dua kali menghasilkan
`Device or resource busy` pada yang kedua.

Tambalan ini melepas fd lama (`mFd.reset()`) sebelum membuka ulang dengan
`O_RDWR` yang memang dibutuhkan MTP untuk membaca maupun menulis.

**Terverifikasi di perangkat:** MTP berjalan, PC mendeteksi storage.

Perlu diketahui: TWRP memilih handle secara otomatis di `MtpServer.cpp:122`
berdasarkan keberadaan `/dev/usb-ffs/mtp/ep0`. Karena `etc/init.rc:149-153`
hanya me-mount instance functionfs `adb` dan `fastboot`, yang terpilih adalah
`MtpDevHandle` — jalur `/dev/mtp_usb`, yang memang cocok untuk kernel ini.

**JANGAN me-mount `/dev/usb-ffs/mtp`.** Gadget android kernel ini hanya punya
satu `struct functionfs_config` dengan satu `struct ffs_data *data`, dan
`functionfs_ready_callback()` menimpanya tanpa syarat. Instance FFS yang
menulis deskriptor terakhir menendang yang sebelumnya keluar dari gadget.

---

## 0004 — Lepaskan `ep0` adb sebelum mengganti komposisi USB

Setelah MTP berjalan, adb jatuh ke `offline` dan tidak pernah pulih.
Logcat dari perangkat menunjukkan mekanismenya persis:

```
02:09:58  adbd PID 276  opening control endpoint /dev/usb-ffs/adb/ep0
02:09:58  adbd PID 276  USB event: FUNCTIONFS_BIND
02:09:58  adbd PID 276  USB event: FUNCTIONFS_ENABLE
02:10:01  adbd PID 308  cannot open control endpoint ...: Device or resource busy
          (PID 308 mengulang tiap detik, selamanya)
```

Dua temuan:

1. **PID 276 tidak pernah menerima `FUNCTIONFS_UNBIND`.** `android_disable()`
   di `drivers/usb/gadget/android.c` TIDAK memanggil `functionfs_unbind`; ia
   bergantung pada adbd melepas `ep0` sehingga `ffs_ep0_release` memicu
   `functionfs_closed_callback` yang melakukan unbind. Commit CAF
   `ac76de240429` menyebut ketergantungan ini secara eksplisit. Artinya adbd
   secara struktural tidak bisa tahu gadget dirobohkan — ia harus dihentikan.

2. **`restart adbd` di init tidak cukup.** `restart` = `stop` lalu `start`
   tanpa menunggu, sehingga proses lama masih memegang `ep0` saat yang baru
   lahir. `ffs_ep0_open()` menolak selama `atomic_read(&ffs->opened)` belum
   nol. Pendekatan itu dicoba dan justru menciptakan balapan; dibatalkan.

Tambalan ini menambah `Release_ADB_FFS()` yang menghentikan adbd lewat
`ctl.stop` dan **menunggu** sampai `init.svc.adbd` tidak lagi `running`
(maksimal 5 detik), dipanggil di awal `Enable_MTP()` dan `Disable_MTP()`
sebelum `sys.usb.config` disentuh. Aturan init `start adbd` yang sudah ada
menyalakannya kembali setelah komposisi berganti, dengan `ep0` yang bebas.

**Terverifikasi berjalan, tapi kini DORMAN.** Panggilan `Release_ADB_FFS()`
berada di dalam blok `if (strcmp(old_value, "mtp,adb") != 0)`. Setelah 0005
menyetel komposisi `mtp,adb` sejak boot, blok itu tidak pernah dimasuki lagi.
Sengaja dipertahankan sebagai jaring pengaman kalau komposisi suatu saat
memang harus berganti saat adbd sudah berjalan.

Perlu dicatat: menghentikan adbd saja TIDAK cukup memperbaiki masalahnya —
lihat 0005 untuk sebab sebenarnya.

Repo hulu yang di-sync, jadi kedua tambalan ini **hilang pada `repo sync`
berikutnya**.

---

## 0005 — Komposisi USB `mtp,adb` sejak boot (INI YANG MENYELESAIKAN)

Dua berkas: `etc/init.rc` dan `etc/init.recovery.usb.rc`.

### Sebab sebenarnya: kebocoran referensi AIO

Pelacakan kernel (`kernel_oppo_msm8939` branch `twrp-12.1`) memberi jawabannya
dalam satu putaran, setelah lima percobaan berbasis penalaran meleset:

```
CLOSE ep0   (opened=3 sebelum) -> 2
CLOSE       (opened=2 sebelum) -> 1
(tutup ketiga TIDAK PERNAH datang)
ffs: ep0 open DITOLAK: state=2 opened=1 ref=4     <- berulang selamanya
```

`state=2` adalah `FFS_ACTIVE`, jadi penolakan datang dari
`atomic_read(&ffs->opened)` yang tidak nol — tepat SATU berkas masih terbuka,
padahal pemindaian `/proc/*/fd` menemukan **nol** pemegang di seluruh sistem.

Berkas yang hidup tanpa fd hanya bisa ditahan referensi kernel:
`io_submit()` mengambil `fget()` (`fs/aio.c:1110`) dan baru melepasnya saat
request selesai (`:542`). Antrean baca AIO adbd di `ep1` tidak pernah
diselesaikan ketika komposisi USB berganti, sehingga epfile-nya tertahan dan
setiap adbd baru ditolak `-EBUSY` selamanya.

**Ini regresi dari backport AIO FunctionFS kita sendiri.** Sebelum backport itu
adbd memakai jalur sinkron tanpa referensi menggantung — tapi backport itu
wajib, karena adbd AOSP 12 tidak punya jalur legacy sama sekali.

### Perbaikannya: hindari pemicunya

`Enable_MTP()` hanya memutar `sys.usb.config` kalau nilainya BELUM `mtp,adb`.
Dengan nilai itu disetel di `init.rc` sebelum adbd pertama kali berjalan,
pergantian komposisi tidak pernah terjadi saat adbd sudah mengikat endpoint —
adbd mengikat sekali, ke komposisi final.

Hasil terverifikasi di perangkat:

```
DITOLAK: 0        cannot open control endpoint: 0
CLOSE ep0 (3->2)  CLOSE ep2 (2->1)  CLOSE (1->0)  -> reset
OPEN  ep0 (->1)   OPEN  ep2 (->2)   OPEN  (->3)

pid=278 (adbd)     memegang ep0, ep1, ep2
pid=296 (recovery) memegang /dev/mtp_usb
```

### Jebakan: idProduct harus ikut berganti

`on fs` menulis `idProduct D001` — PID untuk adb **tunggal**. `Enable_MTP()`
biasanya menggantinya ke `4EE2` (`usb.product.mtpadb`,
`partitionmanager.cpp:2833`) saat memutar komposisi. Karena komposisi kini sudah
benar sejak boot, fungsi itu melewati seluruh bloknya — **termasuk penulisan
idProduct**.

Akibatnya perangkat mengumumkan PID adb-tunggal padahal menyajikan dua
antarmuka. Host mengikat driver berdasarkan VID/PID, tidak menemukan kecocokan
untuk antarmuka adb, dan perangkat muncul sebagai **TIDAK TERDETEKSI SAMA
SEKALI** di PC — bukan `offline`. Keadaan internal perangkat sepenuhnya benar;
hanya identitas yang diumumkan yang salah.

Karena itu aturan `mtp,adb` kini menulis `idProduct 4EE2`, dan aturan `adb`
menulis `D001` sebagai pasangannya.

Kalau PC masih kosong setelah flash: `adb kill-server` lalu `adb devices` —
driver Windows di-cache per VID/PID.

### Yang SENGAJA tidak diubah

`on fs` di `init.recovery.usb.rc` tetap menulis `functions adb`. Percobaan
sebelumnya mengubah baris itu bersamaan dengan `init.rc` dan gadget tidak naik
sama sekali — menulis komposisi `mtp,adb` ke sysfs pada tahap `on fs`, sebelum
`/dev/usb-ffs/adb` ter-mount, adalah tersangkanya. Cukup properti awal yang
disetel; aturan `on property:sys.usb.config=mtp,adb` yang menulis komposisinya.

Repo hulu yang di-sync, jadi tambalan ini **hilang pada `repo sync` berikutnya**.
