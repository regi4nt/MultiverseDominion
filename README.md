# MULTIVERSE DOMINION — Godot 4.7 (GDScript)

Status: **PHASE 1 (Foundation) + PHASE 2 (Territory Board) + PHASE 3 (Card System) + PHASE 4 (Battle System) + PHASE 5 (Game Loop) + PHASE 6 (Content) + PHASE 7 (Android) — selesai di sisi kode; **APK belum dibangun/diuji di perangkat** (lihat BUILD_ANDROID.md).**
Proyek berjalan di Godot 4.7 (renderer GL Compatibility). Menu utama: New Match (Journey / Arena / Battle Chess / Tutorial), Card Hub (Collection / Deck / Info), Shop, Events (Mission / Achievement / Chests), Profile, Settings. Sebelum perubahan batas ronde per mode, diuji dengan Godot headless: import bersih, game AI penuh selesai, UI smoke test lolos; setelah perubahan itu tes belum dijalankan ulang.
Perubahan terbaru (safe area notch, judul menu di kiri bawah, START di kanan bawah, zoom awal papan 100 petak, tombol Fit / 1:1, tab Info) ditulis tanpa Godot di tempat kerjanya, jadi **belum dijalankan sama sekali**: jalankan `tools/run_tests.sh` dan cek di perangkat (BUILD_ANDROID.md bagian 4).

## Menjalankan
1. Buka Godot 4.7 -> Import -> pilih `project.godot` (biarkan import pertama selesai).
2. Tekan F5. Alur: Main Menu -> NEW MATCH -> pilih OFFLINE (Journey / Arena / Battle Chess / Tutorial) -> untuk Arena: pemain / difficulty / taruhan / continent; untuk Journey: continent / taruhan (difficulty dipaksa menurut trofi sampai benua terakhir terbuka, setelah itu bebas dipilih) -> START MATCH (faksi diambil dari Deck) (lihat bagian "New Match").
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
   `godot --headless --path . res://tests/monster_test.tscn` -> `MONSTER TEST RESULT: PASS` (monster tersembunyi).
   `godot --headless --path . res://tests/deposit_test.tscn` -> `DEPOSIT TEST RESULT: PASS` (tambang & harta karun tersembunyi).
   `godot --headless --path . res://tests/skin_test.tscn` -> `SKIN TEST RESULT: PASS` (skin map per benua).
   Juga: `tutorial_test` (juga memeriksa batas ronde per mode / difficulty), `audio_test`, `fx_test`, `rules_test` (Auction, Special Dice, unlock), `team_test` (mode 2vs2), `newmatch_test` (hub, setup, aturan unlock),
   `series_test` (Battle Chess 10 Rounds / Survival), `shop_test`, `chest_test`, `event_test`, `xp_test`, `save_test`, `update_test`, `perf_test`;
   UI: `ui_resume_smoke`, `ui_shop_smoke`, `ui_dialog_smoke`, `ui_ux_smoke`, `ui_tutorial_smoke`, `layout_test` (dua terakhir butuh render nyata, lihat BUILD_ANDROID.md bagian 4).
   `tools/run_tests.sh [logic|ui|all]` menjalankan tes logika dan UI headless berurutan (dipakai juga oleh `.github/workflows/tests.yml`); `perf_test`, `ui_smoke`, `ui_tutorial_smoke`, dan `layout_test` tidak termasuk. Scene `*_shots` / `art_gallery` hanya membuat screenshot.

## Peti hadiah / Chests (Main Menu -> Events -> tab Chests)
- **Menang Arena = dapat 1 peti** (Journey, Tutorial, Battle Chess, dan kekalahan tidak). Grade ditentukan acak menurut difficulty (`ChestSystem.DROP_WEIGHTS`): Easy 70/25/5, Normal 55/33/12, Hard 35/45/20 (% Bronze/Silver/Gold). Layar hasil menampilkan peti yang didapat. Kemenangan tidak lagi membuka kartu Support baru (kartu hanya dari Shop).
- **Batas perolehan: 6 peti** (`ChestSystem.DROP_LIMIT`). Setelah peti ke-6 didapat, kemenangan Arena berikutnya tidak memberi peti sampai **1 jam** (`DROP_REFRESH_SECONDS`) berlalu sejak batas tercapai; lalu jatah di-refresh ke 0 dan peti bisa didapat lagi. Tab Chests menampilkan "Chest drops: n/6" dan hitung mundur refresh; layar hasil menulis "Chest limit reached".
- **4 slot**. Peti masuk ke slot kosong pertama dalam keadaan menunggu; tekan *Start unlocking* untuk menjalankan **timer** (jam nyata, tetap berjalan saat game ditutup). Hanya **satu peti** yang boleh membuka kunci pada satu waktu. Semua slot penuh = peti masuk **Storage** (di samping slot, kapasitas 12, `ChestSystem.STORAGE_CAPACITY`); tombol *To slot* memindahkannya ke slot kosong pertama (menunggu, belum jalan timernya). Hanya bila Storage juga penuh, peti langsung jadi coin (Bronze 50 / Silver 150 / Gold 400).
- **Timer**: Bronze 15 menit, Silver 1 jam, Gold 4 jam. **Open now** melewati sisa timer dengan Crystal (1 Crystal per 30 menit tersisa, dibulatkan ke atas, ada konfirmasi).
- **Isi** (rentang, peluang): Bronze = Coins 60-120, Fragments 5-15 (70%), Chips 50-150 (40%), Tiket 1 (10%), XP 20-40. Silver = Coins 150-300, Fragments 20-45, Chips 150-400 (70%), Tiket 1-2 (40%), Crystal 1 (20%), XP 60-110. Gold = Coins 400-800, Fragments 60-140, Chips 500-1200 (90%), Tiket 2-4 (80%), Crystal 1-3 (60%), XP 150-260. Semua angka ada di `ChestSystem.GRADE_DATA`.
- Tersimpan di save (`chests`: slots + opened + storage + drops + limit_at); save lama otomatis mendapat 4 slot kosong. Tombol Events di menu utama menampilkan "Events (N to claim!)" bila ada peti siap (dihitung bersama misi/achievement yang belum diklaim); tab Chests juga menampilkan jumlah peti siap.
- Kode: `scripts/systems/chest_system.gd`, `scripts/ui/chests_panel.gd` (dipakai tab Chests di `scenes/events/events.tscn`). Tes: `godot --headless --path . res://tests/chest_test.tscn` -> `CHEST TEST RESULT: PASS`.

## Events (Main Menu -> Events, tepat di atas Settings)
- Tiga tab: **Mission**, **Achievement**, dan **Chests** (4 slot peti, lihat bagian Peti hadiah). Entri yang selesai tampil di atas dengan tombol **Claim**; angka di tab = jumlah hadiah yang belum diambil, menu utama menampilkan "Events (N to claim!)".
- **Mission**: 4 misi harian, diundi dari 8 misi (`EventHub.MISSION_POOL`) dengan seed tanggal (daftar sama seharian, berganti tiap tengah malam waktu lokal; ada hitung mundur reset). Progres dan klaim ikut di-reset.
- **Achievement**: 16 target permanen (menang, main, Arena, Battle Chess, peti, gacha, level, trofi, jumlah coin) di `EventHub.ACHIEVEMENTS`.
- Hadiah: coin, fragment, tiket, Crystal, chip, XP. Progres dihitung lewat `EventHub.track(metric, n)` dari `SaveManager.record_match` / `record_practice`, `ChestSystem.open`, dan `ShopSystem.pull_batch`. Disimpan di save (`events`).
- Kode: `scripts/systems/event_hub.gd`, `scripts/ui/events.gd`, `scenes/events/events.tscn`. Tes: `godot --headless --path . res://tests/event_test.tscn` -> `EVENT TEST RESULT: PASS`.

## Shop (Main Menu -> Shop, di atas Profile)
- Rincian lengkap ada di bagian "Shop, unit terkunci & jalur trofi" di bawah (4 tab: Card Gacha, Buy Card, Gamble, Exchange). Gacha dibayar **Tiket** (bukan coin), kartu terkunci dibeli dengan **Crystal** atau **Fragment**, dan coin diubah ke tiket / fragment / chip lewat Exchange.
- Mata uang: **Aether Coins** (mulai 600), Fragments, Gacha Tickets, Crystals, Chips (disimpan di `wallet` pada save). Hadiah match tergantung difficulty (lihat "Nyawa & hadiah per difficulty"). **Battle Chess** juga memberi coin menurut difficulty (Easy +50 / +10, Normal +75 / +15, Hard +150 / +25 untuk menang / kalah-seri; `ShopSystem.PRACTICE_WIN_BY_DIFF` / `PRACTICE_LOSS_BY_DIFF`); tidak mengubah statistik, progres Journey, atau membuka kartu.
- Rate gacha: Common 60 / Rare 28 / Epic 10 / Legendary 2 (%), pity Epic+ di pull ke-30 (`ShopSystem.RATES`, `PITY_LIMIT`). Duplikat jadi Fragment.
- Tes: `godot --headless --path . res://tests/shop_test.tscn` -> `SHOP TEST RESULT: PASS`; `ui_shop_smoke.tscn` -> `UI SHOP SMOKE: PASS`.

## Deck: pilihan benua
- Tab Deck selalu menampilkan chip semua benua yang playable (yang belum dibuka diberi tanda `(locked)`), tidak perlu menamatkan Journey dulu. Arena memakai deck milik benua yang dimainkan, jadi deck tiap benua harus bisa diatur sejak awal. Kartu dari benua yang masih terkunci tetap terkunci; deck diisi dari kartu benua yang sudah terbuka lewat chip `Cards: ...`.

## UX geser (scroll)
- Semua area scroll dibuat lewat `UiTheme.make_scroll()` yang sekarang mengembalikan `TouchScroll` (`scripts/ui/touch_scroll.gd`): kontrol Button / Panel / RichTextLabel di dalamnya otomatis `MOUSE_FILTER_PASS` (juga yang ditambahkan belakangan, mis. grid kartu yang dibangun ulang), jadi geseran yang dimulai di atas tombol atau kartu tetap men-scroll daftar (Deck, New Match, Shop, Settings, dialog, dll).
- Geseran yang dimulai di atas tombol membatalkan tekan tombol itu setelah melewati dead zone, jadi melepas jari tidak ikut menekan tombol. Slider, scrollbar, LineEdit/TextEdit tetap `STOP`.

## Shop, unit terkunci & jalur trofi
- **Shop** punya 6 tab: **Card Gacha** (satu pool: Support + Unit + King), **Buy Card** (Support + Unit jadi satu), **Auction**, **Gamble**, **Trading**, **Exchange** (`scripts/ui/shop.gd`, logika di `ShopSystem`). Mata uang di dompet: Aether Coins, Fragments, **Gacha Tickets**, **Crystals**, **Chips**.
- **Gacha** hanya bisa dibayar **Tiket** (1 pull = 1 tiket, 10-pull = 9 tiket); Coins tidak bisa lagi dipakai langsung. **Card Gacha** hanya **satu pool** (tidak ada lagi pilihan pool Bidak / Support): rarity diundi dulu (Common 60 / Rare 28 / Epic 10 / Legendary 2 %), lalu kartu diambil dari pool berisi semua kartu Support rarity itu, kartu unit Rare/Epic dan kartu **King** (Legendary) dari benua yang sudah terbuka. Pity **per kelangkaan** (counter sendiri, reset saat rarity itu atau yang lebih tinggi keluar; `ShopSystem.PITY_LIMITS`): Rare+ dijamin di pull ke-10, Epic+ di pull ke-30, Legendary di pull ke-90 (Legendary menang atas Epic, Epic atas Rare); 10-pull minimal 1 Rare; duplikat jadi fragment (duplikat King menaikkan level B).
- **Animasi grafis Gacha** (`scripts/ui/gacha_stage.gd`, digambar dengan kode seperti `gamble_stage.gd`): saat Pull, lingkaran sihir berputar, partikel tersedot ke orb yang makin terang, lalu ledakan cahaya + cincin + sinar berwarna rarity terbaik di batch itu (Common 1,1 dtk, Rare 1,45, Epic 1,85, Legendary 2,4). Kartu baru muncul saat ledakan. Hasil undian sudah ditentukan `ShopSystem.pull_batch`; animasi hanya memutarnya. Mode **Lite** melewati animasi.
- **Buy Card** (kartu Support dan unit dalam satu tab; filter All / Unit / Support): beli kartu terkunci dengan **Crystals** atau tukar Fragments (tidak bisa dengan Coins). Harga unit: Rare 2 kristal / 120 fragment, Epic 4 / 300.
- **Exchange** (`ShopSystem.EXCHANGES`): jumlah pack dipilih dengan **slider** (tombol - dan + di sampingnya, maksimum = sebanyak yang mampu dibayar), lalu tekan *Exchange*; urutan di tab: 100 coins = 1 tiket (tiket tidak bisa ditukar ke kristal; kristal hanya dari peti, misi, dan achievement); 50 coins = 10 fragment; 100 coins = 100 chip; 10 fragment = 20 coins; 100 chip = 80 coins. Bolak-balik selalu rugi, tidak bisa untung. Chip dipakai di tab **Gamble**.
- **Auction**: tab tepat di kiri Gamble. 5 kartu terkunci acak (Support non-Common + unit yang dijual Shop) dilelang, **diganti tiap jam** (seed = jam unix, sama untuk satu jam penuh; hitung mundur tampil di tab, lot baru muncul otomatis saat jam berganti). Bayar dengan **Crystals**; nilai lot = harga Crystal kartu itu (Buy Card: 1 / 2 / 4 / 10), bid pertama 40% nilai (min. 1), raise 10% nilai (min. 1), tiap raise +10%. Satu rival menjawab tiap raise sampai batas tersembunyinya (60-130% nilai); jika rival menyerah kamu menang dan membayar bid terakhirmu, atau *Pass* untuk melepas lot. Animasi (`scripts/ui/auction_stage.gd`, digambar dengan kode): papan tawaran hijau naik saat kamu bid, papan merah rival membalas dari sisi lain, lalu palu mengetuk dengan gelombang kejut + percikan emas dan teks **SOLD!** (atau **GONE** kalau lot diambil rival / di-Pass). Tombol terkunci selama animasi; mode **Lite** melewatinya. Logika: `ShopSystem.auction_*`, UI: `AuctionPanel` di `shop.gd`.
- **Gamble (judi)**: mini game uang cepat, taruhan dan hadiah hanya dalam **Chip** (bet 100/500/1000/5000; ubah kemenangan jadi coins lewat Exchange). Coin Flip (menang 48%, bayar x2), Dice 2 dadu (Low/High x2.3, Seven x5.5), Slots 3 reel (tiga 7 x30, tiga sama x8, dua sama x1.5). Semua punya house edge kecil (~95% return, diuji simulasi). Logika: `ShopSystem.gamble`.
- **Kartu King (B1 / B2 / B3)**: King sekarang kartu yang dikoleksi, ada di **Card Gacha** (rarity Legendary, hanya King dari benua yang sudah terbuka) dan **Buy Card** (filter baru **King**; harga Legendary: 10 kristal atau 1000 fragment per kopi). Jumlah kopi = level **B** (maks B3). Duplikat King menaikkan B (bukan jadi fragment); setelah B3 baru jadi fragment. Pemain baru hanya punya Solvaris (B1); save lama otomatis mendapat King dari faksi yang sudah terbuka sebagai B1. King yang belum dimiliki tidak bisa dipilih di Deck.
  - **B1**: kartu King (stat, battle passive, King buff) tanpa skill King.
  - **B2**: membuka **skill aktif Battle Chess** (tombol King skill, sekali pakai). Di bawah B2 tombolnya terkunci dan King masuk arena tanpa skill.
  - **B3**: membuka **skill teritori** (passive di Territory Board: Royal Treasury, Shadow Ledger, dst). Di bawah B3 pemain tidak mendapat efek passive itu.
  - Hanya King pemain yang dikunci; lawan AI selalu punya semua skill. Tutorial tidak dikunci. Logika: `SaveManager.king_b` / `add_king_copy`, `ShopSystem.shop_kings`, kunci battle di `BattleEngine.king_skill_locked` (cfg), kunci teritori lewat cfg `king_b` di `MatchController`. Tes: `tests/king_test.gd`.
