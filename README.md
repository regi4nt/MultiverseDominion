# MULTIVERSE DOMINION — Godot 4.2+ (GDScript)

Status: **PHASE 1 (Foundation) + PHASE 2 (Territory Board) + PHASE 3 (Card System) + PHASE 4 (Battle System) + PHASE 5 (Game Loop) + PHASE 6 (Content) + PHASE 7 (Android) — selesai di sisi kode; **APK belum dibangun/diuji di perangkat** (lihat BUILD_ANDROID.md).**
Diuji dengan Godot 4.3 headless: import bersih, 60 game AI penuh selesai, UI smoke test lolos.

## Menjalankan
1. Buka Godot 4.2+ -> Import -> pilih `project.godot` (biarkan import pertama selesai).
2. Tekan F5. Alur: Main Menu -> PLAY -> pilih mode / continent / faction / difficulty -> START MATCH.
3. Tes otomatis (tanpa UI):
   `godot --headless --path . res://tests/sim_test.tscn` -> harus mencetak `TEST RESULT: PASS`.
   `godot --headless --path . res://tests/ui_smoke.tscn` -> memainkan papan lewat scene asli.
   `godot --headless --path . res://tests/card_test.tscn` -> `CARD TEST RESULT: PASS` (Phase 3).
   `godot --headless --path . res://tests/ui_cards_smoke.tscn` -> `UI CARDS SMOKE: PASS`.
   `godot --headless --path . res://tests/battle_test.tscn` -> `BATTLE TEST RESULT: PASS` (Phase 4).
   `godot --headless --path . res://tests/ui_battle_smoke.tscn` -> `UI BATTLE SMOKE: PASS`.
   `godot --headless --path . res://tests/duel_test.tscn` -> `DUEL TEST RESULT: PASS` (Phase 5).
   `godot --headless --path . res://tests/ui_duel_smoke.tscn` -> `UI DUEL SMOKE: PASS`.
   `godot --headless --path . res://tests/content_test.tscn` -> `CONTENT TEST RESULT: PASS` (Phase 6).
   `godot --headless --path . res://tests/ui_content_smoke.tscn` -> `UI CONTENT SMOKE: PASS` (7 benua di UI).
   Juga: `tutorial_test`, `audio_test`, `rules_test` (Auction, Special Dice, unlock), `save_test`, `perf_test`, `ui_resume_smoke`; dan
   `ui_tutorial_smoke` + `layout_test` (butuh render nyata, lihat BUILD_ANDROID.md bagian 4).

## Cara bermain (Phase 2)
- Roll Dice (2xD6). Double / event "Time Surge" = lempar lagi (maks 2 bonus).
- Reroll Token: ulang lemparan sebelum bergerak (beli di Shop / event / passive Elarion).
- Wilayah kosong: beli. Wilayah lawan: bayar Tax (rent). Mayoritas region (6/10) x1.5, Regional Dominion (10/10) x2.5.
- Portal aktif (ungu) memindahkan ke portal aktif lain; portal berpindah tiap akhir ronde penuh.
- Bangkrut = jual wilayah otomatis; jika tetap kurang -> -1 Life + bailout. Life 0 = tereliminasi.
- Menang: lawan habis, atau ronde 40 -> net worth tertinggi.
- Ketuk petak mana pun di papan untuk info detail.

## Sistem kartu (Phase 3)
- `data/cards.json`: 15 tipe unit (8 Pawn, 2 Rook, 2 Knight, 2 Bishop, 1 Queen) + 21 Support (3 per kategori x 7 kategori).
- Deck = 15 tipe x 9 salinan (135) + 1 Champion + 15 Support = **151 kartu** (`Deck.validate()`).
- Upgrade bintang otomatis (`UnitRoster`): 3 salinan = 2 bintang, 9 salinan = 3 bintang (stat dari `balance.json`).
- Kapasitas catur (`CapacitySystem`): Pawn 1, Rook/Knight/Bishop 2, Queen 4, King 6; level 3 = 9 ... level 10 = 30.
  Asumsi: King/Champion tidak dihitung ke kapasitas deploy (hanya masuk saat Last Stand) — konfirmasi di Phase 4.
- `BattleDeck`: tumpukan 135 kartu untuk Battle Shop (5 kartu per refresh, sisa kembali ke tumpukan).
- Main Menu -> Card Collection (filter, detail, stat 1/2/3 bintang) dan Deck Builder (pilih Champion + tepat 15 Support, simpan ke save).
- Koleksi awal: semua unit x9 dan 15 dari 21 Support; 6 Support terkunci (cara membuka: tiap kemenangan membuka satu Support terkunci, lihat "Aturan tambahan").

