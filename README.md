# MULTIVERSE DOMINION — Godot 4.2+ (GDScript)

Status: **PHASE 1 (Foundation) + PHASE 2 (Territory Board) + PHASE 3 (Card System) + PHASE 4 (Battle System) + PHASE 5 (Game Loop) + PHASE 6 (Content) + PHASE 7 (Android) — selesai di sisi kode; **APK belum dibangun/diuji di perangkat** (lihat BUILD_ANDROID.md).**
Diuji dengan Godot 4.3 headless: import bersih, 60 game AI penuh selesai, UI smoke test lolos.

## Menjalankan
1. Buka Godot 4.2+ -> Import -> pilih `project.godot` (biarkan import pertama selesai).
2. Tekan F5. Alur: Main Menu -> NEW MATCH -> pilih OFFLINE (Journey / Arena / Battle Chess / Tutorial) -> untuk Journey dan Arena: pemain / difficulty / continent -> START MATCH (faksi diambil dari Deck) (lihat bagian "New Match").
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
   Juga: `tutorial_test`, `audio_test`, `rules_test` (Auction, Special Dice, unlock), `team_test` (mode 2vs2), `save_test`, `perf_test`, `ui_resume_smoke`; dan
   `ui_tutorial_smoke` + `layout_test` (butuh render nyata, lihat BUILD_ANDROID.md bagian 4).

## Shop (Main Menu -> Shop, di atas Profile)
- Mata uang: **Aether Coins** (disimpan di save, mulai 600). Menang match +150, kalah +50 (`ShopSystem`).
- Tab **Gacha**: Pull x1 = 100, Pull x10 = 900 (10 kartu, minimal 1 Rare). Rate: Common 60 / Rare 28 / Epic 10 / Legendary 2 (%).
  Pity: Epic atau lebih dijamin paling lambat pull ke-30. Kartu duplikat diubah jadi **Card Fragment** (Common 10, Rare 25, Epic 60, Legendary 150), disimpan di save (`wallet.fragments`) dan ditampilkan di header Shop.
- Tab **Buy Cards**: beli langsung Support yang masih terkunci (filter per kategori). Harga: Common 200, Rare 500, Epic 1200, Legendary 3000.
  Atau **tukar dengan fragment** lewat tombol *Exchange* di panel yang sama: makin langka kartunya makin banyak fragment (Common 50, Rare 150, Epic 400, Legendary 1000; `ShopSystem.exchange`).
- Tes: `godot --headless --path . res://tests/shop_test.tscn` -> `SHOP TEST RESULT: PASS`; `ui_shop_smoke.tscn` -> `UI SHOP SMOKE: PASS`.

## Cara bermain (Phase 2)
- Roll Dice (2xD6). Double / event "Time Surge" = lempar lagi (maks 2 bonus).
- Reroll Token: ulang lemparan sebelum bergerak (beli di Shop / event / passive Elarion).
- Wilayah kosong: beli. Wilayah lawan: bayar Tax (rent). Mayoritas region (6/10) x1.5, Regional Dominion (10/10) x2.5.
- Portal aktif (ungu) memindahkan ke portal aktif lain; portal berpindah tiap akhir ronde penuh.
- Bangkrut = jual wilayah otomatis; jika tetap kurang -> -1 Life + bailout. Life 0 = tereliminasi.
- Menang: lawan habis, atau ronde 40 -> net worth tertinggi.
- Ketuk petak mana pun di papan untuk info detail.

## New Match (menu utama -> NEW MATCH)
Satu scene (`scripts/ui/match_setup.gd`) dengan dua tampilan. Tombol Back / Esc / tombol Back Android: dari setup kembali ke hub, dari hub ke menu utama.
- **Hub**: dua tab. **OFFLINE** berisi 4 kartu: **Journey**, **Arena**, **Battle Chess**, **Tutorial**. **ONLINE - COMING SOON** berisi **Classic**, **Ranked**, **Battle Chess**
  (kartu redup dan nonaktif, belum ada multiplayer). Di layar tinggi (tablet) tinggi kartu dibatasi dan dipusatkan (`CARD_MAX_H`).