- **Kartu unit terkunci** (mekanik Clash Royale): pemain baru hanya punya 15 tipe unit starter (8 Pawn + 7 bidak Solvaris = deck default). Sisanya hanya bisa dipakai di deck setelah didapat dari Shop. Deck tidak pernah memakai unit yang belum dimiliki (`Deck.owned_filter`). Save lama (semua unit dimiliki) tetap utuh (`unit_cards_v`).
- **Journey = jalur trofi**: menang +trofi, kalah -trofi (Easy +20/-30, Normal +30/-20, Hard +40/-10; `trophy_win`/`trophy_loss` di balance.json). Trofi tidak turun di bawah ambang benua tertinggi yang terbuka. Benua terbuka otomatis di `unlock_trophies` (Aetherion 0, Arcanum 150, Machina 400, Sylvaris 700, Drakmor 1100, Thalassia 1600, Eclipsia 2200) **dan hanya jika pemain sudah menang di benua sebelumnya dengan masing-masing faksinya** (aturan yang sama seperti Eclipsia; lihat "Gerbang faksi" di bawah), lalu kartu unitnya masuk Shop (tidak langsung bisa dipakai).

## Nyawa & hadiah per difficulty
- **Nyawa (Life)** awal semua penguasa dalam match mengikuti difficulty: **Easy 5, Normal 3, Hard 1** (`data/balance.json` -> `life_by_difficulty`, `GameData.life_for`). Angka ini juga batas maksimal heal (Territory Shop, Royal Pardon, dadu Healing, dst.): `PlayerState.max_life`. Pada Hard, kekalahan duel atau bangkrut pertama langsung menyingkirkan penguasa. Tutorial memakai AI Normal dan 3 Life. Tersimpan di save/resume (`max_life`, `difficulty`); save lama dianggap 3.
- **Difficulty Journey: 3 level di setiap benua** (`SaveManager.difficulty_for_trophies()`, `journey_band()`, `journey_tier_starts()`; `balance.json` -> `journey_last_continent_span` untuk benua terakhir): rentang trofi tiap benua (dari `unlock_trophies`-nya sampai `unlock_trophies` benua berikutnya) dibagi tiga sama besar: Easy di awal, Normal di tengah, Hard di akhir. Begitu benua baru terbuka, level kembali ke Easy. Contoh Aetherion (0-149): Easy 0-49, Normal 50-99, Hard 100-149; Arcanum (150-399): Easy 150-233, Normal 234-316, Hard 317-399. Trofi tidak pernah turun di bawah batas benua yang sudah terbuka, jadi tiap benua selalu mulai dari Easy. Nyawa, gold awal, batas ronde, hadiah, perubahan trofi, dan odds taruhan memakai level itu. Arena tetap memilih difficulty sendiri. **Difficulty bebas dipilih hanya setelah jalur selesai** (`SaveManager.journey_difficulty_free()` = `journey_final_cleared()`): Eclipsia terbuka, trofi sudah mencapai akhir rentang Eclipsia (`journey_final_trophy_goal()` = 2800, jadi tahap Easy, Normal, dan Hard Eclipsia sudah dilewati) DAN pemain sudah menang di Eclipsia dengan **masing-masing dari 4 faksinya** (Solstice, Paradox, Eternis, Oblivion; kemenangan per faksi dicatat di `journey_wins` oleh `record_match`, kemenangan ulang dan kekalahan tidak dihitung). Setelah itu pemain memilih Easy / Normal / Hard sesukanya di setup Journey (tombol yang sama dengan Arena); trofi menang/kalah dan hadiah mengikuti pilihan itu. Sebelum itu setup menampilkan tujuan, mis. "Goal: reach 2800 trophies (2310 now) and win on Eclipsia with each of its 4 factions (2 / 4) to choose your own difficulty", dan level AI tetap dipaksa menurut trofi.
- **Gerbang faksi (Journey)**: benua berikutnya tidak cukup dibuka dengan trofi. Pemain juga harus pernah **menang di Journey dengan tiap faksi benua sebelumnya** (4 faksi per benua, mis. Aetherion: Solvaris, Nocthyr, Valdoria, Elarion -> baru Arcanum bisa terbuka). Kemenangan dicatat per faksi di `journey_wins` (kemenangan ulang dan kekalahan tidak dihitung). Selama gerbang belum lengkap, trofi **tertahan 1 di bawah ambang benua berikutnya** (`SaveManager.journey_trophy_cap()`, mis. 149 untuk Arcanum) sehingga level AI tetap Hard; begitu faksi terakhir menang, benua langsung terbuka. API: `journey_prev_continent(id)`, `journey_gate_missing(id)`, `can_unlock_continent(id)`, `unlock_by_trophies()`. UI: status Journey di hub, baris benua terkunci di setup, hint Journey ("Arcanum needs a win with each Aetherion faction (2 / 4)"), dan catatan Shop menampilkan progres faksi. **King benua didapat gratis**: begitu benua terbuka, keempat King faksinya masuk koleksi sebagai B1 (`SaveManager.grant_continent_kings()`, dipanggil oleh `unlock_by_trophies()`), jadi pemain bisa menang dengan tiap faksi tanpa menunggu gacha; pemain baru langsung punya 4 King Aetherion. King yang sudah dimiliki tidak berubah levelnya, dan salinan tambahan (B2 / B3) tetap dari Card Gacha / Buy Card. Layar hasil menulis "... opened! Its unit cards are now in the Shop and its Kings are yours (B1)." Save lama (`king_cards_v` < 2) mendapat King dari semua benua yang sudah terbuka. Save lama aman: benua yang sudah terbuka tetap terbuka; gerbang hanya berlaku untuk benua yang masih terkunci.
- **Hadiah Aether Coins setelah match** (Journey / Arena, `ShopSystem.WIN_REWARD_BY_DIFF` / `LOSS_REWARD_BY_DIFF`): Easy menang +100 / kalah +25, Normal +150 / +50, Hard +300 / +75. Bonus random-map Arena (hanya saat menang) dihitung dari hadiah menang difficulty yang dipilih; bonus benua berupa persen/tambahan coin dan **XP** (bukan lagi fragment: Arcanum +20 XP, Sylvaris +15 XP +15 coins, Eclipsia +25 XP; data di `data/continents.json` -> `random_bonus.xp`). Bonus XP digabung dengan XP match sehingga ikut memicu hadiah naik level.
- **Battle Chess** (`PRACTICE_WIN_BY_DIFF` / `PRACTICE_LOSS_BY_DIFF`): Easy +50 / +10, Normal +75 / +15, Hard +150 / +25. Battle Chess memakai nyawa run Survival (Easy 5 / Normal 3 / Hard 1), bukan Life match.
- Layar New Match menampilkan Life dan hadiah difficulty yang sedang dipilih; layar hasil menampilkan difficulty di baris coin. Taruhan (wager) tetap memakai pengali odds sendiri di atas hadiah ini.

## Taruhan / Wager (Arena dan Battle Chess)
- Sebelum bertanding pemain bisa mempertaruhkan **Aether Coins** lewat **slider kelipatan 10** (0 = None, maksimal 1000, tombol - / + menggeser 10; batas atas mengikuti saldo, `ShopSystem.WAGER_STEP` / `WAGER_MAX`). **Journey sekarang punya taruhan** (tanpa pilihan difficulty: level AI Journey mengikuti trofi, jadi odds taruhan juga ikut: Easy x1.5, Normal x2.0, Hard x3.0); Tutorial tidak punya taruhan.
- **Arena**: panel *Wager* ada di kolom Match (di bawah Difficulty). **Battle Chess**: menekan kartunya membuka dialog kesulitan + taruhan, lalu tombol FIGHT.
- Stake dibayar **saat match dimulai** (`SaveManager.place_wager`). Menang: dibayar **stake x odds** (stake sudah termasuk), kalah: stake hangus. Battle Chess seri: stake dikembalikan.
  Keluar di tengah Battle Chess = stake hangus. Arena: stake ikut tersimpan di match yang bisa dilanjutkan (`MatchController.wager`), diselesaikan satu kali (`wager_settled`).
- Odds (`ShopSystem.wager_odds`): 1 vs 1 / 2 vs 2 / Battle Chess x2, 4 Player x2,5 (`FFA_ODDS`; Chaos x0,75); dikali kesulitan AI easy x0.75, normal x1, hard x1.5. Taruhan ini **di luar** hadiah coin normal (lihat hadiah per difficulty di atas).

## Monster tersembunyi di Territory
- **4 monster per benua** (7 benua = 28 monster, semuanya berbeda: nama, stat, dan buff; data di `data/monsters.json`). Satu monster untuk tiap region (Utara/Timur/Selatan/Barat), masing-masing bersembunyi di **petak Territory acak** region itu.
  Lokasinya diacak tiap match (seed yang sama = lokasi yang sama) dan **tidak pernah ditampilkan di peta**: `describe_tile`, papan, dan info petak tidak menyebutnya. Pemain baru tahu setelah **mendarat** di petak itu. Match Tutorial tidak punya monster.
- **Bertemu monster**: mendarat di petak berisi monster -> pilih **Fight** atau **Flee** (`pending.type = "monster"`, tombol keputusan biasa). Setelah itu petak diproses seperti biasa (beli / sewa / duel).
  **Fight (pemain manusia di game)** = pertarungan di layar Battle seperti Duel (`MatchController.monster_battles_interactive`, state `AWAIT_DUEL` dengan `pending.type = \"monster_battle\"`): fase persiapan (beli unit dengan Dominion Gold, deploy, Level Up, kunci formasi), kartu Support dan skill King bisa dipakai, lalu auto battle melawan monster liar. Gold yang dibelanjakan permanen, sama seperti Duel. Menang = Kartu Monster; kalah atau seri/timeout = bayar `monster_defeat_gold` dan monster tetap di sarang. Hasil dilaporkan lewat `MatchController.finish_monster_battle`.
  AI dan simulasi tanpa UI tetap memakai auto battle instan (`MonsterSystem.fight`: pasukan permanen dipasang otomatis + King Last Stand, tanpa beli unit dan tanpa kartu Support).
  Kalah = kehilangan `monster_defeat_gold` (50 G) dan monster tetap di sarangnya; kabur = gratis.
- **Menang = dapat Kartu Monster**, **maksimal 1 per pemain**. Pemain yang sudah punya kartu berjalan melewati monster lain tanpa terjadi apa-apa (monster tetap tersembunyi). Monster yang sudah dikalahkan hilang untuk semua pemain (`monster_unique`: true di `balance.json`; set `false` agar tiap pemain bisa mengalahkan monster yang sama).
- **Membantu King di Duel**: saat King masuk lewat Last Stand, monster ikut turun di samping King dan bertarung di pihak yang sama, dengan stat setara **King di level yang sama dengan King pemain saat kartunya didapat**: stat monster liar x pengali level itu (Lv 1 = x1,0 / x1,0, Lv 2 = HP x1,35 / ATK x1,25, Lv 3 = HP x1,8 / ATK x1,5, `CommanderSystem`). Level disimpan di `PlayerState.monster_star` (= `commander_star` saat menang) dan **tetap** walau King naik level setelahnya; ikut tersimpan di save/resume (`mstar`, save lama memakai level King saat ini). Dikirim ke engine lewat side config `monster_star` (`BattlePrep.to_side_cfg`). Buff monster (armor, burn, regen, aura ATK, dst.) memakai efek buff kartu yang sudah ada. Berlaku untuk duel pemain maupun AI (`BattleEngine` side config key `"monster"`, `BattlePrep.to_side_cfg(..., monster_id)`).
- **Skill aktif Monster** (dipakai seperti skill King): tiap dari 28 monster punya skill aktif sendiri di `data/monsters.json` (`skill_id`, `active_name`, `active_value`, `active_desc`; memakai mekanik skill King yang sama: Sun Judgment, Inferno Burst, Banner of Iron, Rift Strike, Chrono Stasis, dst., jadi efeknya sudah ada di `BattleEngine._apply_active_skill`). Kekuatannya mengikuti ATK/HP monster, jadi kekuatan skill sekutu mengikuti level monster (Lv 1-3).
  - **Sekutu (Kartu Monster)**: skill dipakai **manual, sekali per battle** lewat tombol baru di panel King (di bawah tombol skill King), setelah monster ikut turun bersama King. Biaya **energi** `monster_skill_energy` = 5 (sumber energi yang sama dengan Support dan skill King; King punya biaya `king_skill_energy` = 6). Skill King dan skill Monster masing-masing sekali pakai dan tidak saling mengunci. Tombol menampilkan biaya, sisa energi, "(used)" atau "(the Monster has fallen)" bila monster sudah tumbang. Sisi AI / auto memakainya otomatis: skill King dulu, lalu skill Monster begitu energi cukup, dan AI tidak memainkan Support selagi menunggu keduanya.
  - **Monster liar**: memakai skill-nya **sekali, otomatis, gratis** saat ada musuh dalam jarak 3 petak. Matikan lewat `wild_monster_skill: false` di `balance.json`.
  - API engine: `can_use_monster_skill(side)`, `use_monster_skill(side)`, `monster_energy_cost()`, `ally_monster(side)`, `monster_skill_used`, `monster_unit`. Ringkasan monster (`MonsterSystem.summary`, tooltip di Territory Board) kini menampilkan baris "Skill - nama: deskripsi". Tes: `monster_test` (`_test_skill_data`, `_test_manual_monster_skill`, `_test_auto_monster_skill`, `_test_all_monster_skills`, `_test_wild_monster_skill`).