## Battle System (Phase 4) — Main Menu -> Battle Practice
- Grid 8x8; kamu di baris 4-7 (area 4x8), lawan di baris 0-3. Tanpa kontrol manual: semua unit bergerak/menyerang sendiri.
- Persiapan (`BattlePrep`): Battle Shop 5 unit, Reroll, Buy/Sell, Level Up (kapasitas 9 -> 30), Preparation Area 10 slot,
  Deploy/Return (ketuk unit lalu ketuk petak), Auto Deploy. Satu mata uang (Dominion Gold); "budget" hanya batas belanja.
- Engine (`BattleEngine`, deterministik per seed): 1 tick = 0.25 detik; prioritas target per role (Assassin = HP terendah,
  Marksman/Mage = musuh terlemah dalam jangkauan, lainnya = terdekat), range Chebyshev, gerak BFS 8 arah,
  15 skill unit, Faction Synergy (2 unit sefaksi +5%, 4 = +15%, 6 = +30% HP/ATK).
- **Champion Last Stand**: Champion hanya masuk arena saat semua unit biasa pihaknya kalah (dan langsung masuk jika tanpa unit),
  lalu memakai skill aktifnya. Champion kalah = pihak itu kalah. HP Champion di battle = HP x3 (`champion_hp_mult`).
- Support card yang sudah berfungsi: Fireball (area_damage), Arcane Heal (heal_all), Battle Cry (team_atk),
  Blessing of Light (shield_all), Summon Recruits (summon_pawns), Fortune's Favor (gold_on_win). (Catatan lama: sejak Phase 6 SEMUA 21 efek Support berfungsi.)
- Lawan AI membangun pasukan lewat shop yang sama (budget easy 250 / normal 450 / hard 700) dan memakai Support.
- Diuji: 90 pertarungan AI-vs-AI selesai (terlama 85 tick), tanpa tumpang-tindih sel, aturan Last Stand tidak pernah dilanggar,
  tidak ada bias sisi (43/47), seed sama = hasil sama.

## Game Loop (Phase 5) — Territory Encounter & Duel
- Berhenti di wilayah lawan -> **pemilik** memilih **Tax** atau **Duel** (UI menampilkan tombol untuk pemain yang berhak menjawab).
- Pemilik memilih Duel -> pengunjung boleh **Accept** atau **Refuse** (bayar rent + penalti `refuse_duel_penalty`, bisa diatur di `balance.json`).
- Duel = auto battle 8x8 antar **pasukan permanen** pemain: unit yang dibeli dengan Dominion Gold tetap dimiliki antar duel.
  Persiapan duel memakai batas belanja `battle_budget_ratio` (50% gold) untuk manusia; AI memakai rasio per tingkat kesulitan.
  Duel yang melibatkan pemain manusia tampil sebagai overlay Battle; duel AI vs AI diselesaikan instan (hasil masuk log).
- Penyerang menang -> **Conquest** (ambil wilayah) atau **Victory Reward** (gold = 75% harga wilayah, wilayah tetap).
- Pemain yang kalah duel kehilangan 1 Life (spesifikasi bagian 6). Jika penyerang kalah: wilayah tetap. Jika pemilik kalah: penyerang
  memilih Conquest/Reward. `defender_loses_life=false` mengembalikan aturan "hanya penyerang yang kehilangan Life" (bagian 12).
  Life 0 = tereliminasi. Heal Life lewat Territory Shop (`heal_price`).
- AI memutuskan Tax/Duel/Accept/Refuse dari estimasi kekuatan pasukan (`BattleAI.army_power`), jumlah Life, dan tingkat kesulitan.
- Pemenang game: pemain terakhir yang hidup, atau net worth tertinggi di ronde 30 (`max_rounds`).

