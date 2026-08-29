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

**BELUM diverifikasi di perangkat.** Mekanisme kegagalannya sudah pasti dari
logcat, tapi perbaikannya belum diuji.

Repo hulu yang di-sync, jadi kedua tambalan ini **hilang pada `repo sync`
berikutnya**.