- **Journey** (Story, selalu 1 vs 1): hanya benua pertama (Aetherion) yang terbuka di awal, benua lain **terkunci**. Menang di sebuah benua dengan **masing-masing dari 4 faksi benua itu**
  (faksi = King di Deck, jadi ganti faksi di Deck lalu menang lagi) membuat benua itu **mastered**. Setiap benua mastered memberi **satu hak memilih** salah satu benua terkunci
  (bebas benua mana saja, bukan berurutan): setup Journey menampilkan "Tap to unlock" di benua terkunci, lalu konfirmasi. Satu hak = satu benua; benua baru itu harus di-master untuk hak berikutnya.
  Faksi dari benua lain tidak dihitung untuk mastery benua ini (hint di setup menjelaskannya). Baris benua menampilkan "Factions won 2 / 4" atau "Mastered"; layar hasil menulis kemajuannya.
  Logika di `SaveManager`: `journey_won_factions`, `is_journey_cleared` (= mastered), `journey_picks_available`, `choose_continent`, `journey_frontier`; key save `journey_wins` (continent -> faksi yang menang).
- **Arena**: match bebas melawan AI di benua yang sudah terbuka. Players: **1 vs 1**, **2 vs 2**, **4 Player**. **Tidak membuka benua** (kemenangan tetap memberi koin, statistik, dan kartu Support).
  Flag `journey` ikut di config match (`GameSession.category`) dan di save/resume (`MatchController.journey`); `SaveManager.record_match(..., journey)` hanya membuka benua jika `journey` true.
- **Faksi tidak dipilih di New Match.** Kolom kanan setup hanya menampilkan faksi + King dari Deck (read-only) dan tombol **Change faction in Deck**
  (membuka Collection & Deck -> Deck -> tab Faction; Back kembali ke New Match lewat `GameSession.collection_return`, `open_deck_tab`).
- **Faksi dipilih di Deck**: tab **Faction** (dulu "King") di Collection & Deck menampilkan 28 faksi per benua. Faksi dari benua yang belum terbuka **terkunci** (tombol nonaktif,
  "Locked - unlock X in Journey") dan tidak bisa dipilih; faksi 4 benua yang terbuka bisa dipilih. Faksi terkunci terbuka otomatis saat benuanya dibuka lewat Journey.
  King pilihan = faksi pemain di setiap match dan di Battle Chess (`SaveManager.player_champion_id()` / `player_faction_id()`; King dari faksi terkunci di save lama jatuh kembali ke faksi terbuka pertama).
  Faksi pemain boleh dari benua lain daripada benua match (musuh AI tetap dari faksi benua match); `GameData.find_faction` mencari di semua benua.
- **Aturan home-continent** (`GameData.is_home_faction`): faksi tidak dibatasi benua dan bisa dimainkan di benua lain (hanya di luar Journey, mis. Arena; faksi tetap harus sudah terbuka).
  Bonus faksi hanya aktif jika faksi dimainkan di **benua asalnya** (seluruh bidak dek = benua yang sama): **buff King** baru (`data/king_buffs.json`, 28 buff, dipasang saat King masuk Last Stand di `BattleEngine._enter_king`), **buff kartu unit** (`card_buffs.json`, dimatikan di `BattleEngine._spawn_unit` lewat `_home_bonus`) dan **Faction Synergy** 2/4/6 unit. Kartu unit dek selalu milik faksi benua yang dimainkan, jadi Faction Synergy otomatis terikat benua;
  `BattleEngine._synergy` dan panel Synergy juga menolak faksi non-home sebagai pengaman (mis. bidak shared milik King asing).
  Di benua asing faksi tetap bisa main, tanpa buff King, tanpa buff kartu, dan tanpa Faction Synergy (passive King tetap aktif di mana pun) untuk faksi itu (Role Synergy dan modifier benua tidak terpengaruh).
  **Journey wajib faksi asal**: tombol START MATCH nonaktif jika faksi di Deck bukan faksi benua Journey. Setup menampilkan catatan status bonus.