- UI: kartu pemain menampilkan "Monster: nama" (tooltip = stat + buff); popup hasil untuk pemain manusia; panel King di layar Battle menampilkan kartu monster. Tersimpan di save/resume (`monsters`, `PlayerState.monster_id`); save lama tanpa monster tetap bisa dimuat.
- **Level monster liar = level King yang menantangnya**: stat di `data/monsters.json` adalah stat dasar (Lv 1); monster liar bertarung dengan pengali level King penantang (Lv 1 = x1,0 / x1,0, Lv 2 = HP x1,35 / ATK x1,25, Lv 3 = HP x1,8 / ATK x1,5, `CommanderSystem`), jadi HP liar 325-490 di Lv 1 dan 585-882 di Lv 3 (ATK 26-35 di Lv 1, 39-53 di Lv 3). Level dikirim ke engine lewat side config `foe_star` (= `commander_star` pemain, juga di `MonsterSystem.fight` untuk AI dan di layar Battle untuk pemain manusia). Skill dan buff liar ikut menyesuaikan karena dihitung dari stat itu. Ringkasan monster (`MonsterSystem.summary`) dan pesan Fight / Flee menampilkan "Lv n"; kekuatan yang dipakai AI untuk memutuskan Fight / Flee (`MonsterSystem.power(id, star)`) memakai level King AI itu sendiri. Naik level King berarti monster liar berikutnya juga lebih kuat, sedangkan Kartu Monster yang sudah didapat tetap di level saat didapat.
- **Stat setara King, bukan setara unit**: HP dasar monster **325-490** dan ATK dasar **26-35**, sejajar dengan King di `data/champions.json` (HP 310-490, ATK 26-35); unit biasa hanya HP 50-290 dan ATK 6-28. Urutan antar-monster dipertahankan (Gearwork Behemoth 490 HP paling tebal, Cinder Phoenix 325 HP paling tipis; Voltage Arc Hound dan Chrono Foundry Drone ATK 35 paling kuat). Sebagai sekutu stat-nya mengikuti level King saat didapat (Lv 1 = stat liar, Lv 3 = HP 585-882 dan ATK 39-53); nama monster di panel King dan tooltip Territory Board menampilkan "Lv n". Rentang lama (HP 600-1510, ATK 22-53) sudah tidak dipakai; kalibrasi lama (~60% menang di ronde ~14) tidak berlaku lagi dan belum diukur ulang, jadi pasukan penuh sekarang kemungkinan jauh lebih mudah mengalahkan monster. Penyesuaian lewat `data/monsters.json` (hp / atk) dan pengali level di `commander_star_hp_mult` / `commander_star_atk_mult`.
- Kode: `scripts/systems/monster_system.gd`, `MatchController._meet_monster` / `_answer_monster`, `AIController._monster_choice`. Tes: `godot --headless --path . res://tests/monster_test.tscn` -> `MONSTER TEST RESULT: PASS`.

## Tambang & harta karun tersembunyi di Territory
- **4 temuan per benua: 2 harta karun + 2 tambang** (7 benua = 28 temuan, semuanya berbeda: nama, lore, hadiah, dan durasi; data di `data/deposits.json`). Tiap temuan tersembunyi di **petak Territory acak di seluruh papan** (region mana pun), tidak pernah di petak yang sama dengan temuan lain dan tidak pernah di sarang monster.
  Lokasinya diacak tiap match (seed yang sama = lokasi yang sama), memakai generator acak sendiri sehingga aliran rng utama dan lokasi monster tidak berubah. Seperti monster, **tidak pernah ditampilkan di peta**: `describe_tile` dan info petak tidak menyebutnya. Match Tutorial tidak punya temuan. Opsi `deposits: false` pada cfg `setup()` mematikannya.
- **Menemukan**: cukup **mendarat** di petak itu (otomatis, tanpa keputusan). Setelah itu petak diproses seperti biasa (beli / sewa / duel / monster).
- **Harta karun**: hadiah sekali ambil untuk penemunya (emas, kadang Reroll Token, kadang Special Die; jika kantong dadu penuh, emasnya tetap dibayar). Setelah ditemukan, hilang untuk semua pemain.
- **Tambang**: menjadi milik penemunya dan membayar **emas tiap akhir ronde** selama sejumlah ronde (`rounds`), sebagian tambang juga memberi 1 Reroll Token tiap `token_every` pembayaran. Tambang pemain yang tersingkir berhenti membayar. Pemain lain yang mendarat di tambang yang sudah ditemukan tidak mendapat apa-apa.
- Contoh isi: Aetherion = Buried Royal Tithe (300 G), Crown Jeweler's Cache (180 G + Token), Sunstone Quarry (30 G x 10 ronde), Emerald Seam (24 G x 12 ronde + Token tiap 6). Drakmor = Dragon's Hoard (350 G), Warlord's War Chest (240 G + Special Die), Obsidian Pit (38 G x 8), Brimstone Deep (30 G x 10). Angka lengkap tiap benua ada di `data/deposits.json`.
- UI: popup untuk pemain manusia saat menemukan harta karun atau tambang; kartu pemain menampilkan "Mines: N (+X G / round)" (tooltip = tambang + sisa ronde). Tersimpan di save/resume (`deposits`); save lama tanpa temuan tetap bisa dimuat.
- Kode: `scripts/systems/deposit_system.gd`, `MatchController._find_deposit` / `_pay_mines` (dipanggil dari `_end_of_round`), signal `deposit_event`. Tes: `godot --headless --path . res://tests/deposit_test.tscn` -> `DEPOSIT TEST RESULT: PASS`.

## Skin map berbeda untuk tiap benua (Territory dan Battle)
- Tiap benua punya **tampilan papan sendiri**, baik di **Territory Board** (cincin 100 petak + plat tengah) maupun **Battle Board** (grid 8x8), plus **langit latar** layarnya. Semuanya digambar prosedural dengan `_draw()` (tanpa file gambar, tetap ringan di Android). Data di `data/map_skins.json`, kode di `scripts/ui/map_skin.gd` (`MapSkin`).
- Ciri tiap benua:

| Benua | Warna | Motif (`pattern`) | Bentuk petak / sel | Emblem watermark |
|---|---|---|---|---|
| Aetherion | emas kerajaan | `marble` (urat marmer) | agak bulat (0.12) | ratu / mahkota |
| Arcanum | ungu arkana | `runes` (glif rune) | bulat sedang (0.30) | bintang arkana |
| Machina | tembaga + baja | `gears` (roda gigi) | hampir siku (0.03) | roda gigi besar |
| Sylvaris | hijau hutan | `leaves` (daun, arah beda tiap sel) | sangat bulat (0.42) | daun |
| Drakmor | merah lava | `embers` (retakan + percikan) | tajam (0.04) | taring naga |
| Thalassia | biru laut | `waves` (garis ombak) | bulat (0.25) | ombak |
| Eclipsia | indigo + bintang emas | `stars` (bintang 4 sudut) | hampir lingkaran (0.45) | gerhana |

- **Territory**: warna bingkai papan, plat tengah, judul benua, petak Territory (selang-seling), warna petak layanan (Shop, Bank, dst. tetap satu keluarga warna agar mudah dikenali tetapi diberi tint benua), motif di tiap petak Territory, dan watermark emblem benua di plat tengah.
- **Battle**: bingkai, petak sisi kita (nada dingin) dan sisi musuh (nada merah-ungu) tetap **mudah dibedakan di setiap skin** (dijaga oleh tes), garis deploy, Highland, dinding, motif di tiap sel, dan watermark emblem di tengah papan. Battle selalu memakai skin benua yang sedang dimainkan (duel di dalam match memakai benua match-nya, Battle Practice / Battle Chess memakai benua terpilih).
- Menambah atau mengubah skin cukup lewat `data/map_skins.json` (warna heksadesimal, `radius`, `pattern`, `motif_a`, `emblem_a`). Key yang hilang atau nama `pattern` yang tidak dikenal otomatis kembali ke tampilan lama (`MapSkin.DEFAULT_*`), jadi benua baru tanpa skin tidak merusak apa pun.
- Tes: `godot --headless --path . res://tests/skin_test.tscn` -> `SKIN TEST RESULT: PASS` (data lengkap, tiap benua unik, fallback, semua motif dan kedua papan benar-benar digambar). Screenshot semua benua: `xvfb-run godot --path . res://tests/skin_shots.tscn` (hasil di `/tmp/shots_skins`).

## Cara bermain (Phase 2)
- Roll Dice (2xD6). Double / event "Time Surge" = lempar lagi (maks 2 bonus).
- **Kartu Event** (12, `data/events.json`): Hidden Treasure, Royal Levy, Tailwind, Sudden Storm, Blessing of Fortune, Grand Festival, Bandit Ambush, Time Surge, Special Die, plus **Bull Market** (semua saham +20%), **Market Crash** (semua saham -20%), **Lucky Chip** (satu ronde Casino gratis dari game acak).
- Reroll Token: ulang lemparan sebelum bergerak (beli di Shop / event / passive Elarion).
- Wilayah kosong: **Beli** atau **Sewa**. Sewa (`balance.json` -> `lease_cost_ratio` 0,3 dan `lease_rounds` 4): bayar 30% harga, wilayah jadi milikmu selama 4 ronde dan menarik rent seperti biasa, lalu kembali kosong. Selama disewa: tidak bisa di-upgrade, tidak dihitung net worth, tidak dihitung bonus region (6/10 dan Dominion), tidak ikut dijual paksa saat bangkrut. Mendarat di wilayah sewaanmu sendiri menawarkan **Buy out** seharga sisa harga (harga - biaya sewa), yang membuatnya permanen. Menaklukkan wilayah sewaan lewat duel membuatnya permanen bagi penakluk; pemain yang tereliminasi melepas sewanya. AI Normal / Hard menyewa setengah waktu saat membeli akan menipiskan dompet dan masih ada sisa gold; AI Easy tidak menyewa. Tersimpan di save (`tiles` memuat sisa ronde dan biaya sewa; save lama tanpa sewa tetap bisa dimuat). Kode: `MatchController._do_lease` / `_do_redeem` / `_tick_leases`, `EconomySystem.lease_cost` / `redeem_cost`. Tes: `tests/rules_test.gd` (`_test_lease`). Wilayah lawan: bayar Tax (rent). Mayoritas region (6/10) x1.5, Regional Dominion (10/10) x2.5.
- **Portal**: tiap sisi hanya punya **1 portal** (4 di papan, selalu aktif); mendarat di sana bisa warp ke portal sisi lain.
- **Bank & Saham** (ikon grafik hijau, 2 per sisi = 8): investasi gold 100 / 250 / 500. Pasar bergerak tiap ronde (acak -20% s/d +30%, `stock_change_min/max`), berlaku untuk semua portofolio.
  Jual semua di Bank mana pun. Saham dihitung di net worth dan otomatis dicairkan lebih dulu saat harus bayar utang (sebelum tanah dijual). State: `PlayerState.stock_value/stock_basis`, `MatchController.market_change`, tersimpan di save.
- **Kartu Event & Special Die per benua** (`data/continent_flavor.json`, dimuat lewat `GameData.apply_flavor` saat match mulai / save di-load): tiap benua punya **12 kartu event dan 6 Special Die sendiri** (nama, efek, dan angka berbeda; set netral di `data/events.json` / `data/special_dice.json` hanya dipakai sebagai cadangan dan oleh tes). Ringkasan:
  - **Aetherion** (kerajaan): ekonomi stabil. Crown Tax (-10 G/teritori), Grand Tourney (+10 G/teritori), Royal Pardon (+1 Life). Dadu: Charger, **Decree** (rival bayar), Rogue (curi), **Tribute** (emas per teritori), Guild Broker, **Physician** (heal).
  - **Arcanum** (sihir): kacau & berisiko. Ley Line (warp portal), Wild Teleport (warp teritori acak), pasar +/-30%. Dadu: **Ritual** (token), Portal Spell, Mana Broker (swing besar), Binding, Oracle (fate), **Arcane Surge** (emas).
  - **Machina** (industri): Factory Inspection (-15 G/teritori), Factory Output (+15 G/teritori), Patent Sale (curi 50 G), Gear Jam. Dadu: Overclock, Piston, **Factory** (emas per teritori), **Ticker**, Saboteur, Spare Parts.
  - **Sylvaris** (alam): aman & menyembuhkan. Spring of Life (+2 Life), Bumper Harvest, Locust Swarm, tanpa kartu rugi emas langsung. Dadu: **Harvest**, **Healing Spring**, Vine, Seed Broker (stabil), Foraging, Spirit.
  - **Drakmor** (perang): angka besar. Dragon's Hoard (+250 G), Demon's Toll (-150 G), Pillage (curi 80 G), Victory Revel (+50 G/rival). Dadu: **Warlord**, Charge, Pillager, **Blood Fate** (+/-250..350), Spoils, Supply Line.
  - **Thalassia** (laut): gerak & badai. Fair Winds (+5), Tempest (-4), Whirlpool (warp portal), Becalmed (skip), Pirate Raid (-120 G). Dadu: **Tempest** (-2..+6), Whirlpool, Corsair, Merchant, **Treasure Dive**, Sea Charm.
  - **Eclipsia** (waktu): Time Loop (warp ke START + bonus), Echo Thief, Temporal Dividend (+8 G/teritori), 2 Reroll Token. Dadu: **Paradox** (START 2x), Epoch, **Fate Weave** (+/-150..400), Moment, **Futures** (swing -30..+100%), Chrono (-3..+6).
  Efek kartu baru: `gain_per_land`, `lose_per_land`, `steal_richest`, `heal`, `skip_turn`, `warp_portal`, `warp_land`, `warp_start`; jenis dadu baru: `land_gold`, `levy`, `tokens`, `gold`, `heal` (dadu `fate` boleh punya `fate_values` sendiri).
- **Destiny Die** (Special Die ke-5, `data/special_dice.json`): dadu nasib baik/buruk, dibeli di Shop / dari Event, dipakai sebelum lempar dadu. 1 = bencana (-200 G), 2 = sial (-100 G), 3 = mundur 3 petak (petak itu diproses), 4 = +100 G, 5 = +200 G, 6 = +300 G + Reroll Token. Nilai di `fate_values` / `fate_detour` (`data/balance.json`); rugi dibayar lewat `_pay` (saham dicairkan dulu, lalu tanah dijual). Tidak ada petak Fate di papan.
- **Casino** (tempat judi, ikon dadu merah, 1 per sisi = 4): **sama seperti tab Gamble di Shop**: tiap kali mendarat, game-nya **diundi acak** dari Coin Flip, Dice, atau Slots (`MatchController.random_casino_game`, disimpan di `pending["game"]`; aturan, payout, dan animasi sama, logika di `ShopSystem.gamble_round`, UI `scripts/ui/gamble_panel.gd`), tetapi dimainkan dengan **Dominion Gold** (bukan Chips) lewat overlay di Territory Board. Taruhan 50 / 100 / 250 / 500 G (`casino_bets` di `data/balance.json`); **hanya satu ronde per kunjungan**, setelah hasil keluar tekan *Continue* (`pending["played"]`). Syarat masuk: gold minimal taruhan terkecil. AI main sekali (game yang terundi, pilihan default, taruhan terkecil) bila kaya dan bukan Hard. Pot dan hadiah lama (x2 / x4 / pot) dihapus. Kartu **Lucky Chip** = satu ronde gratis dari game acak dengan taruhan terkecil (menang dibayar penuh sesuai payout, kalah tidak rugi).
- Bangkrut = jual wilayah otomatis; jika tetap kurang -> -1 Life + bailout. Life 0 = tereliminasi.
- Menang: lawan habis, atau saat batas ronde tercapai -> net worth tertinggi. Batas ronde berbeda per mode dan difficulty (Journey 20 / 30 / 40, Arena 30 / 40 / 50 untuk Easy / Normal / Hard; Tutorial 10).
- Ketuk petak mana pun di papan untuk info detail.

## Misi di papan teritori
Di kolom kanan papan teritori, tepat di bawah tombol **Menu**, ada **satu** kotak misi gabungan (`territory_board.gd`, `_refresh_mission`, `RichTextLabel` `_mission_text`): judul **MISSION**, lalu satu baris per misi. Baris **King** = misi level-up King pemain (level, tujuan, progres; sebelumnya baris "Mission:" di kartu pemain). Baris **Continent** (hanya Arena / Chaos) = misi benua (tujuan, progres, hadiah). Misi yang selesai berwarna hijau dengan tanda centang. Kartu pemain di kiri tidak lagi memuat misi.

