# Tambalan TWRP 9.0 — arsip, TIDAK dipakai lagi

Dua tambalan ini dibuat saat mencoba membuat TWRP **9.0** mendekripsi `/data`
ber-FBE milik LineageOS 23.2. Keduanya **berfungsi sesuai maksudnya**, tapi
jalur 9.0 ditinggalkan setelah rujukan acroreiser twrp-12.1 menunjukkan jalan
yang jauh lebih bersih. Disimpan sebagai catatan, bukan untuk dipakai.

## 0001 — KeyStorage4: terima format kunci tanpa `stretching`

`retrieveKey()` di TWRP 9.0 gagal di baris pertama karena Android 11 ke atas
tidak lagi menulis berkas `stretching` maupun `salt`:

    Failed to read from /data/unencrypted/key/stretching
    e4crypt_initialize_global_de returned fail

Tambalan menganggap ketiadaan berkas itu sebagai `kStretch_none` (bukan
`kStretch_nopassword`), sehingga `appId = secdiscardable_hash + secret` —
rumus yang sama persis dengan vold Android 16 (`KeyStorage.cpp:421`), berlaku
untuk keadaan tanpa sandi maupun dengan PIN.

**Terbukti bekerja**: pesan `No stretching file; assuming modern key format
(none)` muncul di recovery.log, dan `retrieveKey` lanjut ke langkah berikutnya.

**TIDAK diperlukan di TWRP 12.1** — vold TeamWin android-12.1 sudah memakai
format kunci modern. `KeyStorage.cpp:74` di sana memuat komentar yang identik
dengan Android 16: "old key directories may contain a file named 'stretching'".

## 0002 — init.recovery.qcom.rc: jalankan hwservicemanager + keymaster

Setelah 0001, `retrieveKey` menggantung selamanya (`futex_wait_queue_me`)
karena tidak ada servis keymaster di recovery. Tambalan ini menambahkan
definisi servis dan rantai pemicu dua tahap lewat `hwservicemanager.ready`
supaya bebas balapan.

**Rantai pemicunya terbukti bekerja** — init mencatat
`processing action (hwservicemanager.ready=true)` lalu menjalankan keymaster.

**Tapi gagal di lapisan berikutnya**: `hwservicemanager` SIGABRT (kemungkinan
besar karena ramdisk TWRP 9.0 tidak punya manifest VINTF sama sekali),
`keymaster-3-0` exit 1, dan proses `recovery` sendiri ikut crash-loop 27 kali.

Pelajarannya: kode HIDL TWRP **menggantung** kalau hwservicemanager tidak ada,
tapi **abort** kalau ada lalu mati. Menghadirkan servis setengah jalan lebih
buruk daripada tidak sama sekali.

## Yang tidak diarsipkan

Biner keymaster (`android.hardware.keymaster@3.0-service` dengan interpreter
ELF ditambal ke `/sbin/linker`, impl, `libkeymaster3device.so`,
`libpuresoftkeymasterdevice.so`) — semuanya keluaran build yang bisa
dihasilkan ulang, dan TWRP 12.1 memakai keymaster **4.1 software** dari
`/system/bin`, bukan HAL vendor 3.0 dari `/sbin`.