- **Battle Chess**: membuka scene Battle (sebelumnya tombol "Battle Practice"). **Tutorial**: match panduan seperti sebelumnya.
- Perubahan perilaku: sebelumnya kemenangan di mode apa pun membuka benua berikutnya secara berurutan; sekarang hanya Journey, lewat mastery dan pilihan pemain. Benua yang sudah terbuka di save lama tetap terbuka (tetapi tidak memberi hak pilih; kemenangan lama tidak tercatat per faksi).
- Tes: `godot --headless --path . res://tests/newmatch_test.tscn` -> `NEW MATCH TEST RESULT: PASS` (aturan unlock, config, hub, setup). `tests/layout_test` ikut memeriksa hub (offline / online) dan setup Arena / Journey di 7 rasio layar.
  Screenshot untuk review: `xvfb-run godot --path . res://tests/newmatch_shots.tscn` menulis PNG ke `/tmp/shots`.

## Mode 2vs2 (tim, New Match -> Offline -> Arena -> Players)
Pilihan Players di Arena: **1 vs 1 (You vs 1 AI)**, **2 vs 2 (You + 1 AI vs 2 AI)**, dan **4 Player (free-for-all vs 3 AI)**.
- 4 pemain, 2 tim: **Team A** = Anda (kursi 0) + sekutu AI (kursi 2, bernama "(Ally)"); **Team B** = 2 AI (kursi 1 dan 3). Giliran bergantian A, B, A, B.
  Kartu pemain menampilkan tag `[A]` / `[B]`. Tiap pemain tetap punya Life, gold, wilayah, dan pasukan sendiri.
- **Sekutu**: mendarat di wilayah sekutu = gratis (tanpa rent, tanpa Encounter/Duel). Tribute (Grand Festival, Special Tribute) hanya memungut dari lawan,
  dan Order Die "skip next" tidak pernah mengenai sekutu. Rent, Majority, dan Regional Dominion tetap dihitung per pemilik (wilayah tim tidak digabung).
- **Lawan**: aturan lama berlaku penuh (rent, Tax atau Duel, Conquest, Auction). AI tidak menawar melawan sekutu di Auction dan tidak menghitung sekutu sebagai pesaing.
- **Menang**: seluruh pemain tim lawan tereliminasi, atau saat batas ronde tim dengan **net worth gabungan** (pemain yang masih hidup) terbesar menang.
  Jika Anda tereliminasi tetapi sekutu masih hidup, match berlanjut (AI yang bermain); kalah hanya jika seluruh Team A habis atau Team B lebih kaya di akhir.
- Menang/kalah dicatat untuk tim Anda (profil, unlock benua, hadiah), sama seperti mode lain. Save/resume menyimpan tim.
- Kode: `MatchController` (`team_mode`, `is_ally`, `team_networth`, `human_won`), `AIController`, `match_setup.gd`, `territory_board.gd`; tes: `tests/team_test.tscn`.

## Sistem kartu (Phase 3)
- `data/cards.json`: per dek 15 tipe unit (8 Pawn benua + 7 bidak milik faksi: 2 Rook, 2 Knight, 2 Bishop, 1 Queen) + 105 Support (15 per kategori x 7 kategori).
- Deck = 15 tipe x 9 salinan (135) + 1 Champion + 15 Support = **151 kartu** (`Deck.validate()`).
- Upgrade bintang otomatis (`UnitRoster`): 3 salinan = 2 bintang, 9 salinan = 3 bintang (stat dari `balance.json`).
- Kapasitas catur (`CapacitySystem`): Pawn 1, Rook/Knight/Bishop 2, Queen 4, King 6; level 3 = 9 ... level 10 = 30.
  Asumsi: King/Champion tidak dihitung ke kapasitas deploy (hanya masuk saat Last Stand) — konfirmasi di Phase 4.
- `BattleDeck`: tumpukan 135 kartu untuk Battle Shop (5 kartu per refresh, sisa kembali ke tumpukan).
- Main Menu -> Collection & Deck: satu layar dengan dua tab. Tab Collection (filter, detail, stat 1/2/3 bintang) dan tab Deck (pilih Champion + tepat 15 Support, simpan ke save).
- Koleksi awal: semua unit x9 dan 15 dari 105 Support; 90 Support terkunci (cara membuka: tiap kemenangan membuka satu Support terkunci, lihat "Aturan tambahan").