## New Match (menu utama -> NEW MATCH)
Satu scene (`scripts/ui/match_setup.gd`) dengan dua tampilan. Tombol Back / Esc / tombol Back Android: dari setup kembali ke hub, dari hub ke menu utama.
- **Hub**: dua tab. **OFFLINE** berisi 4 kartu: **Journey**, **Arena**, **Battle Chess**, **Tutorial**. **ONLINE - COMING SOON** berisi **Classic**, **Ranked**, **Battle Chess**
  (kartu redup dan nonaktif, belum ada multiplayer). Di layar tinggi (tablet) tinggi kartu dibatasi dan dipusatkan (`CARD_MAX_H`).
- **Journey** (Story, selalu 1 vs 1): jalur trofi. Hanya benua pertama (Aetherion) yang terbuka di awal. Menang menambah trofi, kalah mengurangi (tidak pernah di bawah batas benua tertinggi yang sudah terbuka), dan benua terbuka otomatis saat trofi mencapai `unlock_trophies`-nya (Arcanum 150, Machina 400, Sylvaris 700, Drakmor 1100, Thalassia 1600, Eclipsia 2200). Benua yang dimainkan selalu benua terbaru yang terbuka (`SaveManager.journey_frontier`); faksi di Deck harus faksi benua itu.
- **Story Journey** (`StorySystem`, `StoryPanel`, `data/story.json`): kartu cerita melayang yang menemani pemain dari benua pertama sampai ketujuh: prolog, 7 bab (satu per benua, urutan Aetherion sampai Eclipsia) dan epilog. Bab terbuka saat benua itu terbuka di Journey; epilog terbuka saat jalur Journey tamat. Tombol **Story** ada di setup Journey (tanda NEW bila ada halaman belum dibaca) dan kartu terbuka sendiri sekali untuk bab baru. Halaman yang sudah dibaca disimpan di save (`story_seen`). Tes: `story_test`.
  Difficulty: level AI dipaksa menurut trofi (3 level di setiap benua, lihat bagian Difficulty Journey) sampai trofi melewati rentang Eclipsia (2800) dan pemain menang di Eclipsia dengan keempat faksinya; setelah itu pemain memilih sendiri. Setup Journey menampilkan **tabel "Difficulty by trophies"** di kolom Journey Map: satu baris per benua (baris benua saat ini dan sel level yang sedang aktif berwarna emas, benua terkunci diredupkan). Data tabel dari `SaveManager.journey_ladder()`. Rentang saat ini:

  | Benua | Easy | Normal | Hard |
  |---|---|---|---|
  | Aetherion | 0-49 | 50-99 | 100-149 |
  | Arcanum | 150-233 | 234-316 | 317-399 |
  | Machina | 400-499 | 500-599 | 600-699 |
  | Sylvaris | 700-833 | 834-966 | 967-1099 |
  | Drakmor | 1100-1266 | 1267-1433 | 1434-1599 |
  | Thalassia | 1600-1799 | 1800-1999 | 2000-2199 |
  | Eclipsia | 2200-2399 | 2400-2599 | 2600-2799 |
- **Arena**: match bebas melawan AI di **semua benua playable (semuanya terbuka di Arena)**, termasuk yang belum dibuka lewat Journey. Players: **1 vs 1**, **2 vs 2**, **4 Player**. **Tidak membuka apa pun**: benua yang masih terkunci di Journey tetap terkunci, dan **King (faksi) serta Pawn benua itu tetap terkunci** di Card Hub (baris benua di setup menulis "Open  -  King & Pawn stay locked"). Kemenangan tetap memberi koin, statistik, dan peti (bukan kartu Support). Random map mengundi dari semua benua playable (`MatchSetup._open_continents`, `_is_continent_open`). **Musuh AI Arena** diundi dari faksi **seluruh benua playable** (bukan hanya 4 faksi benua map; faksi pemain dikecualikan, tiap faksi paling banyak satu kursi): config `any_continent_enemies` (`GameSession.to_match_config`, hanya kategori Arena) dibaca `MatchController.setup`. Journey dan Tutorial tetap melawan faksi benua yang sama. Buff King / kartu / Faction Tier faksi asing tetap hanya aktif di benua asalnya.
  Flag `journey` ikut di config match (`GameSession.category`) dan di save/resume (`MatchController.journey`); `SaveManager.record_match(..., journey)` hanya membuka benua jika `journey` true.
- **Faksi tidak dipilih di New Match.** Kolom kanan setup hanya menampilkan faksi + King dari Deck (read-only) dan tombol **Change faction in Deck**
  (membuka Card Hub -> Deck -> tab Faction; Back kembali ke New Match lewat `GameSession.collection_return`, `open_deck_tab`).
- **Faksi dipilih di Deck**: tab **Faction** (dulu "King") di Card Hub menampilkan 28 faksi per benua. Faksi dari benua yang belum terbuka **terkunci** (tombol nonaktif,
  "Locked - unlock X in Journey") dan tidak bisa dipilih; faksi 4 benua yang terbuka bisa dipilih. Faksi terkunci terbuka otomatis saat benuanya dibuka lewat Journey.
  King pilihan = faksi pemain di setiap match dan di Battle Chess (`SaveManager.player_champion_id()` / `player_faction_id()`; King dari faksi terkunci di save lama jatuh kembali ke faksi terbuka pertama).
  Faksi pemain boleh dari benua lain daripada benua match. Lawan AI Arena (termasuk Chaos) diundi dari faksi SEMUA benua (`any_continent_enemies`); di Journey lawan tetap dari faksi benua match. `GameData.find_faction` mencari di semua benua.
- **Aturan home-continent** (`GameData.is_home_faction`): faksi tidak dibatasi benua dan bisa dimainkan di benua lain (hanya di luar Journey, mis. Arena; faksi tetap harus sudah terbuka).
  King asing = King yang faksinya bukan faksi benua match (`BattleEngine._home_bonus` = false). Yang tetap aktif untuk King asing: **passive King**, **Faction Tier**, **Grand Army (Faction)**, Role Synergy (trait role dan Role Pact), dan modifier benua.
  Yang mati untuk King asing: **buff King** (`king_buffs.json`) dan **buff kartu unit** (`card_buffs.json`).
  Faction Tier hanya menghitung unit yang faksinya SAMA dengan King (`BattleEngine._synergy`, `_faction_counts`). Grand Army (Faction) memakai hitungan terpisah semua faksi (`_continent_counts`) dan dinilai terhadap benua King ATAU benua match (`_army_active`), lihat bagian "Sinergi".
  Pawn memakai id yang sama di semua benua; faksinya mengikuti slot Pawn di **benua King** (`CardDatabase.effective_faction`), jadi Pawn King asing ikut faksi benua King.
  **Unit King asing**: pemain dengan King asing memakai loadout unit tersimpan untuk benua King (bila ada loadout kustom, `MatchController._init_army`), mis. King Astralis dengan unit Arcanum bermain di Aetherion; tanpa loadout itu dipakai dek benua match. Dek AI lihat bagian "Dek AI".
  **Journey wajib faksi asal**: tombol START MATCH nonaktif jika faksi di Deck bukan faksi benua Journey. Setup menampilkan catatan status bonus.
- **Battle Chess**: membuka scene Battle (sebelumnya "Battle Practice"; sekarang bukan latihan: setiap battle memberi Aether Coins). **Tutorial**: match panduan seperti sebelumnya.
- Perubahan perilaku: sebelumnya kemenangan di mode apa pun membuka benua berikutnya secara berurutan; sekarang hanya Journey yang membuka benua, lewat trofi. Benua yang sudah terbuka di save lama tetap terbuka dan trofi mulai dari batas benua tertinggi yang terbuka.
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
  **Skala bintang unit** (`star_hp_mult` / `star_atk_mult`): HP x1,0 / x1,4 / x1,9 dan ATK x1,0 / x1,2 / x1,4 (dulu HP x1,0 / x1,8 / x3,2 dan ATK x1,0 / x1,6 / x2,6). Dikecilkan supaya King dan Monster tetap lebih kuat dari unit mana pun. Unit terkuat (HP 290 / ATK 28): B2 = HP 406 / ATK 34, B3 = HP 551 / ATK 39; King terlemah (HP 310 / ATK 26): Lv 2 = HP 418 / ATK 32, Lv 3 = HP 558 / ATK 39; King / Monster terkuat Lv 3 = HP 882 / ATK 52. Pengali King / Monster (`commander_star_*`) tidak diubah. Belum diuji dengan Godot; kalibrasi menang-kalah belum diukur ulang.
- Kapasitas catur (`CapacitySystem`): Pawn 1, Rook/Knight/Bishop 2, Queen 4, King 6; level 3 = 9 ... level 10 = 30.
  Asumsi: King/Champion tidak dihitung ke kapasitas deploy (hanya masuk saat Last Stand) — konfirmasi di Phase 4.
- `BattleDeck`: tumpukan 135 kartu untuk Battle Shop (5 kartu per refresh, sisa kembali ke tumpukan).
- Main Menu -> Card Hub (dulu "Card Hub"; nama di `GameSession.CARD_HUB_NAME`): satu layar dengan empat tab: **Lineup** (tab pembuka: formasi awal 8x4 dan urutan kartu Support; hasil disimpan per benua), Collection (filter, detail, stat 1/2/3 bintang), Deck (pilih Champion + tepat 15 Support, simpan ke save), dan tab **Info** (panduan: aturan dek, **Territory** (dadu, jenis petak, rent/region, Tax-Duel-Conquest, cara menang), 7 role + skill, sinergi faksi/role, dasar battle; semua angka dibaca dari data game). Card Hub juga bisa dibuka dari **Territory Board** (tombol Card Hub di kolom pemain): tampil sebagai overlay, match berhenti sementara (tidak disimpan/dimuat ulang), benua match dipulihkan saat ditutup, dan dek yang disimpan berlaku untuk match berikutnya.
- Koleksi awal: semua unit x9 dan 15 dari 105 Support; 90 Support terkunci (cara membuka: Shop (Crystal); kemenangan match dan peti tidak lagi membuka kartu).

## Deck (Main Menu -> Card Hub -> tab Deck)
- Editor bergaya Clash Royale: **deck sebagai kartu visual di kiri** (grid 3 x 5, lencana biaya capacity di tiap kartu, "avg cost" di judul) dan **koleksi di kanan** (5 kolom).
  Tab: **Units n / 15** (filter per faksi), **Support n / 15** (filter per kategori), **Faction** (kartu faksi per benua dengan gaya yang sama; panel kiri menampilkan King terpilih + skill-nya; faksi terkunci diberi overlay LOCKED).
  Ketuk kartu koleksi untuk memasang (kartu yang sudah di deck tampak redup; ketuk lagi untuk melepas). Jika deck penuh, kartu itu "dipegang" dan semua slot menyala emas:
  ketuk satu kartu deck untuk menukarnya. Ketuk kartu di deck tanpa memegang kartu = melepasnya. Tooltip menampilkan skill/deskripsi.
- **Kartu Unit boleh lintas benua**: di tab Units, chip benua (Cards: <benua>) memilih kartu benua mana yang ditampilkan di pool, sedangkan isi dek tetap tersimpan; yang bisa dipasang = 8 Pawn + bidak dari semua faksi benua terbuka. Faksi dan benua **boleh dicampur** (15 tipe unit), dan 2 unit dari satu faksi di setiap ke-7 benua sekaligus di lapangan mengaktifkan Continent Alliance (efek benua King).
  Tiap benua map tetap punya susunan unit sendiri (disimpan per benua). Tiap tipe unit = 9 salinan (15 x 9 = 135).
- **King tidak terikat benua** (semua 28 King bisa dipilih) dan Support dipakai bersama semua benua. Total dek tetap 151 kartu.
- Save hanya aktif jika 15 unit + 15 support terisi. "Reset to default" mengembalikan unit bawaan faksi King.
- Di match, kartu unit pemain = susunan benua yang dimainkan; bila King asing dan ada loadout tersimpan untuk benua King, loadout itu yang dipakai. King mengikuti faksi yang dipilih di Deck; di Battle Chess King mengikuti pilihan di dek.
  **Dek AI**: dibuat sama seperti dek default pemain dari King-nya (15 tipe unit: 8 Pawn + 7 bidak faksi King, 9 salinan masing-masing). Bila King AI bukan dari benua match (Arena), unitnya tetap dari benua dan faksi King-nya (`MatchController._init_army`), bukan dari benua match; Pawn ikut faksi benua King sehingga tiap faksi benua King mendapat 2 Pawn.

## Battle System (Phase 4) — Main Menu -> New Match -> Offline -> Battle Chess (dulu "Battle Practice")
- **Duel multi-ronde di match (Journey / Arena / Chaos)**: duel antar-ruler dimainkan beberapa ronde menurut difficulty match, **Easy 5 / Normal 3 / Hard 1** (`ShopSystem.series_rounds`, `duel_context["difficulty"]`). Pasukan dan Gold asli dipakai di semua ronde (tanpa income), tiap ronde ada persiapan baru dan medan baru; musuh memakai pasukan yang sama. Pemenang duel = lebih banyak ronde menang daripada kalah; sama = seri (penyerang kalah, seperti aturan seri lama). Bonus gold dihitung dari ronde yang dimenangkan pemenang, `gold_delta` Support dijumlahkan. Duel AI vs AI otomatis (`MatchController.auto_duel`) memakai jumlah ronde yang sama. Tutorial dan duel monster tetap 1 ronde. Belum diuji dengan Godot.
- **Update di dalam game**: dialog gagal pasang punya tombol **Open browser** (cadangan: browser / Files memasang APK dengan izinnya sendiri), dan unduhan dicek terhadap Content-Length server. Bila menu *Install unknown apps* tidak ada untuk game, versi terpasang lebih lama dari izin `request_install_packages`: pasang APK terbaru sekali lewat browser. Belum diuji di perangkat.
- **Pion awal Battle Chess**: begitu battle mulai, pemain langsung mendapat `starter_units` = 3 Pawn acak dari dek (gratis, diambil dari tumpukan shop sehingga batas 9 salinan tetap terjaga; bila dek tanpa Pawn, unit apa pun). Kode: `BattlePrep.give_starter_pawns`, dipanggil di `BattleBoard._ready`. Belum diuji dengan Godot (tidak tersedia di lingkungan ini).
- Grid 8x8; kamu di baris 4-7 (area 4x8), lawan di baris 0-3. Tanpa kontrol manual: semua unit bergerak/menyerang sendiri.
- Persiapan (`BattlePrep`): Battle Shop 5 unit, Reroll, Buy/Sell, Level Up (kapasitas 9 -> 30), Preparation Area 10 slot,
  Deploy/Return (ketuk unit lalu ketuk petak), Auto Deploy. Satu mata uang (Dominion Gold); "budget" hanya batas belanja.
- Engine (`BattleEngine`, deterministik per seed): 1 tick = 0.25 detik; prioritas target per role (Assassin = HP terendah,
  Marksman/Mage = musuh terlemah dalam jangkauan, lainnya = terdekat), gerak mengikuti catur asli (`ChessMove`: Rook/Bishop/Queen meluncur jauh, Knight lompat L, King 1 petak, Pawn maju 2 petak di langkah pertama; Pawn yang jalannya tertutup boleh geser menyamping agar tidak macet), serang: SEMUA bidak memukul jarak dekat (8 petak di sekeliling) dan Rook/Knight/Bishop/Queen juga jarak jauh sesuai pola caturnya (slide berhenti di unit pertama, Knight melompati unit); Pawn dan King hanya jarak dekat, gerak lewat BFS,
  15 skill unit, dan sinergi bernama (`ComboSystem`, `scripts/systems/combo_system.gd`): lihat bagian "Sinergi" di bawah.
