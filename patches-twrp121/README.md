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