## Deck (Main Menu -> Collection & Deck -> tab Deck)
- Editor bergaya Clash Royale: **deck sebagai kartu visual di kiri** (grid 3 x 5, lencana biaya capacity di tiap kartu, "avg cost" di judul) dan **koleksi di kanan** (5 kolom).
  Tab: **Units n / 15** (filter per faksi), **Support n / 15** (filter per kategori), **Faction** (kartu faksi per benua dengan gaya yang sama; panel kiri menampilkan King terpilih + skill-nya; faksi terkunci diberi overlay LOCKED).
  Ketuk kartu koleksi untuk memasang (kartu yang sudah di deck tampak redup; ketuk lagi untuk melepas). Jika deck penuh, kartu itu "dipegang" dan semua slot menyala emas:
  ketuk satu kartu deck untuk menukarnya. Ketuk kartu di deck tanpa memegang kartu = melepasnya. Tooltip menampilkan skill/deskripsi.
- **Kartu Unit mengikuti benua**: di tab Units, chip benua muncul begitu ada lebih dari satu benua terbuka (benua terkunci disembunyikan); yang bisa dipasang = 8 Pawn + 28 bidak dari 4 faksi benua itu. Faksi **boleh dicampur** selama
  satu benua. Tiap benua punya susunan unit sendiri (disimpan per benua). Tiap tipe unit = 9 salinan (15 x 9 = 135).
- **King tidak terikat benua** (semua 28 King bisa dipilih) dan Support dipakai bersama semua benua. Total dek tetap 151 kartu.
- Save hanya aktif jika 15 unit + 15 support terisi. "Reset to default" mengembalikan unit bawaan faksi King.
- Di match, kartu unit = susunan benua yang dimainkan; King mengikuti faksi yang dipilih di Deck; di Battle Chess (Battle Practice) King mengikuti pilihan di dek.
  Lawan AI tetap memakai dek bawaan faksinya.

## Battle System (Phase 4) — Main Menu -> New Match -> Offline -> Battle Chess (dulu "Battle Practice")
- Grid 8x8; kamu di baris 4-7 (area 4x8), lawan di baris 0-3. Tanpa kontrol manual: semua unit bergerak/menyerang sendiri.
- Persiapan (`BattlePrep`): Battle Shop 5 unit, Reroll, Buy/Sell, Level Up (kapasitas 9 -> 30), Preparation Area 10 slot,
  Deploy/Return (ketuk unit lalu ketuk petak), Auto Deploy. Satu mata uang (Dominion Gold); "budget" hanya batas belanja.
- Engine (`BattleEngine`, deterministik per seed): 1 tick = 0.25 detik; prioritas target per role (Assassin = HP terendah,
  Marksman/Mage = musuh terlemah dalam jangkauan, lainnya = terdekat), range Chebyshev, gerak BFS 8 arah,
  15 skill unit, Faction Synergy (2 unit sefaksi +5%, 4 = +15%, 6 = +30% HP/ATK) dan Role Synergy (2 unit semisi role +8%, 4 = +20%, 6 = +35%; Tank/Support = HP, Assassin/Mage/Marksman = ATK, Fighter/Controller = HP+ATK 60%).
- **Champion Last Stand**: Champion hanya masuk arena saat semua unit biasa pihaknya kalah (dan langsung masuk jika tanpa unit),
  lalu memakai skill aktifnya. Champion kalah = pihak itu kalah. HP Champion di battle = HP x3 (`champion_hp_mult`).
- **King di battle punya tiga hal terpisah**: **Pasif** (`data/king_passives.json`, aktif sejak battle mulai di benua mana pun: +HP/+ATK/-damage/shield untuk semua unit, atau +HP/+ATK King saat masuk); **Buff** (`data/king_buffs.json`, hanya di benua asal, melekat pada King saat masuk); **Aktif** = skill King
  (Sun Judgment, Starfall Decree, dst.) yang dipakai **manual, sekali** lewat tombol di panel King (kiri) setelah King masuk lewat Last Stand. Sisi AI / auto memakainya otomatis saat masuk.
  Engine: `manual_king` di cfg, `can_use_king_skill`, `use_king_skill`, `king_skill_used`; tes di `battle_test` (`_test_manual_king`).
