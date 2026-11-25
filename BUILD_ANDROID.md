# Build Android — Multiverse Dominion (APK dan AAB / Gradle)

**Godot yang dipakai: 4.7** (proyek diuji penuh di 4.7: semua tes lulus). Godot 4.3 masih bisa membuka proyek untuk uji lokal,
tetapi template Gradle 4.3 menargetkan API lama; sejak **31 Agustus 2026 Google Play mewajibkan target API 36 (Android 16)**,
dan template Gradle Godot 4.7 memang menargetkan API 36 (minSdk 24 = Android 7.0, sesuai spesifikasi).

## Apa yang sudah terbukti dan apa yang belum
| Terbukti di lingkungan pengembangan saya | Belum terbukti |
|---|---|
| **APK sungguhan dibangun** dengan Godot 4.7 (55 MB): paket `com.multiversedominion.game`, v0.7.0, **minSdk 24, targetSdk 36**, landscape, **hanya izin INTERNET (cek update)**, arm64-v8a + armeabi-v7a, bertanda tangan (v2/v3), ikon adaptif | APK dijalankan di perangkat Android nyata |
| Preset AAB (Gradle) valid: Godot menerima template 4.7, SDK, JDK 17, keystore, lalu menyusun proyek Android dan **memanggil Gradle** | Kompilasi Gradle sampai `.aab` selesai (jaringan lingkungan saya memblokir `services.gradle.org` dan repositori Maven) |
| Workflow GitHub: YAML valid, `actionlint` bersih, setiap blok shell dijalankan lokal dan hasilnya benar | Workflow dijalankan di server GitHub |
| Seluruh tes (logika, UI, tata letak 7 rasio layar, tutorial, performa) lulus di Godot 4.7 | Performa/sentuhan/suara di ponsel nyata |

## 1. Build di GitHub (paling mudah, tanpa memasang apa pun)
Folder ini sudah berisi `.github/workflows/`:
- `tests.yml`: tes headless di setiap push/PR + job `visual` (audit tata letak dan tutorial dengan renderer perangkat lunak).
- `build-android.yml`: pasang JDK 17 + Android SDK (platform 36, build-tools 36.1.0) + Godot 4.7 + template Android, jalankan tes, lalu
  ekspor **debug APK** (uji di ponsel) dan **debug AAB** (membuktikan jalur Play Store), dan, bila secrets ada, **release AAB + APK bertanda tangan**.

Langkah:
1. Buat repository GitHub, lalu dari DALAM folder `MultiverseDominion` (isi folder = akar repo; `project.godot` harus di akar):
   `git init && git add . && git commit -m "Multiverse Dominion" && git branch -M main && git remote add origin <url-repo> && git push -u origin main`
2. Tab **Actions** -> *Tests* berjalan otomatis.
3. Actions -> **Build Android (APK + AAB)** -> *Run workflow* (atau beri tag `git tag v0.7.1 && git push --tags`: file ikut terlampir di Releases).
   Run pertama lama (mengunduh template 1,3 GB dan dependensi Gradle); berikutnya memakai cache.
4. Unduh artifact `MultiverseDominion-android`: `MultiverseDominion-debug.apk` (pasang di ponsel: izinkan *sumber tidak dikenal* atau `adb install -r`).
5. Rilis bertanda tangan: Settings -> Secrets and variables -> Actions, tambahkan
   `RELEASE_KEYSTORE_BASE64` (`base64 -w0 upload.keystore`), `RELEASE_KEYSTORE_USER` (alias kunci), `RELEASE_KEYSTORE_PASSWORD`
   (password keystore dan kunci harus SAMA; Godot hanya mendukung satu password).
   Buat keystore sekali dan SIMPAN BAIK-BAIK (cadangan di luar GitHub):
   `keytool -genkeypair -v -keystore upload.keystore -alias upload -keyalg RSA -keysize 2048 -validity 10000`

Jika run pertama merah, kirim log langkah yang gagal.

## 2. Build di komputermu
1. Godot **4.7** + export template 4.7 (Editor -> Manage Export Templates), JDK 17, Android SDK:
   `sdkmanager "platform-tools" "build-tools;36.1.0" "platforms;android-36" "cmdline-tools;latest"`.
2. Editor -> Editor Settings -> Export -> Android: isi *Android SDK Path*, *Java SDK Path*, debug keystore
   (`keytool -keyalg RSA -genkeypair -alias androiddebugkey -keypass android -keystore debug.keystore -storepass android -dname "CN=Android Debug,O=Android,C=US" -validity 9999`).
3. **APK cepat** (template bawaan, tanpa Gradle): Project -> Export -> preset **Android** -> Export Project,
   atau `godot --headless --path . --export-debug "Android" build/MultiverseDominion-debug.apk`.
4. **AAB / Gradle** (untuk Play Store):
   - sekali saja: Project -> **Install Android Build Template**, atau `tools/install_android_template.sh 4.7.stable`
     (folder `android/build` ~200 MB; di `.gitignore`, jangan di-commit; versinya harus sama dengan versi editor);
   - Project -> Export -> preset **Android AAB (Play Store)** atau
     `godot --headless --path . --export-release "Android AAB (Play Store)" build/MultiverseDominion.aab`
     (butuh release keystore diisi di dialog Export atau lewat variabel lingkungan `GODOT_ANDROID_KEYSTORE_RELEASE_PATH/USER/PASSWORD`).
   Build Gradle butuh internet (mengunduh Gradle 8.11.1 dan Android Gradle Plugin 8.6.1).

