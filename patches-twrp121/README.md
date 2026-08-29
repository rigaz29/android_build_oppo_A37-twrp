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