- **Support di Battle Shop**: kartu Support dari Deck **muncul di roll Battle Shop** bersama bidak (tiap slot ada peluang `shop_support_chance` = 20%), tidak lagi dibagikan acak 3 kartu.
  Dibeli dengan gold (`support_price`: Common 40, Rare 100, Epic 220, Legendary 450) dan **butuh level** (`support_level_req`: Common 3, Rare 5, Epic 7, Legendary 9; kartu di atas level tampil terkunci).
  Kartu masuk **hand** (maks `hand_max` = 5), disimpan antar duel sampai dimainkan manual di battle (sekali). Kartu yang dimainkan terpakai dan kembali ke tumpukan shop.
  Hand bisa dijual (50%) di panel persiapan; Mercenary Pact dan Merchant Contract langsung berlaku saat dibeli (tidak bisa dijual). AI membeli Support lewat shop yang sama.
  Kode: `BattleDeck.support_pool` / `draw_shop`, `BattlePrep.hand` / `can_buy` / `buy` / `consume_used`, `PlayerState.hand` (ikut save/resume: `spile`, `hand`); tes `battle_test._test_shop_supports`.
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
- Dialog konfirmasi dan **Profile** memakai `UiDialog` (`scripts/ui/ui_dialog.gd`), bukan `ConfirmationDialog`/`AcceptDialog` bawaan Godot:
  overlay bertema dengan backdrop gelap, ikon nada (`info` ungu / `warn` emas / `danger` merah, tombol konfirmasi ikut merah),
  tombol selebar dialog (>= 58 px), teks panjang bergulir. Back/Esc menutup dialog yang terbuka lebih dulu (`AppNav.go_back`).
  Kartu Profile (`scripts/ui/profile_view.gd`): avatar inisial, nama, status tutorial, bar menang/kalah, 6 statistik. Tes: `ui_dialog_smoke`.
- **Simpan dan lanjutkan match**: autosave di awal tiap giliran manusia dan saat aplikasi di-pause (`user://match.json`, tulis
  lewat file sementara; file korup/versi asing dibuang tanpa crash). Tombol **CONTINUE** di menu. Terbukti deterministik:
  match yang dipulihkan berjalan identik dengan aslinya sampai selesai (3 benua).
- Layar: audit tata letak di 7 rasio (16:9, 18:9, 20:9, 21:9, 16:10, 4:3, 5:3): 0 kontrol keluar layar, semua tombol >= 48 px
  (minimum global 52 px). Dua bug nyata ditemukan dan diperbaiki lewat audit ini: panel persiapan battle terlalu tinggi
  (board terpotong di 720 px) dan HUD tidak memakai lebar ekstra di layar lebar. Screenshot ada di `docs/screenshots/`.
- Performa (desktop; ponsel kelas bawah ~5-10x lebih lambat): tick battle terburuk 1.3 ms (timer 250 ms), satu game AI penuh 76 ms,
  satu duel AI instan <= 13 ms, memori logika ~18 MB, 0 kebocoran setelah 40 game dan 75 siklus buat/hapus scene.
  `low_processor_mode` aktif (hemat baterai), max FPS 60, renderer GL Compatibility.
- Ekspor: `export_presets.cfg` (arm64-v8a + armeabi-v7a, permission INTERNET saja (cek update), tests/tools dikecualikan); paket data 218 KB (95 file)
  berjalan dari luar folder proyek tanpa error.

## Konten (Phase 6)
- **7 benua dapat dimainkan**, masing-masing 4 regional bernama, 10 awalan nama wilayah, 4 faction, dan 1 world modifier.
  Benua selain Aetherion dibuka lewat Journey: master sebuah benua (menang dengan ke-4 faksinya) lalu pilih satu benua terkunci untuk dibuka (Arena tidak membuka apa pun; tidak ada fitur "Unlock all").