- **Summon King**: pemain bisa memanggil King lebih awal tanpa menunggu unit habis dengan membayar energy (`king_summon_energy` = 8, tombol di panel King; `BattleEngine.summon_king`). AI tetap hanya lewat Last Stand.
- **Champion Last Stand**: Champion otomatis masuk arena saat semua unit biasa pihaknya kalah (dan langsung masuk jika tanpa unit),
  lalu memakai skill aktifnya. Champion kalah = pihak itu kalah. Stat King (HP 310-490, ATK 26-35) sengaja lebih besar daripada unit mana pun (maks HP 290 / ATK 25); tidak ada lagi pengali x3 (`champion_hp_mult` = 1.0).
- **King di battle punya tiga hal terpisah**: **Pasif** (`data/king_passives.json`, aktif sejak battle mulai di benua mana pun: +HP/+ATK/-damage/shield untuk semua unit, atau +HP/+ATK King saat masuk); **Buff** (`data/king_buffs.json`, hanya di benua asal, melekat pada King saat masuk); **Aktif** = skill King
  (Sun Judgment, Starfall Decree, dst.) yang dipakai **manual, sekali** lewat tombol di panel King (kiri) setelah King masuk lewat Last Stand. Sisi AI / auto memakainya otomatis saat masuk.
  Engine: `manual_king` di cfg, `can_use_king_skill`, `use_king_skill`, `king_skill_used`; tes di `battle_test` (`_test_manual_king`).
- **Tombol Surrender di duel match**: di layar Battle, posisi tombol **Menu** (kolom samping atas) dipakai Battle Chess biasa; di duel dalam match Journey / Arena / Chaos (juga perburuan monster) tombol itu menjadi **Surrender**. Menekannya (atau Back di Android) membuka konfirmasi; setelah dikonfirmasi seluruh duel dihitung kalah (lawan menang, tanpa bonus gold; ronde yang sudah dimainkan tetap masuk tally gold) dan hasilnya dikirim seperti kekalahan biasa: penyerang yang kalah kehilangan 1 nyawa, penantang yang menyerah membiarkan lawan menang. Pembelian di fase prep tetap berlaku (gold/level disinkron sebelum menyerah). Perburuan monster: monster bertahan dan gold berkurang seperti kalah. Duel tutorial tidak punya tombol ini. Tes: `tests/ui_surrender_smoke.gd`.
- **Rate isi Battle Shop sesuai level pemain**: rarity tiap tawaran di Battle Shop (unit dan Support) diundi dulu dari tabel `shop_rarity_odds` di `data/balance.json` menurut **level toko** (level yang dinaikkan dengan tombol Level Up), baru kartu dengan rarity itu diambil dari tumpukan (`BattleDeck.draw_shop(count, level)`, `BattleDeck.odds_for_level`). Rarity yang sudah habis di tumpukan dilewati dan peluangnya dibagi ulang, jadi toko selalu terisi dan satu unit tetap maksimal 9 kopi. Tabel (persen Common / Rare / Epic / Legendary):

  | Level | Common | Rare | Epic | Legendary |
  |---|---|---|---|---|
  | 3 | 75 | 25 | 0 | 0 |
  | 4 | 65 | 32 | 3 | 0 |
  | 5 | 55 | 37 | 8 | 0 |
  | 6 | 45 | 40 | 14 | 1 |
  | 7 | 35 | 42 | 20 | 3 |
  | 8 | 25 | 42 | 27 | 6 |
  | 9 | 18 | 37 | 35 | 10 |
  | 10 | 10 | 30 | 40 | 20 |

  Kartu unit hanya Common / Rare / Epic (tidak ada unit Legendary), jadi persen Legendary di level tinggi hanya berlaku untuk kartu Support dan di unit dibagi ulang ke rarity lain. Legenda rarity di atas daftar toko menampilkan persen level saat ini (tooltip menjelaskan); odds baru berlaku di Reroll / ronde berikutnya, bukan langsung mengganti tawaran yang sedang tampil. Berlaku di semua layar Battle (Battle Chess, duel di Territory Board, dan toko AI, karena memakai `BattlePrep` yang sama). `BattleDeck.level_odds_enabled = false` mengembalikan undian rata. Tes: `tests/shop_odds_test.gd`. **Level toko AI mengikuti level pemain**: di duel match (Journey / Arena / Chaos) AI berbelanja di level pemain manusia (`BattleAI.prepare_ai_army(..., follow_level)`, `MatchController.human_level()` = level tertinggi pemain manusia), seperti musuh Battle Chess; kapasitas dan odds rarity AI ikut level itu, sedangkan armadanya tetap tumbuh lewat anggaran (rasio gold per difficulty). Tanpa pemain manusia (simulasi AI vs AI) AI naik level sendiri seperti dulu (maks Lv 7). Pengukuran level AI (Arena vs Chaos, tiap difficulty): `godot --headless --path . res://tests/level_sim.tscn -- 30`.
- **Support di Battle Shop**: kartu Support dari Deck **muncul di roll Battle Shop** bersama bidak (tiap slot ada peluang `shop_support_chance` = 20%), tidak lagi dibagikan acak 3 kartu.
  Dibeli dengan gold (`support_price`: Common 40, Rare 100, Epic 220, Legendary 450) dan **butuh level** (`support_level_req`: Common 3, Rare 5, Epic 7, Legendary 9; kartu di atas level tampil terkunci).
  Kartu masuk **hand** (maks `hand_max` = 5), disimpan antar duel sampai dimainkan manual di battle (sekali). Kartu yang dimainkan terpakai dan kembali ke tumpukan shop.
  Hand bisa dijual (50%) di panel persiapan; Mercenary Pact dan Merchant Contract langsung berlaku saat dibeli (tidak bisa dijual). AI membeli Support lewat shop yang sama.
  Kode: `BattleDeck.support_pool` / `draw_shop`, `BattlePrep.hand` / `can_buy` / `buy` / `consume_used`, `PlayerState.hand` (ikut save/resume: `spile`, `hand`); tes `battle_test._test_shop_supports`.
- **Energi Support di battle**: tiap sisi punya bar Energy (maks `energy_max` = 10, mulai `energy_start` = 2) yang terisi +1 tiap `energy_regen_ticks` = 8 tick (2 detik). Memainkan kartu Support memakai energi menurut rarity (`support_energy_cost`: Common 3, Rare 5, Epic 7, Legendary 9). Bar penuh tidak menambah apa pun (energi terbuang), jadi pemain memilih: pakai kartu murah sekarang atau menabung untuk kartu mahal. AI memakai aturan yang sama (memainkan kartu termahal yang mampu dibayar). Kode: `BattleEngine.energy`, `support_energy_cost`, `_regen_energy`; tes `battle_test._test_energy`; cfg tes `free_supports` menghapus biaya.
- **Combo Support**: memainkan kartu Support dari kategori yang sama berturut-turut dalam `combo_window_ticks` = 20 tick (5 detik) dari kartu sebelumnya memperpanjang rantai. Kartu ke-n dalam rantai mengembalikan min(n-1, `combo_refund_max` = 2) energi. Kategori lain atau terlambat = rantai mulai lagi dari 1 (tanpa refund). Panel battle menampilkan combo dan sisa waktunya; AI memilih kartu sekategori dulu bila bisa melanjutkan rantai. Kode: `BattleEngine.combo_*`; tes `battle_test._test_combo`.
- **Skill aktif King juga memakai energi** (`king_skill_energy` = 6, sumber energi yang sama dengan Support). Pemain menekan tombol skill saat King sudah masuk dan energi cukup; tombol menampilkan biaya dan sisa energi. King AI menahan skill-nya sampai energi cukup lalu melepasnya otomatis, dan AI tidak memainkan Support selagi Kingnya menunggu. `free_supports` (tes) juga membuat skill King gratis.
- Support card yang sudah berfungsi: Fireball (area_damage), Arcane Heal (heal_all), Battle Cry (team_atk),
  Blessing of Light (shield_all), Summon Recruits (summon_pawns), Fortune's Favor (gold_on_win). (Catatan lama: sejak Phase 6 SEMUA 21 efek Support berfungsi.)
- Lawan AI membangun pasukan lewat shop yang sama (budget easy 250 / normal 450 / hard 700) dan memakai Support.
- Diuji: 90 pertarungan AI-vs-AI selesai (terlama 85 tick), tanpa tumpang-tindih sel, aturan Last Stand tidak pernah dilanggar,
  tidak ada bias sisi (43/47), seed sama = hasil sama.

## Sinergi (`ComboSystem`)
**Semua sinergi adalah efek spesial, bukan bonus stat** (tidak ada bonus HP / ATK / shield / move / range). Efek semua sinergi aktif ditambahkan; mesinnya sama dengan buff kartu benua (`BattleEngine._x`, `BattleUnit.fx`). Bentuk data efek: `{"to": "all" atau daftar role, <efek>: nilai}`.

**Efek** (`ComboSystem.FX_TYPES`): armor (damage diterima -x), evade (setiap hit ke-N dihindari), thorns (memantulkan x damage), execute (+x damage ke musuh di bawah 30% HP), frenzy (+x ATK per kill, maks 5), rage (+x ATK di bawah setengah HP), aura_atk (unit di sebelahnya +x ATK), burn (x ATK tiap 4 tick selama 12 tick), stun_proc (setiap serangan ke-N membuat target pingsan 1 tick), splash (x damage ke musuh di sebelah target), lifesteal, chill (target diperlambat x tick), opener (serangan pertama +x), last_rites (saat mati menyembuhkan sekutu di sebelahnya x% HP), death_burst (saat mati meledak x ATK ke musuh di sebelahnya), mend_self (menyembuhkan diri x% HP tiap 8 tick), guard (sekutu dalam 2 petak -x damage), second_life (bangkit sekali dengan x% HP).
Nilai berupa pecahan (0,10 = 10%), kecuali hitungan (evade, stun_proc: makin kecil makin kuat, tidak pernah di bawah `FX_COUNT_MIN` = 3) dan durasi (chill). Penumpukan: hitungan ambil yang terendah, chill dan second_life ambil yang tertinggi; batas atas di `FX_CAP` (armor 60%, guard 50%, second_life 90%, thorns 100%).

**1. Faction Tier** (`faction_tier`): trait faksi per tier **Rally 2 / Legion 4 / Host 6 / Ultra** unit SEFAKSI dengan King (unit faksi lain tidak mendapat Faction Tier). Satu baris di panel COMBOS, log battle, dan tab Info; tanpa bonus HP / ATK flat. Tetap aktif di benua mana pun, juga untuk King asing. Pawn ikut faksi slot-nya di benua King. Trait tiap faksi (`FACTION_TRAITS`, nilai Rally / Legion / Host; hanya mengenai unit faksi itu):

| Faksi | Trait | Efek |
|---|---|---|
| Solvaris | Dawn Ward | semua: mend_self 2/3/4% |
| Nocthyr | Nightfall | Assassin/Marksman: opener 15/30/50% |
| Valdoria | Rally the Banner | Fighter: aura_atk 3/5/8%; Support: mend_self 2/3/5% |
| Elarion | Moonlit Focus | Mage/Controller: chill 2/3/4 tick |
| Astralis | Astral Drift | Mage/Marksman: evade tiap ke-6/5/4; Mage: splash 0/0/20% |
| Ignivar | Wildfire | semua: burn 5/8/12% |
| Cryndel | Frost Armor | Tank/Fighter/Support: armor 4/7/10%; Tank/Fighter/Support: chill 0/2/3 tick |
| Umbrael | Umbral Step | Assassin/Mage: evade tiap ke-6/5/4; Assassin: opener 0/0/40% |
| Ferrum | Forged Hulls | semua: armor 2/4/6% |
| Voltrix | Overcharge | Marksman: stun_proc tiap ke-6/5/4 |
| Chronex | Time Dilation | Tank/Fighter/Assassin: evade tiap ke-6/5/4; Tank/Fighter/Assassin: opener 0/0/30% |
| Nexaris | Linked Network | Controller/Support: aura_atk 3/5/8%; semua: mend_self 1/2/3% |
| Verdantia | Lifebloom | Support/Controller: mend_self 3/5/8% |
| Besthara | Pack Instinct | Fighter/Assassin: frenzy 3/5/8% |
| Floralis | Petal Veil | Support/Mage/Marksman: guard 3/5/8% |
| Terragorn | Stone Skin | Tank/Fighter: armor 4/7/11% |
| Drakhan | Dragon's Might | semua: rage 5/10/15% |
| Inferna | Hellfire | semua: death_burst 15/30/50% |
| Bloodfang | Bloodlust | Fighter/Assassin: lifesteal 4/7/10% |
| Warborn | War Cry | semua: aura_atk 2/3/4% |
| Abyssal | Crushing Depths | Tank/Mage: thorns 5/10/16% |
| Pelagia | Tidal Blessing | Support/Controller/Mage: mend_self 2/3/5% |
| Tempestra | Storm Surge | Assassin/Fighter: stun_proc tiap ke-7/6/5 |
| Corsaria | Plunder | semua: execute 8/12/20% |
| Solstice | Radiant Zenith | Tank/Support: armor 3/5/8%; semua: last_rites 3/5/8% |
| Paradox | Paradox Loop | Marksman/Mage/Controller: evade tiap ke-7/6/5; Marksman/Mage/Controller: second_life 0/0/30% |
| Eternis | Eternal Bulwark | Tank/Support/Mage: armor 3/5/8%; Tank/Support/Mage: second_life 0/0/25% |
| Oblivion | Void Hunger | Assassin/Mage: lifesteal 5/8/12%; Assassin/Mage: execute 5/10/15% |

**Tier Ultra (tier teratas Faction Tier)** (`ULTRA_MIN` = 8 unit, `ULTRA_SCALE` = 1,5): aktif bila SEMUA unit lineup (minimal 8) berasal dari faksi King. Trait faksi di kekuatan Host dibuat x1,5 (persentase dan durasi x1,5, hitungan dibagi 1,5 dan tidak di bawah 3). Ditambah **bonus Ultra** (bagian dari tier Ultra, bukan sinergi terpisah; flat, tidak ikut x1,5, hanya di Ultra): semua unit lifesteal 8% dan frenzy 4%. Ultra tidak bersama Grand Army (Faction), karena Ultra butuh satu faksi saja.

**2. Trait role** (`ROLE_TRAITS`): satu per role, tier 2 / 4 / 6 unit satu role dan tier **Ultra** (satu role tidak perlu satu faksi):