## Tuning keseimbangan (`tools/balance_report`)
Alat ukur: `godot --headless --path . res://tools/balance_report.tscn -- games=600 mode=mixed seed_base=300 rent_rate=0.4`
(kunci numerik/boolean apa pun di `data/balance.json` bisa di-override per-run; kunci bertingkat: `ai_battle_budget_ratio.normal=0.2`).
Mode: `mixed` (semua Normal), `skill` (kursi 0 Hard vs 3 Easy), `skill_rev` (kursi 0 Easy vs 3 Hard).
Hasil akhir (600 game AI, ronde 30): win rate per kursi 25.5 / 23.8 / 24.7 / 26.0%; per faction 22-27% (ideal 25%);
Hard vs 3 Easy menang 53.5% (sebelum limit 30 ronde: 69%); 7.7 duel/game, penyerang menang 45%; tanpa game yang macet.
Perubahan dari baseline (yang berakhir 0 eliminasi dan hanya 1.9 duel/game): harga wilayah 60 + 12/urutan, rent 40%, tax 100,
AI menantang/menerima duel lebih berani (`ai_owner_duel_ratio` 0.8, `ai_visitor_accept_ratio` 0.6), penalti tolak duel 150,
belanja militer AI 10/20/30% gold, heal 300, batas ronde 30. Temuan: eliminasi total sulit karena heal dan Life 3;
ekonomi yang terlalu ketat justru mengurangi kepemilikan tanah sehingga encounter jarang.

## Android (Phase 7) - lihat BUILD_ANDROID.md
- Tombol Back (`AppNav`): tidak pernah menutup aplikasi; menu utama bertanya dulu, match menampilkan konfirmasi, duel tidak bisa ditinggalkan.
- **Simpan dan lanjutkan match**: autosave di awal tiap giliran manusia dan saat aplikasi di-pause (`user://match.json`, tulis
  lewat file sementara; file korup/versi asing dibuang tanpa crash). Tombol **CONTINUE** di menu. Terbukti deterministik:
  match yang dipulihkan berjalan identik dengan aslinya sampai selesai (3 benua).
- Layar: audit tata letak di 7 rasio (16:9, 18:9, 20:9, 21:9, 16:10, 4:3, 5:3): 0 kontrol keluar layar, semua tombol >= 48 px
  (minimum global 52 px). Dua bug nyata ditemukan dan diperbaiki lewat audit ini: panel persiapan battle terlalu tinggi
  (board terpotong di 720 px) dan HUD tidak memakai lebar ekstra di layar lebar. Screenshot ada di `docs/screenshots/`.
- Performa (desktop; ponsel kelas bawah ~5-10x lebih lambat): tick battle terburuk 1.3 ms (timer 250 ms), satu game AI penuh 76 ms,
  satu duel AI instan <= 13 ms, memori logika ~18 MB, 0 kebocoran setelah 40 game dan 75 siklus buat/hapus scene.
  `low_processor_mode` aktif (hemat baterai), max FPS 60, renderer GL Compatibility.
- Ekspor: `export_presets.cfg` (arm64-v8a + armeabi-v7a, tanpa permission, tests/tools dikecualikan); paket data 218 KB (95 file)
  berjalan dari luar folder proyek tanpa error.

## Konten (Phase 6)
- **7 benua dapat dimainkan**, masing-masing 4 regional bernama, 10 awalan nama wilayah, 4 faction, dan 1 world modifier.
  Menu: Settings -> "Unlock all" untuk membuka semua benua/faction saat uji; di mode normal, menang di sebuah benua membuka benua berikutnya.
- **28 Champion berbeda** (`data/champions.json`): 10 passive papan x 11 skill aktif Last Stand, nilai tiap Champion beda dan dibaca dari data
  (`passive_value`, `active_value`). Passive: Royal Treasury, Shadow Ledger, Landlord, Fortune Weave, Toll Keeper, Treasure Hunter,
  Spoils of War, Quartermaster, Mender, Vanguard. Aktif: Sun Judgment, Starfall Decree, Eclipse Veil, Banner of Iron, Inferno Burst,
  Chrono Stasis, Soul Drain, Frost Veil, Overcharge, Rift Strike, Life Surge.
- **World modifier** (`WorldMods`): Aetherion Royal Tithe (+50 START), Arcanum Arcane Conduits (8 portal aktif), Machina Industrial Age (rent +25%,
  harga shop -20%), Sylvaris Bountiful Harvest (+6 G per wilayah per ronde), Drakmor War Fever (ATK battle +15%, pemenang duel +60 G),
  Thalassia Sea Trade (tax setengah, Reroll Token 40 G), Eclipsia Time Fold (+1 Reroll Token tiap lewat START, bonus roll maks 3).
- **Kartu**: 15 arketipe unit dipakai semua benua; tiap kartu punya "slot" faksi sehingga di benua lain ia milik faksi benua itu
  (nama diawali nama faksi, mis. "Ferrum Royal Guard"). Faction Synergy ikut berubah. Nama unik per benua masih TODO; ilustrasi kini prosedural (lihat "Seni dan audio").