- **28 Champion berbeda** (`data/champions.json`): 10 passive papan x 11 skill aktif Last Stand, nilai tiap Champion beda dan dibaca dari data
  (`passive_value`, `active_value`). Passive: Royal Treasury, Shadow Ledger, Landlord, Fortune Weave, Toll Keeper, Treasure Hunter,
  Spoils of War, Quartermaster, Mender, Vanguard. Aktif: Sun Judgment, Starfall Decree, Eclipse Veil, Banner of Iron, Inferno Burst,
  Chrono Stasis, Soul Drain, Frost Veil, Overcharge, Rift Strike, Life Surge.
- **World modifier** (`WorldMods`): Aetherion Royal Tithe (+50 START), Arcanum Arcane Conduits (8 portal aktif), Machina Industrial Age (rent +25%,
  harga shop -20%), Sylvaris Bountiful Harvest (+6 G per wilayah per ronde), Drakmor War Fever (ATK battle +15%, pemenang duel +60 G),
  Thalassia Sea Trade (tax setengah, Reroll Token 40 G), Eclipsia Time Fold (+1 Reroll Token tiap lewat START, bonus roll maks 3).
- **Kartu (v19)**: tiap faksi punya **dek 15 tipe unit** (15 x 9 salinan = 135): **8 Pawn benua** (2 per faksi, "slot" 0-3; di benua lain ia milik faksi benua itu, nama diawali
  nama faksi, mis. "Ferrum Royal Guard"; sama untuk semua faksi di benua itu) + **7 bidak milik faksi sendiri** (2 Rook, 2 Knight, 2 Bishop, 1 Queen; `faction: "<id faksi>"`,
  `slot: -1`, field `continent`): 28 faksi x 7 = **196 kartu unik** dengan nama, nama skill, angka skill (`skill.params`), buff, serta HP/ATK sendiri. Dek ditentukan
  oleh Champion (`Deck.faction_id()` -> `CardDatabase.faction_units`), jadi Battle Shop hanya menawarkan Pawn benua + bidak faksi pemain.
  Setiap slot (Rook Tank, Rook Marksman, Knight Fighter, Knight Assassin, Bishop Mage, Bishop Support, Queen) punya nilai dasar di `CardDatabase.SLOT_BASE`; HP/ATK tiap
  faksi boleh menyimpang sedikit (maks ~12%) dengan HP x ATK tetap seimbang (`validate_all_continents`). Role, range, move, rarity, dan mekanik skill tetap sama per slot;
  skill menunjuk mekanik dasar lewat `skill.mechanic` (`CardDatabase.skill_mechanic`). Angka skill yang divariasikan: durasi taunt, interval dan jumlah target Rook Marksman,
  durasi stun Knight Fighter, bonus serangan pertama Knight Assassin, frekuensi dan persen splash Bishop Mage, interval dan persen heal Bishop Support. Queen selalu
  aura +15% ATK ditambah buff.
  **Save lama**: id bidak bersama versi lama diterjemahkan lewat `legacy_ids` di `cards.json` ke bidak faksi pertama benua itu (`CardDatabase.canonical_id`).
  **Buff benua (`data/card_buffs.json`)**: tiap kartu unit punya satu buff tema (8 Pawn x 7 benua + 196 bidak faksi, nama unik). 8 Pawn yang sama mendapat buff berbeda di
  tiap benua. Buff = tipe efek + nilai (`CardDatabase.BUFF_TYPES`, 22 tipe, diterapkan di `BattleEngine`): armor, evade, thorns, execute, frenzy, aura_atk, burn, stun_proc, ward, splash,
  lifesteal, chill, opener, rage, last_rites, death_burst, mend_self, swift, guard, opening_shield, regen, second_life.
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
Project > Export > Android; renderer sudah GL Compatibility, orientasi sensor landscape (landscape dua arah: layar ikut terbalik saat ponsel diputar 180°, tidak pernah portrait). Butuh Android SDK + JDK + keystore.

- **Build di GitHub dan Gradle/AAB**: `.github/workflows/` (tes otomatis + APK + AAB, Godot 4.7); lihat BUILD_ANDROID.md. Skrip tes: `tools/run_tests.sh`. Proyek kini memakai Godot 4.7 (target API 36 untuk Google Play).