| Role | Trait | 2 unit | 4 unit | 6 unit |
|---|---|---|---|---|
| Tank | Iron Wall | Tank: armor 5% | Tank: armor 10%, thorns 10% | Tank: armor 15%, thorns 20% |
| Support | Guardian Aura | Support: mend_self 3% | Support: mend_self 5%; semua: armor 3% | Support: mend_self 7%; semua: armor 5% |
| Assassin | Shadow Strike | Assassin: execute 15% | Assassin: execute 30%, opener 25% | Assassin: execute 50%, opener 50% |
| Mage | Arcane Surge | Mage: splash 15% | Mage: splash 25% | Mage: splash 40%, burn 15% |
| Marksman | Pinning Shot | Marksman: chill 3 tick | Marksman: chill 5 tick, frenzy 4% | Marksman: chill 6 tick, frenzy 6% |
| Fighter | Warband | Fighter: frenzy 4% | Fighter: frenzy 7%, rage 15% | Fighter: frenzy 10%, rage 30%, lifesteal 10% |
| Controller | Tactician's Command | Controller: stun_proc tiap ke-5 | Controller: stun_proc tiap ke-4, aura_atk 5% | Controller: stun_proc tiap ke-3, aura_atk 8% |

**Tier Ultra (tier teratas trait role)** (`ULTRA_MIN` = 8 unit, `ULTRA_SCALE` = 1,5): aktif bila SEMUA unit lineup (minimal 8) memakai role yang sama. Trait role di kekuatan 6 unit dibuat x1,5 (persentase dan durasi x1,5, hitungan dibagi 1,5 dan tidak di bawah 3). Ditambah **efek spesial Ultra** per role (flat, tidak ikut x1,5, hanya di Ultra): Tank **Unbreakable** (Tank bangkit sekali di 30% HP); Support **Sanctuary** (seluruh pasukan armor 5%); Assassin **Phantom Rush** (evade tiap hit ke-3, opener +50%); Mage **Arcane Overreach** (burn 20%, splash 20%); Marksman **Deadeye Volley** (execute +30%, chill 4 tick); Fighter **Berserk Charge** (rage +40%, lifesteal 12%); Controller **Grand Strategy** (setiap serangan ke-6 seluruh pasukan membuat target pingsan).

**3. Role Pact** (`DUO_COMBOS`, 21 kombo): 6 unit dari KEDUA role (`DUO_UNITS` = 6); setiap pasangan dari 7 role punya kombo (21). **Grand Army (Role)** bukan Role Pact, ia bagian dari sinergi **Grand Army** (lihat **4**).

| Kombo | Syarat | Efek |
|---|---|---|
| Frontline Shield | Tank + Support | semua: armor 6% |
| Glass Cannon | Assassin + Mage | Assassin/Mage: burn 15%, death_burst 40% |
| Sniper's Nest | Marksman + Tank | Marksman: opener 40%, evade tiap ke-5 |
| Pincer Strike | Assassin + Fighter | Assassin/Fighter: stun_proc tiap ke-4 |
| Arcane Ward | Mage + Support | Mage: evade tiap ke-5 |
| Battle Plan | Controller + Fighter | Fighter: frenzy 5% |
| Vanguard Line | Tank + Fighter | Fighter: thorns 10%; Tank: guard 6% |
| Command Post | Controller + Tank | Tank: armor 8% |
| Field Medic | Support + Fighter | Fighter: mend_self 4% |
| Lifeline | Marksman + Support | Marksman: lifesteal 10% |
| Spellblade | Mage + Fighter | Mage/Fighter: burn 12% |
| Crossfire | Marksman + Assassin | Marksman/Assassin: execute 20% |
| Arcane Tactics | Controller + Mage | Mage: chill 3 tick; Controller: mend_self 4% |
| Ambush Plan | Assassin + Controller | Assassin: opener 50% |
| Spell Bastion | Tank + Mage | Mage: armor 8%; Tank: thorns 10% |
| Supply Line | Support + Controller | semua: mend_self 2% |
| Bait and Strike | Tank + Assassin | Tank: thorns 15%; Assassin: opener 30% |
| Alchemist's Fire | Assassin + Support | Assassin: burn 20% |
| Hold the Line | Fighter + Marksman | Fighter: armor 8%; Marksman: execute 15% |
| Ranged Barrage | Mage + Marksman | Mage/Marksman: splash 15% |
| Target Painting | Marksman + Controller | Marksman: execute 20%; Controller: chill 4 tick |

**4. Grand Army** (satu keluarga sinergi, dua versi): seluruh pasukan bertempur bersama. Keduanya **bukan** Role Pact dan masing-masing punya konstanta sendiri.

| Versi | Konstanta | Syarat | Efek (seluruh unit) |
|---|---|---|---|
| Grand Army (Role) | `ROLE_ARMY` | 2 unit dari tiap 7 role (`ROLE_ARMY_UNITS` = 2, 14 unit), jadi semua trait role aktif sekaligus | armor 5%, lifesteal 5% |
| Grand Army (Faction) | `FACTION_ARMY` | SETIAP faksi dari satu benua punya minimal `FACTION_ARMY_MIN` = 2 unit dan total faksi itu minimal `FACTION_ARMY_TOTAL` = 8 unit (4 faksi x 2), jadi semua Faction Tier aktif sekaligus | last_rites 10%, mend_self 3% |

Versi Role dihitung dari role (`ComboSystem.active`, jenis `"army"`, `duo_mods` tidak memasukkannya) dan hanya 2 unit per role karena 7 x 6 melebihi kapasitas 30. Versi Faction dinilai terhadap benua King ATAU benua yang dimainkan (`BattleEngine._army_active`; panel Synergy menampilkan yang paling dekat terpenuhi), jadi King asing juga bisa mengaktifkannya. Hitungannya `BattleEngine._continent_counts` (semua faksi benua, bukan hanya faksi King) dan `ComboSystem.faction_army_active / faction_army_lacking`. Keduanya bertumpuk dengan semua sinergi lain, tetapi versi Faction **tidak** bersama tier Ultra (Faction Tier), karena Ultra butuh satu faksi saja.

**5. Continent Alliance** (`CONTINENT_BONDS`, `ComboSystem.bonds_for`, `bond_missing`): satu sinergi yang menyatukan ke-7 benua. Aktif bila di lapangan ada **2 unit dari SATU faksi di SETIAP benua** (`BOND_FACTION_UNITS` = 2; faksi mana pun dari benua itu, jadi 2 x 7 = 14 unit minimal; Pawn dan bidak bersama dihitung sebagai faksi King; unit tanpa faksi tidak dihitung). **Efeknya tergantung King**: seluruh unit mendapat efek bond **benua asal King** (hanya satu efek, lihat tabel), bukan efek benua lain. Contoh: King Drakhan (Drakmor) -> semua unit War Fever (rage 8%); King Solvaris (Aetherion) -> semua unit Royal Standard (armor 3%). Bertumpuk dengan semua sinergi lain, termasuk tier Ultra. Panel COMBOS menampilkan progres "Continent Alliance: n / 7 continents" bila sudah ada 2+ benua yang tercukupi. **Dek boleh berisi kartu unit dari benua mana pun** (`Deck.validate`, `CardDatabase.any_unit_ids`): di tab Deck, baris chip "Cards: <benua>" memilih kartu benua mana yang ditampilkan di pool, dan isi dek tetap tersimpan. Bidak dari benua lain bertarung tanpa buff kartu benua map yang dimainkan (`BattleEngine._spawn_unit`). Efek per benua King:

| Benua King | Nama | Efek (semua unit) |
|---|---|---|
| Aetherion | Royal Standard | armor 3% |
| Arcanum | Arcane Resonance | splash 10% |
| Machina | Clockwork Precision | opener 15% |
| Sylvaris | Verdant Renewal | mend 2% |
| Drakmor | War Fever | rage 8% |
| Thalassia | Undertow | chill 2 tick |
| Eclipsia | Time Slip | evade tiap ke-8 |

Logika: `BattleEngine._continent_unit_counts` (log `synergy: Continent Alliance`), `ComboSystem.bonds_for`, panel Synergy dan tab Info. Tes: `rules_test`.

**6. Continent Specialty** (`CONTINENT_ROLE_COMBOS`, 6 sinergi): satu benua dipasangkan dengan role yang cocok dengan temanya. Aktif bila **kedua syarat** ini terpenuhi di lapangan: **6 unit dari satu faksi milik benua itu** (`CONTINENT_ROLE_FACTION_UNITS` = 6) **dan 6 unit dari role yang cocok** (`CONTINENT_ROLE_UNITS` = 6, unit role boleh dari faksi mana saja). Unit faksi yang kebetulan memiliki role itu dihitung untuk kedua syarat sekaligus. Pawn dan bidak bersama dihitung sebagai faksi King (seperti Continent Alliance). **King tidak harus dari benua itu**, dan efeknya mengenai unit dengan role tersebut (bukan seluruh pasukan). Keduanya setara ukuran Host (6) pada Faction Tier dan trait role, jadi ini sinergi tahap akhir. Bertumpuk dengan semua sinergi lain (trait role, Role Pact, Faction Tier, Bond, Ultra). Semuanya efek spesial, bukan bonus stat:

| Kombo | Benua + role | Efek (unit dengan role itu) |
|---|---|---|
| Royal Bulwark | Aetherion + Tank | guard 6% (sekutu dalam 2 petak), thorns 8% |
| Rune Cascade | Arcanum + Mage | splash 20%, chill 2 tick |
| Clockwork Command | Machina + Controller | aura_atk 6%, chill 3 tick |
| Living Grove | Sylvaris + Support | mend_self 5%, last_rites 10% |
| Dragonfire Horde | Drakmor + Fighter | rage 20%, death_burst 30% |
| Rift Ambush | Eclipsia + Assassin | evade tiap ke-5, opener 30% |

Thalassia dan role Marksman belum punya pasangan (ada 7 benua tetapi hanya 6 kombo); menambahnya cukup satu entri di `CONTINENT_ROLE_COMBOS`. Di panel COMBOS layar Battle kombo aktif tampil sebagai baris "Nama Benua xN + Role xM efek", dan kombo yang kurang paling banyak 3 unit (dengan progres di kedua syarat) masuk baris "Close". Tab Info > Synergies memuat bagian "Continent Specialties".

Logika: `BattleEngine._continent_role_counts` (log `synergy: <nama> - <Benua> <Role>s`), `ComboSystem.continent_role_active / continent_role_lacking / continent_role_combo`, parameter `cont_combos` + `unit_cont` di `ComboSystem.unit_mods`. Tes: `rules_test` (`_test_combos`, `_test_continent_role_engine`).

**7. Continent Formation** (`CONTINENT_FORMATIONS`, `ComboSystem.formation_active / formation_effects_for / formation_lacking`): **4 unit dari SATU faksi yang berasal dari benua yang SAMA dengan King** (`FORMATION_UNITS` = 4; faksi King sendiri atau faksi lain di benuanya; faksi dari benua lain tidak berlaku, dan tanpa King tidak ada formasi) memberi **unit faksi itu** efek spesial bertema benua King. Hanya mengenai unit faksi tersebut (unit lain tidak ikut). Dua faksi dari benua King dengan 4 unit masing-masing sama-sama mendapat formasi. Pawn slot dan bidak bersama dihitung sebagai faksi King (`CardDatabase.effective_faction`). Bertumpuk dengan semua sinergi lain, termasuk trait faksi. Berbeda dari Faction Tier (hanya faksi King, trait per faksi, dari 2 unit), Continent Alliance (semua benua) dan Continent Specialty (6 + 6 unit, per role); ini sinergi tahap awal-menengah.

| Benua | Formasi | Efek (unit faksi itu) |
|---|---|---|
| Aetherion | Crown Phalanx | armor 4%, guard 3% |
| Arcanum | Runic Circle | splash 12%, burn 5% |
| Machina | Gear Lock | opener 20%, stun_proc tiap ke-8 |
| Sylvaris | Rootbound Ring | mend_self 3%, last_rites 5% |
| Drakmor | Warband Frenzy | frenzy 4%, rage 6% |
| Thalassia | Riptide Wall | chill 2 tick, thorns 5% |
| Eclipsia | Twilight Veil | evade tiap ke-7, execute 6% |

Logika: `BattleEngine._faction_unit_counts` (log `synergy: <nama formasi> - <Faksi> xN`) dan parameter `formation` di `ComboSystem.unit_mods`. Panel Synergy di layar Battle menampilkan baris formasi aktif dan "Close" bila kurang 1 unit; tab Info > Synergies memuat bagian "Continent Formation". Tes: `rules_test`.

Angka-angka ini belum diseimbangkan lewat banyak simulasi; semuanya ada di `combo_system.gd`. Tab Info (Synergies) dan panel Synergy di layar Battle dibaca dari data yang sama.

## Game Loop (Phase 5) — Territory Encounter & Duel
- Berhenti di wilayah lawan -> **pemilik** memilih **Tax** atau **Duel** (UI menampilkan tombol untuk pemain yang berhak menjawab).
- Pemilik memilih Duel -> pengunjung boleh **Accept** atau **Refuse** (bayar rent + penalti `refuse_duel_penalty`, bisa diatur di `balance.json`).
- Duel = auto battle 8x8 antar **pasukan permanen** pemain: unit yang dibeli dengan Dominion Gold tetap dimiliki antar duel.
  Persiapan duel memakai batas belanja `battle_budget_ratio` (50% gold) untuk manusia; AI memakai rasio per tingkat kesulitan.
  Duel yang melibatkan pemain manusia tampil sebagai overlay Battle; duel AI vs AI diselesaikan instan (hasil masuk log).