- **Semua 21 efek Support berfungsi.** Efek yang butuh target (Crown of Valor, Aegis Shield, Windboots) memilih target otomatis
  (unit terkuat / tertangguh) - TODO: pilih target manual. Mercenary Pact dan Merchant Contract bekerja otomatis di fase persiapan.
- Penyetelan konten: win rate tiap faction di 7 benua berada di kisaran 22-27% (ideal 25%) pada 400-700 game AI per benua.

## Struktur
- `data/` balance.json (semua angka ekonomi), continents.json (7 benua / 28 faction), champions.json, events.json
- `scripts/managers/` GameData, SaveManager (user://save.json), GameSession (autoload)
- `scripts/entities/` BoardTile, PlayerState
- `scripts/systems/` BoardBuilder (100 petak), DiceSystem, PortalSystem, EconomySystem, EventSystem, MatchController (aturan permainan)
- `scripts/ai/ai_controller.gd` AI Easy/Normal/Hard
- `scripts/ui/` tema, menu, setup, BoardView (digambar dengan _draw), layar Territory Board
- `tests/` sim_test, ui_smoke

## Export Android (Phase 7, belum diuji di perangkat)
Project > Export > Android; renderer sudah GL Compatibility, orientasi landscape. Butuh Android SDK + JDK + keystore.

- **Build di GitHub dan Gradle/AAB**: `.github/workflows/` (tes otomatis + APK + AAB, Godot 4.7); lihat BUILD_ANDROID.md. Skrip tes: `tools/run_tests.sh`. Proyek kini memakai Godot 4.7 (target API 36 untuk Google Play).

## Tutorial, Auction, Special Dice, seni, audio, kartu baru
- **Tutorial** (menu utama): match 1v1 melawan AI Easy di Aetherion, 10 ronde, seed tetap. AI sudah memiliki wilayah di depan pemain dan
  tawaran duel pertama selalu muncul. `TutorialGuide` menjelaskan tiap aturan saat pertama kali muncul (panel petunjuk di papan; tips
  di atas separuh papan musuh saat persiapan duel). Hasilnya tidak dihitung ke statistik; `profile.tutorial_done` disimpan.
- **Auction sungguhan**: lot acak dilelang ke semua pemain hidup, mulai dari yang mendarat; buka 40% harga, naik 10% per tawaran;
  yang pass atau tak mampu keluar; AI menaksir lot dari harga, region yang dilengkapi, dan tingkat kesulitan.
- **Special Dice** (4 jenis x 6 sisi, `data/special_dice.json`): Swift (bonus gerak), Fortune (gold), Warp (teleport, menggantikan lemparan),
  Order (lempar ekstra / lawan berikutnya lewat giliran / token / gold). Sumber: kartu Event dan Territory Shop (120 G); maks 3 dibawa; dipakai
  sebelum melempar. AI memakainya. Tersimpan di save. (Sumber dari Champion dan Rule Card belum ada.)
- **Kartu baru**: tiap kemenangan membuka satu dari 6 Support yang terkunci (urutan tetap). Pool unit baru belum ada.
- **Seni prosedural** (`Art`, `PortraitView`; tanpa file gambar): siluet 6 bidak catur, 7 lambang benua, 7 ikon kategori Support, potret perisai
  Champion. Dipakai di kartu, token battle, dan pemilihan Champion. Galeri: `docs/screenshots/art_gallery.png`.
- **Audio** (`Sfx`): 11 efek suara disintesis dari kode (klik, dadu, koin, pukulan, gugur, sihir, portal, menang/kalah, dll), bisa dimatikan di Settings.
  Belum ada musik.
- **Animasi battle**: gerak halus antar petak, lunge saat menyerang, angka damage melayang, cincin saat unit gugur; mengikuti kecepatan 1x/2x/4x.

## TODO (tidak berpura-pura selesai)
- Pool kartu unit baru (varian pengganti) dan Champion/Rule Card sebagai sumber Special Dice.
- Nama dan ilustrasi unik per benua/Champion (seni sekarang prosedural dan generik); sprite dan animasi unit sungguhan.
- Musik latar; suara masih sintetis sederhana.
- Multiplayer (1v1, 2v2, FFA online, Ranked, Lobi, Turnamen) dan Story Campaign: belum ada.
- Pemilihan target manual untuk kartu Artifact (Crown of Valor, Aegis Shield, Windboots).
- Uji di perangkat Android nyata (lihat BUILD_ANDROID.md).
- Keseimbangan: eliminasi total jarang (3-4%); game biasanya diputuskan net worth di ronde 30. Diukur per benua dengan `tools/balance_report`.