Isi preset (`export_presets.cfg`): arm64-v8a + armeabi-v7a, GL Compatibility, landscape, tanpa izin apa pun, ikon di `assets/icons/`,
`tests/`, `tools/`, `docs/` tidak ikut paket. Versi aplikasi: `version/code` (naikkan 1 untuk SETIAP unggahan ke Play) dan `version/name`.

## 3. Checklist Google Play (di luar kode)
- Target API 36 (dipenuhi oleh Godot 4.7), format **AAB**, 64-bit (dipenuhi). Syarat Play berubah tiap tahun: cek halaman resmi "Target API level requirements".
- Akun Play Console; aktifkan **Play App Signing** (kunci yang kamu buat = *upload key*).
- Wajib diisi di Console: kebijakan privasi (game ini tidak mengumpulkan data dan tanpa izin, tetapi formulirnya tetap ada), Data safety,
  rating konten, kategori, deskripsi, tangkapan layar (ada contoh di `docs/screenshots/`), ikon 512x512, feature graphic 1024x500.
- Akun pribadi baru bisa diwajibkan menjalankan *closed testing* dengan sejumlah penguji sebelum produksi; cek kebijakan terbaru.
- Game memakai mode hemat CPU, tanpa iklan, tanpa pembelian: tidak ada SDK pihak ketiga.

## 4. Daftar uji di perangkat (tidak bisa diuji di sandbox)
- [ ] Terbuka landscape, tidak ada elemen terpotong (notch/punch-hole; `screen/immersive_mode` aktif).
- [ ] Notch / punch-hole di KIRI dan di KANAN: kartu profil menu utama, tombol zoom dan panel aksi Territory, dialog, tidak ada yang tertutup; coba slider Notch margin di Settings bila masih ada.
- [ ] Papan Territory: START di pojok kanan bawah, papan 100 petak dibuka dengan petak sebesar papan 40 petak, tombol Fit berganti ke 1:1 dan kembali.
- [ ] Tombol nyaman disentuh; papan wilayah: ketuk petak kecil (~3 mm) untuk info; bila sulit, beri tahu saya.
- [ ] **Back**: menu utama bertanya sebelum keluar; di match muncul konfirmasi; di duel tidak bisa keluar.
- [ ] Home saat bermain lalu buka lagi; matikan paksa lalu **CONTINUE** memulihkan match (autosave tiap awal giliranmu dan saat pause).
- [ ] Performa di perangkat kelas bawah: `adb shell dumpsys gfxinfo com.multiversedominion.game`; battle 4x.
- [ ] Memori: `adb shell dumpsys meminfo com.multiversedominion.game` (logika game ~18-26 MB di desktop).
- [ ] Suara terdengar dan bisa dimatikan di Settings (tes otomatis hanya memeriksa bentuk gelombang).
- [ ] Baterai/suhu setelah 20 menit; tablet 4:3; Android 7.0 (minSdk 24) bila punya perangkatnya.

## 5. Pengujian otomatis di desktop
```
GODOT=godot tools/run_tests.sh all        # 14 tes headless; exit code != 0 bila ada yang gagal
# butuh renderer nyata (Linux: xvfb), juga dijalankan di CI job "visual":
xvfb-run -a -s "-screen 0 1280x720x24" godot --path . --rendering-driver opengl3 --audio-driver Dummy \
  res://tests/layout_test.tscn -- strict shots      # screenshot ke /tmp/shots
```
Catatan: mode `--headless` memakai server teks dummy yang MENGGELEMBUNGKAN tinggi teks (~2x): jangan percaya audit tata letak di mode itu.

## Rilis otomatis dan update di dalam aplikasi
- Tiap push ke `main` -> workflow `Build Android` menjalankan tes, membangun APK/AAB, lalu membuat GitHub Release `v0.7.<nomor run>`
  berisi `MultiverseDominion.apk` dan `.aab`. `versionCode` = nomor run, jadi tiap build valid sebagai update build sebelumnya.
- Semua build harus memakai tanda tangan yang sama (`tools/debug.keystore`, atau keystore rilis bila secret diisi; ganti tanda tangan = uninstall sekali).
- Saat menu utama dibuka (Android, sekali per start; bisa dimatikan di Settings) game memeriksa Release terbaru. Jika versinya lebih baru,
  muncul dialog; "Download" membuka unduhan APK di browser, lalu pengguna membuka file itu untuk memasang. Android tidak mengizinkan
  pasang senyap tanpa Play Store atau plugin khusus. Perlu izin INTERNET (sudah diaktifkan di preset).
- Dialog update punya tiga pilihan: **Download**, **Later** (muncul lagi saat start berikutnya) dan **Skip this version** (diam sampai ada versi yang lebih baru).
  Jika start tanpa internet / kena rate limit GitHub, pengecekan diulang saat menu utama dibuka lagi (bukan menunggu start berikutnya).
- Settings -> **Check for updates now**: cek manual yang selalu memberi jawaban (terbaru / ada update / gagal) dan mengabaikan "skip".
- Repo yang dicek: konstanta `REPO` di `scripts/systems/update_check.gd`.