## Tutorial, Auction, Special Dice, seni, audio, kartu baru
- **Tutorial** (New Match -> Offline -> Tutorial): match 1v1 melawan AI Easy di Aetherion, 10 ronde, seed tetap. AI sudah memiliki wilayah di depan pemain dan
  tawaran duel pertama selalu muncul. `TutorialGuide` menjelaskan tiap aturan saat pertama kali muncul (panel petunjuk di papan; tips
  di atas separuh papan musuh saat persiapan duel). Hasilnya tidak dihitung ke statistik; `profile.tutorial_done` disimpan.
- **Auction sungguhan**: lot acak dilelang ke semua pemain hidup, mulai dari yang mendarat; buka 40% harga, naik 10% per tawaran;
  yang pass atau tak mampu keluar; AI menaksir lot dari harga, region yang dilengkapi, dan tingkat kesulitan.
- **Special Dice** (4 jenis x 6 sisi, `data/special_dice.json`): Swift (bonus gerak), Fortune (gold), Warp (teleport, menggantikan lemparan),
  Order (lempar ekstra / lawan berikutnya lewat giliran / token / gold). Sumber: kartu Event dan Territory Shop (120 G); maks 3 dibawa; dipakai
  sebelum melempar. AI memakainya. Tersimpan di save. (Sumber dari Champion dan Rule Card belum ada.)
- **Kartu baru**: tiap kemenangan membuka satu dari 90 Support yang terkunci (urutan tetap: 6 kartu awal, lalu common -> rare -> epic -> legendary). Pool unit baru belum ada.
- **Seni prosedural** (`Art`, `PortraitView`; tanpa file gambar): siluet 6 bidak catur, 7 lambang benua, 7 ikon kategori Support, potret perisai
  Champion. Dipakai di kartu, token battle, dan pemilihan Champion. Galeri: `docs/screenshots/art_gallery.png`.
- **Audio** (`Sfx`): 11 efek suara disintesis dari kode (klik, dadu, koin, pukulan, gugur, sihir, portal, menang/kalah, dll), bisa dimatikan di Settings.
  Belum ada musik.
- **Animasi battle**: gerak halus antar petak, lunge saat menyerang, angka damage melayang, cincin saat unit gugur; mengikuti kecepatan 1x/2x/4x.

## TODO (tidak berpura-pura selesai)
- Pool kartu unit baru (varian pengganti) dan Champion/Rule Card sebagai sumber Special Dice.
- Nama dan ilustrasi unik per benua/Champion (seni sekarang prosedural dan generik); sprite dan animasi unit sungguhan.
- Musik latar; suara masih sintetis sederhana.
- Multiplayer online (Classic dan Ranked 1v1 / 2v2 / 4 player, Battle Chess online, Lobi, Turnamen): belum ada, tab ONLINE di New Match hanya menampilkan kartunya sebagai "Coming soon". Journey sekarang hanya jalur unlock benua 1v1; alur cerita/campaign dengan misi khusus belum ada. (2vs2 melawan AI sudah ada, lihat bagian Mode 2vs2.)
- Pemilihan target manual untuk kartu Artifact (Crown of Valor, Aegis Shield, Windboots).
- Uji di perangkat Android nyata (lihat BUILD_ANDROID.md).
- Keseimbangan: eliminasi total jarang (3-4%); game biasanya diputuskan net worth di ronde 30. Diukur per benua dengan `tools/balance_report`.

## Peta Territory: zoom dan kamera
Layar Territory dan Battle tiga kolom ala Monopoly (Battle: tombol + kartu Support di kiri, papan 8x8 di tengah, shop + bench di kanan, log di kanan saat bertarung). Territory: papan di tengah, log di kiri (aksi di bawah log; tombol dadu di dalam papan), pemain di kanan. Papan tampil utuh (zoom 1x) dan kamera mengikuti pion saat di-zoom. Geser dengan drag, cubit atau roda mouse untuk zoom,
tombol + / - / Fit dan Speed di pojok kiri bawah layar; semua tombol aksi (Roll Dice, Reroll, Move, End Turn, Buy, special dice) di pojok kanan bawah layar untuk zoom manual atau melihat seluruh papan. Ketuk petak untuk info. Kode: `scripts/ui/board_view.gd`.