- Penyerang menang -> **Conquest** (ambil wilayah) atau **Victory Reward** (gold = 75% dari harga wilayah + total biaya upgrade, wilayah tetap dan levelnya tetap). Saat Conquest, level upgrade wilayah direset ke 0.
- Saat pemain manusia tidak bisa membayar (Tax, Refuse Duel, event kehilangan gold), muncul pilihan **utang**: jual lahan satu per satu (harga + upgrade x sell_ratio, level kembali 0), cairkan saham, **beli nyawa** (harga Restore Life), lalu **Pay**. Pilihan *Sell everything and settle* menjual semua lahan secara otomatis; bila masih kurang, kehilangan 1 Life dan bailout.
- **Chaos Mode**: kartu sendiri di New Match > Offline, di sebelah kanan Arena. Pertandingan Arena (benua, taruhan, hadiah sama) di papan 40 petak: 4 sudut + 9 petak per sisi, 5 Territory per wilayah (majority 3, Regional Dominion 5), **tanpa Portal** (petak portal diganti Territory; Crossroads dan kartu event "warp portal" tetap warp, tetapi ke **tempat acak** (petak non-sudut mana pun selain posisi sekarang, lalu petaknya diproses). Giliran pertama diacak di Journey/Arena/Chaos (`random_first`, `first_seat`; ronde berakhir saat giliran kembali ke seat pembuka). Bintang King (Lv 1-3) tampil di token pertarungan, panel King, dan kartu pemain seperti bintang unit (`CommanderSystem.stars_marks` / `star_info`). Android: mode immersive (bar sistem tersembunyi) jadi default dan diterapkan ulang saat aplikasi kembali aktif (`SaveManager.fullscreen_wanted`, `_reapply_immersive`); toggle Fullscreen di Settings tetap bisa mematikannya. Odds taruhan FFA x2,5 (Chaos x0,75), hadiah Chaos x0,5 (`chaos_reward_mult`) dan chest satu tingkat lebih rendah; simulasi keseimbangan: `godot --headless --path . res://tests/balance_sim.tscn -- 200`. Ganti nama profil: tombol "Rename" di dialog profil (`ProfileView.open_rename`, `SaveManager.set_profile_name`, maks 16 karakter); berlaku untuk match yang dimulai setelahnya. Kombo sinergi dirombak jadi kombo bernama (lihat `ComboSystem`). Penyeimbangan: batas ronde 12/16/20 (easy/normal/hard), harga Territory ×2 (`chaos_price_mult`), bonus Gate 80 G (`chaos_start_bonus`). Dipilih lewat `GameSession.chaos_mode`; disimpan di save (`chaos`). **Temuan tersembunyi di Chaos** (hanya 20 Territory): monster (juga berlaku di Arena 100 petak, bukan Journey): 1v1 = `arena_monster_count_duel` 2 (region acak), 4 Player dan 2vs2 = `arena_monster_count_multi` 4 (satu per region), tambang/harta jadi `chaos_deposit_count` = 2 (1 harta karun + 1 tambang), nilai emas x`chaos_deposit_gold_mult` = 2,0 (mengikuti harga Territory), durasi tambang x`chaos_mine_rounds_mult` = 0,5 (min. 3 ronde); Arena tetap 4 monster + 4 temuan. Petak layanan Chaos: Event 4, Portal 0, dan masing-masing 2 untuk Bank / Tax / Special / Shop / Casino / Auction (sisi genap pola A, sisi ganjil pola B). Journey dan Tutorial selalu 100 petak.
- Pemain yang kalah duel kehilangan 1 Life (spesifikasi bagian 6). Jika penyerang kalah: wilayah tetap. Jika pemilik kalah: penyerang
  memilih Conquest/Reward. `defender_loses_life=false` mengembalikan aturan "hanya penyerang yang kehilangan Life" (bagian 12).
  Life 0 = tereliminasi. Heal Life lewat Territory Shop (`heal_price`).
- AI memutuskan Tax/Duel/Accept/Refuse dari estimasi kekuatan pasukan (`BattleAI.army_power`), jumlah Life, dan tingkat kesulitan.
- Pemenang game: pemain terakhir yang hidup, atau net worth tertinggi saat batas ronde tercapai. **Batas ronde berbeda per mode dan difficulty** (`balance.json` -> `round_limit_by_mode`, `GameData.round_limit_for`, dikirim lewat `GameSession.to_match_config` -> `round_limit`): Journey Easy 20 / Normal 30 / Hard 40; Arena Easy 30 / Normal 40 / Hard 50; Chaos Easy 12 / Normal 16 / Hard 20. Tutorial tetap 10; `max_rounds` (30) hanya cadangan jika config tidak membawa `round_limit`. Match yang disimpan membawa `round_limit`-nya sendiri.

## Level King (Lv 1-3) = misi per faksi, di semua mode
- Lv 1 -> 2 -> 3 selalu lewat **dua misi berurutan milik faksi King** (`data/commander_missions.json`, 28 faksi, tiap faksi pasangan misinya berbeda; faksi tanpa entri memakai `commander_missions` di `balance.json`). Progres hanya dihitung saat misi itu aktif. Solvaris tetap memakai pasangan awal (menang 2 Duel, lalu bangun 1 Landmark).
- Tiap misi punya dua versi: **Territory match** (Journey / Arena / Chaos, metrik `duel_wins`, `landmarks`, `upgrades`, `auctions`, `special_dice`, `conquests`, `bank_deposits`, `bets`, `leases`) dan **Battle Chess** (metrik `bc_wins`, `bc_kills`, `bc_king_skill`, `bc_survivors`, dihitung per ronde lewat `BattleBoard._bc_mission_update` dan `CommanderSystem.add_progress_battle`).
- **Battle Chess**: level King pemain naik lewat misi (tidak lagi otomatis per ronde); level baru berlaku mulai ronde berikutnya pada run 10 Rounds / Survival, **battle tunggal tetap Lv 1**. King musuh tetap naik otomatis menurut ronde (Lv 2 dari ronde 4, Lv 3 dari ronde 7). Misi aktif tampil di status persiapan dan layar hasil.
- UI: kartu King di Collection / Deck menampilkan kedua misi faksinya (versi Territory dan Battle Chess). Tes: `rules_test` (`_test_commander`).

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
  (board terpotong di 720 px) dan HUD tidak memakai lebar ekstra di layar lebar. Screenshot ada di `docs/screenshots/` (dibuat ulang dari game lewat `layout_test -- shots`, `newmatch_shots` dan `docs_shots`; `docs_shots` membuat screenshot unlock Journey, Collection dan papan teritori penuh).
- Performa (desktop; ponsel kelas bawah ~5-10x lebih lambat): tick battle terburuk 1.3 ms (timer 250 ms), satu game AI penuh 76 ms,
  satu duel AI instan <= 13 ms, memori logika ~18 MB, 0 kebocoran setelah 40 game dan 75 siklus buat/hapus scene.
  `low_processor_mode` aktif (hemat baterai), max FPS 60, renderer GL Compatibility.
- **Cek update** (`UpdateCheck`, `UpdateInstaller`): di Android, saat aplikasi dibuka (bisa dimatikan lewat Settings -> Auto-check updates, dan versi tertentu bisa dilewati) game membaca GitHub Release terbaru (aset `MultiverseDominion.apk`); bila versinya lebih baru, menu utama menawarkan unduh di dalam game lalu membuka installer Android (pemain tetap menekan konfirmasi sekali; perlu izin "Install unknown apps"). Jika offline atau gagal, ada jalan keluar ke halaman Release di browser. Tes: `update_test`.
- Ekspor: `export_presets.cfg` (arm64-v8a + armeabi-v7a, permission INTERNET saja (cek update), tests/tools dikecualikan); paket data 218 KB (95 file)
  berjalan dari luar folder proyek tanpa error.

## Konten (Phase 6)
- **7 benua dapat dimainkan**, masing-masing 4 regional bernama, 10 awalan nama wilayah, 4 faction, dan 1 world modifier.
  Benua selain Aetherion dibuka lewat Journey: naikkan trofi sampai batas benua itu (Arena bisa dimainkan di semua benua tetapi tidak membuka apa pun; tidak ada fitur "Unlock all").
- **28 Champion berbeda** (`data/champions.json`): 10 passive papan x 11 skill aktif Last Stand, nilai tiap Champion beda dan dibaca dari data
  (`passive_value`, `active_value`). Passive: Royal Treasury, Shadow Ledger, Landlord, Fortune Weave, Toll Keeper, Treasure Hunter,
  Spoils of War, Quartermaster, Mender, Vanguard. Aktif: Sun Judgment, Starfall Decree, Eclipse Veil, Banner of Iron, Inferno Burst,
  Chrono Stasis, Soul Drain, Frost Veil, Overcharge, Rift Strike, Life Surge.
- **World modifier** (`WorldMods`): Aetherion Royal Tithe (+50 START), Arcanum Arcane Markets (pasar saham Bank +10% tiap ronde), Machina Industrial Age (rent +25%,
  harga shop -20%), Sylvaris Bountiful Harvest (+6 G per wilayah per ronde), Drakmor War Fever (ATK battle +15%, pemenang duel +60 G),
  Thalassia Sea Trade (tax setengah, Reroll Token 40 G), Eclipsia Time Fold (+1 Reroll Token tiap lewat START, bonus roll maks 3).
- **Kartu (v19)**: tiap faksi punya **dek 15 tipe unit** (15 x 9 salinan = 135): **8 Pawn benua** (2 per faksi, "slot" 0-3; di benua lain ia milik faksi benua itu, dan untuk sisi ber-King ia ikut faksi slot-nya di benua King (`CardDatabase.effective_faction`); nama diawali
  nama faksi, mis. "Ferrum Royal Guard"; sama untuk semua faksi di benua itu) + **7 bidak milik faksi sendiri** (2 Rook, 2 Knight, 2 Bishop, 1 Queen; `faction: "<id faksi>"`,
  `slot: -1`, field `continent`): 28 faksi x 7 = **196 kartu unik** dengan nama, nama skill, angka skill (`skill.params`), buff, serta HP/ATK sendiri. Dek ditentukan
  oleh Champion (`Deck.faction_id()` -> `CardDatabase.faction_units`), jadi Battle Shop hanya menawarkan Pawn benua + bidak faksi pemain.
  Tiap faksi membagi 7 role (Tank, Marksman, Fighter, Assassin, Mage, Support, Controller) ke 7 bidaknya dengan susunan sendiri (28 susunan berbeda; Solvaris memakai susunan dasar:
  Rook Tank, Rook Marksman, Knight Fighter, Knight Assassin, Bishop Mage, Bishop Support, Queen Controller). HP/ATK/range dan skill mengikuti ROLE (nilai dasar di `CardDatabase.SLOT_BASE`, dicari lewat `role_base`);
  move dan biaya kapasitas mengikuti jenis bidak; HP/ATK tiap
  faksi boleh menyimpang sedikit (maks ~12%) dengan HP x ATK tetap seimbang (`validate_all_continents`). Role, range, dan mekanik skill tetap sama per role, move per bidak;
  skill menunjuk mekanik dasar lewat `skill.mechanic` (`CardDatabase.skill_mechanic`). Angka skill yang divariasikan: durasi taunt, interval dan jumlah target Rook Marksman,
  durasi stun Knight Fighter, bonus serangan pertama Knight Assassin, frekuensi dan persen splash Bishop Mage, interval dan persen heal Bishop Support. Controller (role Controller, bukan lagi aura ATK) memakai skill kontrol **Dominion Bind**: tiap `interval` tick men-stun `targets` musuh ber-ATK
  tertinggi (di seluruh arena) selama `stun_ticks` tick (angka tiap faksi berbeda, lihat `PARAM_KEYS["dominion_bind"]`), ditambah buff.
  **Save lama**: id bidak bersama versi lama diterjemahkan lewat `legacy_ids` di `cards.json` ke bidak faksi pertama benua itu (`CardDatabase.canonical_id`).
  **Buff benua (`data/card_buffs.json`)**: tiap kartu unit punya satu buff tema (8 Pawn x 7 benua + 196 bidak faksi, nama unik). 8 Pawn yang sama mendapat buff berbeda di
  tiap benua. Buff = tipe efek + nilai (`CardDatabase.BUFF_TYPES`, 22 tipe, diterapkan di `BattleEngine`): armor, evade, thorns, execute, frenzy, aura_atk, burn, stun_proc, ward, splash,
  lifesteal, chill, opener, rage, last_rites, death_burst, mend_self, swift, guard, opening_shield, regen, second_life.
- **Semua 21 efek Support berfungsi.** Efek yang butuh target (Crown of Valor, Aegis Shield, Windboots) memilih target otomatis
  (unit terkuat / tertangguh) - TODO: pilih target manual. Mercenary Pact dan Merchant Contract bekerja otomatis di fase persiapan.
- Penyetelan konten: pengukuran lama menunjukkan win rate tiap faction 22-27% (ideal 25%). **Pengukuran ulang (Godot 4.7, 300 game AI per benua, dua set seed, galat sekitar +/-2,5 poin) tidak lagi memenuhi itu**: Inferna 11-13%, Solvaris 16-18% (faksi bawaan dan faksi Tutorial), Verdantia 18%, Voltrix 19-20% di bawah ideal; Warborn / Bloodfang 32-33%, Terragorn 30-32%, Nocthyr 29-31% di atas. Arcanum, Thalassia dan Eclipsia relatif rata (20-30%). Urutan giliran adil (kursi pertama 22-31% tergantung seed).
- Difficulty (simulasi AI vs AI di Aetherion, 200 game per sel): selisih Normal vs Hard kecil dibanding selisih hadiahnya. Pemain ber-skill Normal menang 1v1 sebesar 51,5% di Normal dan 47,5% di Hard, tetapi Hard membayar 300 / 75 coin (Normal 150 / 50) dan trofi +40 / -10 (Normal +30 / -20), sehingga Hard unggul sebagai pilihan di semua tingkat skill. Pemain skill Easy di Arena Normal tersingkir sebelum game selesai 55% (Hard 87%). Belum diuji dengan pemain manusia.

## Struktur
- `data/` balance.json (semua angka ekonomi, termasuk `life_by_difficulty`, `start_gold_by_difficulty`, `round_limit_by_mode`), continents.json (7 benua / 28 faksi), champions.json, cards.json, card_buffs.json, king_buffs.json, king_passives.json, monsters.json, deposits.json, events.json, continent_flavor.json, special_dice.json, map_skins.json
- `scenes/` main_menu, match_setup, territory_board, battle_board, deck_builder, card_collection (Card Hub), shop, events, settings
- `scripts/managers/` GameData, SaveManager (user://save.json), GameSession (autoload, config match), AppNav (tombol Back), Sfx
- `scripts/entities/` BoardTile, PlayerState, BattleUnit, UnitInstance
- `scripts/systems/` aturan Territory (BoardBuilder, DiceSystem, PortalSystem, EconomySystem, EventSystem, MatchController, WorldMods, Terrain, DepositSystem, MonsterSystem), kartu dan battle (CardDatabase, Deck, BattleDeck, UnitRoster, CapacitySystem, CommanderSystem, BattleEngine, BattlePrep, ChessMove), meta (ShopSystem, ChestSystem, EventHub, XpSystem, TutorialGuide, FxMode, UpdateCheck, UpdateInstaller)
- `scripts/ai/` ai_controller.gd (AI Territory Easy/Normal/Hard), battle_ai.gd (AI battle)
- `scripts/ui/` tema, menu, setup, BoardView (digambar dengan _draw), layar Territory / Battle, Card Hub, Shop, Events, panel Chests / Wager, seni prosedural
- `tests/` sim_test, ui_smoke dan tes per fitur (lihat bagian Menjalankan); `tools/` balance_report, run_tests.sh, install_android_template.sh

## Export Android (Phase 7, belum diuji di perangkat)
Project > Export > Android; renderer sudah GL Compatibility, orientasi sensor landscape (landscape dua arah: layar ikut terbalik saat ponsel diputar 180°, tidak pernah portrait). Butuh Android SDK + JDK + keystore.

- **Build di GitHub dan Gradle/AAB**: `.github/workflows/` (tes otomatis + APK + AAB, Godot 4.7); lihat BUILD_ANDROID.md. Skrip tes: `tools/run_tests.sh`. Proyek kini memakai Godot 4.7 (target API 36 untuk Google Play).

## Tutorial, Auction, Special Dice, seni, audio, kartu baru
- **Tutorial** (New Match -> Offline -> Tutorial): match 1v1 melawan AI Normal di Aetherion, 10 ronde, seed tetap. AI sudah memiliki wilayah di depan pemain dan
  tawaran duel pertama selalu muncul. `TutorialGuide` menjelaskan tiap aturan saat pertama kali muncul (panel petunjuk di papan; tips
  di atas separuh papan musuh saat persiapan duel). Hasilnya tidak dihitung ke statistik; `profile.tutorial_done` disimpan.
- **Auction sungguhan**: lot acak dilelang ke semua pemain hidup, mulai dari yang mendarat; buka 40% harga, naik 10% per tawaran;
  yang pass atau tak mampu keluar; AI menaksir lot dari harga, region yang dilengkapi, dan tingkat kesulitan.
- **Special Dice** (6 jenis x 6 sisi, `data/special_dice.json`): Swift (bonus gerak), Warp (teleport, menggantikan lemparan),
  Order (lempar ekstra / lawan berikutnya lewat giliran / token / gold), Destiny (dadu nasib baik/buruk), **Thief** (curi 20-60 G dari lawan terkaya; sisi terakhir tertangkap, denda 30 G),
  **Broker** (portofolio saham -10% s/d +50%; tanpa saham dapat modal gratis 100 G). Sumber: kartu Event dan Territory Shop (120 G); maks 3 dibawa; dipakai
  sebelum melempar. AI memakainya. Tersimpan di save. (Sumber dari Champion dan Rule Card belum ada.)
- **Kartu baru**: kemenangan match tidak lagi membuka Support terkunci (dihapus); kartu didapat dari Shop (gacha, Buy Card) dan peti. Kartu unit Rare / Epic benua yang terbuka masuk pool gacha Unit; varian kartu unit pengganti belum ada.
- **Seni prosedural** (`Art`, `PortraitView`; tanpa file gambar): siluet 6 bidak catur, 7 lambang benua, 7 ikon kategori Support, potret perisai
  Champion. Dipakai di kartu, token battle, dan pemilihan Champion. Galeri: `docs/screenshots/art_gallery.png`.
- **Audio** (`Sfx`): 11 efek suara disintesis dari kode (klik, dadu, koin, pukulan, gugur, sihir, portal, menang/kalah, dll), bisa dimatikan di Settings.
  Belum ada musik.
- **Animasi battle**: gerak halus antar petak, lunge saat menyerang, angka damage melayang, cincin saat unit gugur; mengikuti kecepatan 1x/2x/4x.
- **Battle Chess: 1 Round / 10 Rounds / Survival** (dialog FIGHT di New Match -> Battle Chess, baris *Length*; `GameSession.battle_series`):
  - *1 Round*: satu battle seperti sebelumnya.
  - *Catatan (terbaru)*: pilihan *Length* sudah dihapus. **Semua Battle Chess di New Match adalah run Survival**; difficulty hanya menentukan **nyawa: Easy 5 / Normal 3 / Hard 1** (`ShopSystem.series_lives`, memakai `life_by_difficulty`). Tiap kekalahan mengurangi 1 nyawa, run berakhir saat nyawa 0 (seri tidak mengurangi nyawa). Status dan layar hasil menampilkan `Lives x/y`. Taruhan: menang bila minimal 5 ronde dimenangkan sebelum nyawa habis (`SERIES_SURVIVAL_TARGET`). Mode 1 Round / 10 Rounds tidak lagi bisa dipilih (kode `single` / `ten` masih ada untuk tes). Belum diuji dengan Godot.
  - *Survival*: lanjut terus sampai kalah pertama. Seri tidak mengakhiri run.
  - Antar round: pasukan, gold, level dan kartu Support tetap; dapat income gold (150 + 25 per round yang sudah dimainkan), shop dibagi ulang, medan diacak lagi.
    Musuh makin kuat lewat budget (+12% per round, maks x3.5). **Level musuh (level shop / kapasitas) selalu sama dengan level pemain** (bukan level King), tanpa bonus Hard dan tanpa +1 tiap 3 round; naik level pemain berarti musuh ikut naik. Kecepatan battle yang dipilih tetap.
  - Koin Aether dibayar tiap round (hadiah practice + bonus 25 x nomor round untuk round menang dari round 2). Wager dibayar sekali di akhir run:
    10 Rounds = menang/seri/kalah menurut skor; Survival = menang jika menang minimal 5 round. *End Run* di 10 Rounds menghanguskan wager; keluar lewat Menu di tengah run juga menghanguskannya.
  - **Gold awal per difficulty** (match wilayah Journey / Arena, semua kursi seperti Life): **Easy 2000 / Normal 1500 / Hard 1000** (`balance.json` -> `start_gold_by_difficulty`, `GameData.gold_for`). Tutorial tetap 1500. Teks Card Hub > Info ikut menampilkan angkanya.
  - **AI naik level di duel wilayah (Arena / Journey)**: semua difficulty, termasuk Easy, naik level (maks Lv 7) saat pasukannya mengisi kapasitas dan budget duelnya cukup (`BattleAI.prepare_ai_army`); Easy lebih jarang karena budget duelnya hanya 10% gold (Normal 20%, Hard 30%).
  - **Level King di seri**: di 10 Rounds dan Survival, King kedua sisi naik level seperti bintang Commander: **Lv 1** ronde 1-3, **Lv 2** ronde 4-6, **Lv 3** ronde 7+ (HP x1,0 / x1,35 / x1,8 dan ATK x1,0 / x1,25 / x1,5, `CommanderSystem`). Battle tunggal (1 Round) tetap Lv 1. Layar hasil memberi tahu saat King naik di ronde berikutnya (`ShopSystem.series_king_star`).
  - Aturan ada di `ShopSystem` (`series_*`), tes: `tests/series_test.gd`.
- **Profil di beranda** (`ProfileView.build_card`, `XpSystem`): kartu profil (avatar, nama, title, Lv, bar EXP, rekor) langsung tampil di Main Menu, tanpa tombol Profile; tap kartu untuk detail lengkap.
  EXP total disimpan di `profile.xp`, level dihitung darinya (butuh `100 + 40 x (level-1)` EXP per level, maks Lv 60).
  Title: Recruit (Lv 1), Squire (5), Knight (10), Captain (15), Warden (20), Warlord (30), Archon (40), Overlord (50), Dominion Lord (60).
  EXP: match Territory menang 100 / kalah 30 (+2 per round, maks 30 round), Battle Chess menang 40 / kalah 10 per battle; dikali easy 0.75, normal 1, hard 1.5.
  **Hadiah naik level**: tiap level baru memberi **Aether Coins** (50 + 10 x level) dan **1 peti** (Gold di level kelipatan 10, Silver di kelipatan 5, selain itu Bronze). Naik beberapa level sekaligus membayar semuanya. Peti ini tidak menghitung batas drop Arena (`ChestSystem.award_grade`); kalau slot dan Storage penuh, peti jadi coin. Ditampilkan di layar hasil (`SaveManager.level_reward_line`) dan dialog buka peti. Angka ada di `XpSystem.level_up_coins` / `level_up_chest`.
  Save lama dapat EXP awal dari rekornya (menang x100, kalah x30), sekali saja (tidak ada hadiah level untuk level hasil migrasi). Tes: `tests/xp_test.gd`.
- **Mode Effects Lite / Pro** (Settings -> Effects, `FxMode`, tersimpan di `settings.effects`, default Pro):
  Pro = semua animasi (dadu berguling, pion melompat, kamera meluncur, lunge, cincin gugur, kartu Shop muncul bertahap, animasi summon Gacha, fade dialog).
  Lite = hasil langsung tampil tanpa tween: dadu langsung hasil, pion langsung mendarat, kamera lompat, unit battle berpindah instan tanpa lunge/cincin, kartu Shop dan dialog tanpa fade.
  Angka damage dan banner (CHECK, CHECKMATE, dll) tetap tampil di Lite karena membawa informasi.

## TODO (tidak berpura-pura selesai)
- Varian kartu unit pengganti dan Champion/Rule Card sebagai sumber Special Dice.
- Nama dan ilustrasi unik per benua/Champion (seni sekarang prosedural dan generik); sprite dan animasi unit sungguhan.
- Musik latar; suara masih sintetis sederhana.
- Multiplayer online (Classic dan Ranked 1v1 / 2v2 / 4 player, Battle Chess online, Lobi, Turnamen): belum ada, tab ONLINE di New Match hanya menampilkan kartunya sebagai "Coming soon". Journey sekarang hanya jalur unlock benua 1v1; alur cerita/campaign dengan misi khusus belum ada. (2vs2 melawan AI sudah ada, lihat bagian Mode 2vs2.)
- Pemilihan target manual untuk kartu Artifact (Crown of Valor, Aegis Shield, Windboots).
- Uji di perangkat Android nyata (lihat BUILD_ANDROID.md).
- Keseimbangan: eliminasi total jarang (3-4%); game biasanya diputuskan net worth saat batas ronde tercapai. Angka keseimbangan di atas diukur dengan batas 30 ronde. Batas per mode / difficulty yang baru (Journey 20 / 30 / 40, Arena 30 / 40 / 50) diukur sekali dengan simulasi AI vs AI di Aetherion (60 game per sel, galat sekitar +/-6 poin, tanpa pemain manusia):
  - Easy (5 Life) tidak pernah berakhir karena eliminasi (0%): hasilnya selalu net worth di batas ronde, jadi ronde tambahan hanya memperpanjang waktu.
  - Hard (1 Life): eliminasi 1v1 naik dari 10% (20 ronde) ke 25% (30) dan 37% (40); keuntungan Hard melawan Easy naik 55% -> 65% -> 68% lalu datar di 40-50 ronde. Arena 4 Player: Normal baru ada 7% eliminasi di 40 ronde dan 13% di 50, jadi ronde ekstra kebanyakan hanya menambah durasi.
  - Pemain di giliran pertama menang lebih sering di Arena 4 Player (23-38% vs 25% adil), terbesar di Easy dan di batas pendek.
  Kesimpulan sementara: batas Normal sudah wajar; Hard Journey 40 dan Arena 50 kemungkinan terlalu panjang untuk manfaatnya. Belum diuji dengan pemain manusia, benua selain Aetherion, atau sampel lebih besar.

## Peta Territory: posisi START, zoom dan kamera
Layar Territory dan Battle tiga kolom ala Monopoly (Battle: tombol + kartu Support di kiri, papan 8x8 di tengah, shop + bench di kanan, log di kanan saat bertarung). Territory: papan di tengah, Card Hub + kartu pemain di kiri, Round + Menu dengan history (log) di kanan (aksi di bawah log; tombol dadu di dalam papan). Kode: `scripts/ui/board_view.gd`, `scripts/systems/board_builder.gd`.
- **START (Dominion Gate) ada di pojok kanan bawah** dan pion berjalan searah jarum jam. Indeks petak 0 = START; `BoardBuilder.grid_pos(idx)` meletakkan cincin dari pojok kiri atas lalu memutarnya 180 derajat (`_ring_pos` = tata letak asli). Urutan petak dan logika game tidak berubah; berlaku untuk papan 100 dan 40 petak, dan save lama ikut tampil dengan orientasi baru.
- **Zoom awal**: papan 40 petak (Chaos) tampil utuh. Papan 100 petak dibuka ter-zoom `grid / 11` (sekitar 2,36x) sehingga ukuran petak sama dengan papan 40 petak (`BoardView.default_zoom()`); kamera mengikuti pion. Zoom hanya dihitung ulang saat ukuran papan berganti, jadi Duel atau Card Hub tidak mereset zoom pemain (`zoom` bersifat static).
- **Kontrol** (pojok kiri bawah): `+` / `-` zoom, **Fit** menampilkan seluruh papan lalu tombolnya berganti jadi **1:1** untuk kembali ke ukuran petak awal di pion giliran saat ini (di papan 40 petak tombol selalu Fit), **Speed** 1x / 2x / 4x. Geser dengan drag, cubit atau roda mouse untuk zoom. Semua tombol aksi (Roll Dice, Reroll, Move, End Turn, Buy, special dice) di pojok kanan bawah layar. Ketuk petak untuk info.

## Safe area / notch kamera
- Layar penuh (immersive) aktif di Android. `UiTheme.safe_insets()` membaca safe area, cutout, dan perkiraan untuk HP lama tanpa laporan cutout (waterdrop notch, rasio >= 1,9), ditambah slider **Notch margin** di Settings (0-120). Latar tetap penuh layar; hanya isi yang digeser.
- `UiTheme.make_margin(px, vertical)` untuk layar biasa, `UiTheme.follow_insets(node, callback)` untuk elemen yang menempel di tepi layar di luar container (kartu profil menu utama, panel aksi dan kontrol zoom Territory). Inset dibaca ulang saat jendela berubah (rotasi, lipat, slider) dan dua kali setelah layar tampil (0,35 dan 1,5 detik) karena Android sering baru melapor sesudah frame pertama.
- `UiDialog` menengahkan panelnya di area aman dan membatasi lebarnya dengan inset; latar redupnya tetap penuh layar.
- Saat headless `safe_insets()` selalu 0, jadi perilaku ini hanya bisa dicek di perangkat atau emulator.

## Menu utama
Judul MULTIVERSE DOMINION, garis pemisah, tagline, dan versi ada di kiri bawah; kartu profil (nama, gelar, level, EXP; ketuk untuk detail) di kiri atas; kolom tombol di kanan: CONTINUE MATCH, NEW MATCH, Card Hub, Shop, Events, Settings, Quit.

## Tab Info (Card Hub -> Info)
Panduan yang dibangun dari data game (`scripts/ui/card_collection.gd`, `_info_*`): Overview, Lineup, Territory, Roles & Skills, Synergies, Battle. Bagian Territory memuat aturan petak, sewa, Duel, batas ronde Journey / Arena / Chaos, Landmark, angka Chaos Mode, monster dan tambang tersembunyi (tanpa membocorkan lokasi), level King, dan kontrol kamera peta. Angka diambil dari `data/balance.json` lewat `GameData`, jadi ikut berubah saat keseimbangan diubah; hanya teks aturan yang perlu diperbarui manual.


## 28 King berbeda & 28 Monster "King+"
Rincian lengkap tiap King dan Monster ada di `docs/KING_KIT.md` (dibuat dari data). Ringkasnya:
- **Skill aktif King** (B2): 28 skill berbeda, masing-masing berupa daftar efek (`data/skills.json`, dijalankan `BattleEngine._run_skill_fx`; 30 jenis efek di `BattleEngine.SKILL_OPS`: damage satu/banyak/jangkauan/kolom/baris/di bawah HP tertentu, teleport, stun, slow, burn, mark, shield, heal, revive, cleanse, energi, haste, dst). Skill lama (`sun_judgment`, dst) tetap didukung di engine bila ada data yang memakainya.
- **Buff battle King**: 28 tipe buff berbeda (tiap tipe dipakai satu King). 10 tipe baru: `feast`, `bastion`, `weaken`, `rally_cry`, `chain`, `crit`, `momentum`, `quickkill`, `undying`, `shatter` (`CardDatabase.KING_BUFF_TYPES`). Dua tipe lain (`vengeance`, `siphon`) khusus Monster.
- **Passive battle King**: tiap King punya dua efek (`type` + `type2` di `king_passives.json`, dibaca lewat `BattleEngine._sp`).
- **Skill teritori King** (B3): tiap King punya dua skill (`passive` + `passive2`) dengan nama sendiri. Lima skill baru: `interest` (bunga saat lewat START, maks 120 G = balance `interest_cap`), `war_chest` (emas awal), `rent_cut`, `tax_cut`, `upgrader` (upgrade lebih murah). `PlayerState.has_passive` / `pv(id)` membaca kedua skill; save/resume menyimpan `passive2`.
- **Monster King+**: 28 monster punya skill aktif sendiri (2-3 efek, tidak ada yang sama dengan skill King mana pun) dan **trait Plus** (`plus` di `monsters.json`): buff kedua di atas buff aslinya, jadi tiap monster punya kombinasi buff + Plus sendiri. Ringkasan monster menampilkan baris "King+ - nama: deskripsi". Stat dasar monster tidak diubah.
- Regenerasi data: `python3 tools/gen_kit.py` (tabel di dalam skrip adalah sumber kebenaran). Tes: `godot --headless --path . res://tests/kit_test.tscn` -> `KIT TEST RESULT: PASS` (keunikan data, tiap skill benar-benar mengubah battle, tiap buff baru, skill teritori baru). `tests/battle_test.gd` juga diperbaiki (variabel `wall` ganda yang membuat tes itu tidak bisa dimuat).
