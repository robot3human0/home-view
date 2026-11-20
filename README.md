# 🏡 HomeView 1.0.0 — to‘rt fasl, ofis tarmog‘i va sport o‘yinlari

*(Avvalgi nomi — Qorli Kun.)*

Mac ish stolida to‘rt fasl. Ofis tarmog‘iga ulanganda hamkasblaringizning odamchalari ekraningizda ismlari bilan yurib yuradi. Ularga salom berish, koptok otish, xabar yozish, choyga taklif qilish va birga o‘ynash mumkin.

```
HomeView-1.0.0/
├── deploy.sh            Mac mini'da bitta buyruq: ilova + yuklab olish sahifasi + server
├── HomeView/            Mac ilovasi
│   ├── HomeView.xcodeproj    TestFlight / App Store versiyasi (Xcode → Archive)
│   ├── AppStore/             uning Info.plist, sandbox ruxsatlari, ikonkalar
│   └── make_dmg.sh           DMG versiyasi (Mac mini'dagi yuklab olish sahifasi uchun)
├── HomeViewServer/      Ofis serveri va yuklab olish sahifasi (Mac mini'da)
└── HomeViewProtocol/    Umumiy "til": ilova va server bir-biriga yuboradigan xabarlar
```

---

## 1. To‘rt fasl

Fasl sanaga qarab o‘zi almashadi (❄ menyusi → Fasl → Avtomatik) yoki istalganini qo‘lda tanlaysiz. Almashganda ekran sekin so‘nib, yangi fasl bilan qayta paydo bo‘ladi.

| | ❄️ Qish | 🌸 Bahor | ☀️ Yoz | 🍂 Kuz |
|---|---|---|---|---|
| Nima yog‘adi | Qor | O‘rik gullari barglari | Terak paxmog‘i | Sarg‘aygan barglar |
| Brigada | Shapkada, kurak bilan | Kepkada, xaskash bilan | Somon shlyapada, supurgi bilan | Kepkada, xaskash bilan |
| Nima yasaydi | Qorbola (shlyapa, chelak, do‘ppi...) | Lolazor (ustida kapalak) | Tarvuz uyumi (tepasida qovun) | Qo‘riqchi qo‘g‘irchoq (qovoq bosh) |
| Qaysi mashina | Qor tozalovchi | Traktor | Suv sepuvchi | Ko‘cha supuruvchi (aylanuvchi cho‘tka) |
| Kim uchib o‘tadi | Qorbobo va Qorqiz | Qaldirg‘ochlar | Havo shari | Turnalar ("V" shaklida) |
| Nima bilan otishiladi | Qor koptok | Gul to‘pi | Suv to‘pi | Barg to‘pi |
| Sovg‘a | Sovg‘a qutisi | Gul dastasi | Muzqaymoq | Anor |

Yasalgan narsani uch zarbada buzish mumkin. Brigada har faslda o‘ziga xos gaplar bilan achinadi, qayta yasaydi, qo‘riqchi qo‘yadi va kerak bo‘lsa javob qaytaradi.

---

## 2. Mac mini'da bitta buyruq: `deploy.sh`

Mac mini — ofisning "markazi". U uchta ishni bajaradi: hamkasblarni bir-biriga ulaydi (server), o‘yinlarda hakam bo‘ladi va ilovani tarqatadi (yuklab olish sahifasi). Uchalasi bitta buyruq bilan yangilanadi:

```bash
cd ~/HomeView-1.0.0
./deploy.sh                                   # oddiy
./deploy.sh "Sport o‘yinlari qo‘shildi"       # yangiliklar matni bilan (sahifada va xabarda ko‘rinadi)
```

| Qadam | Nima bo‘ladi | Nega |
|---|---|---|
| 1. Ilovani yig‘ish | `HomeView/make_dmg.sh` DMG tayyorlaydi | Hamkasblarga Xcode kerak bo‘lmasin |
| 2. Javonga qo‘yish | DMG va `latest.json` → `~/HomeViewServer/downloads/` | Sahifa doim eng yangi versiyani beradi |
| 3. Serverni yangilash | `HomeViewServer/install.sh` | Server qayta ishga tushganda ulangan hamkasblarga "yangi versiya chiqdi" deydi |

Oxirida yuklab olish sahifasining manzili chiqadi, masalan `http://build-mini.local:47778/`. Shu havolani ofis guruhiga yuboring. Ilovadan ham nusxalash mumkin: ❄ → Ofis → "🔗 Ilova havolasini nusxalash".

**Ofis kodi** bir marta beriladi va keyingi `deploy.sh` larda saqlanib qoladi: `HOMEVIEW_CODE=qishki2026 ./deploy.sh`. Olib tashlash: `HOMEVIEW_CODE= ./deploy.sh`.

**Eski Qorli Kun serveri** bo‘lsa, `install.sh` uni o‘zi to‘xtatadi va ofis kodini undan ko‘chirib oladi.

### Hamkasblar uchun: yuklab olish va o‘rnatish

1. Sahifani oching (`http://build-mini.local:47778/`) va "Yuklab olish" ni bosing.
2. DMG'ni oching, **HomeView** ni **Applications** ga torting.
3. HomeView'ni oching. macOS uni tekshira olmaganini aytib to‘xtatadi — **Done** ni bosing.
4. **System Settings → Privacy & Security** → pastda **Open Anyway** → parol yoki Touch ID → yana **Open Anyway**.
5. Menyu satrida ❄ paydo bo‘ladi. Sozlamalar → Ofis'da ismingizni yozing.

3–4-qadamlar faqat birinchi marta va faqat ilova Apple imzosisiz tarqatilgani uchun kerak. Developer ID imzosi qo‘shilgach (`DEVELOPER_ID=... NOTARY_PROFILE=... ./deploy.sh`), ular yo‘qoladi.

**Yangi versiya chiqqanda** ilova o‘zi aytadi: o‘ng yuqorida "🆕 HomeView X chiqdi" kartochkasi va ❄ menyusining tepasida "Yangi versiya" qatori paydo bo‘ladi. Ikkalasi ham to‘g‘ridan-to‘g‘ri sahifani ochadi.

**Eski Qorli Kun'dan o‘tish:** HomeView birinchi ochilishda ism, odamcha, ofis kodi va o‘lchamlarni o‘zi ko‘chirib oladi, eski ilova ishlab turgan bo‘lsa — yopadi. Keyin eski ilovani savatga tashlang va HomeView sozlamalarida "Kompyuter yonganda ishga tushsin" ni qayta yoqing.

---

## 3. Server haqida (boshidan, oddiy tilda)

### Server nima va nega kerak

Serverni ofisdagi dispetcher deb tasavvur qiling. Har bir hamkasbning Mac'i unga "men shu yerdaman, odamcham mana bunday" deb xabar beradi, dispetcher esa buni qolgan hammaga yetkazadi. O‘yinlarda u hakam ham bo‘ladi: kim birinchi bosdi, kim yutdi — shuni u hal qiladi.

Server tashqi kutubxonalarsiz, faqat Apple'ning o‘z vositalari bilan yozilgan. Mac mini'ga qo‘shimcha hech narsa o‘rnatish shart emas, faqat Xcode Command Line Tools bo‘lsa yetarli (CI runner bo‘lgan Mac mini'da u allaqachon bor).

### Faqat serverni o‘rnatish (ilovasiz)

`deploy.sh` hammasini qiladi. Faqat server kerak bo‘lsa:

```bash
cd ~/HomeView-1.0.0/HomeViewServer
./install.sh
tail -f ~/HomeViewServer/server.log      # jurnal; chiqish — Control + C (server to‘xtamaydi)
```

### `install.sh` aslida nima qiladi

| Qadam | Nima | Nega |
|---|---|---|
| 1. `swift build` | Serverni manba koddan dasturga aylantiradi | Mac mini o‘z protsessoriga mos dastur oladi |
| 2. `~/HomeViewServer` ga ko‘chirish | Dasturni doimiy joyga qo‘yadi, yonida `downloads` papkasi | Loyiha papkasini o‘chirsangiz ham server va sahifa ishlayveradi |
| 3. launchd'ga topshirish | Mac mini'ning "navbatchisi" serverni kuzatadi | Mac mini yonganda server o‘zi ishga tushadi, to‘xtab qolsa — qayta yoqiladi |

### Bo‘lishi mumkin bo‘lgan savollar

- **"Kiruvchi ulanishlarga ruxsat berilsinmi?" degan oyna chiqdi.** Bu Mac mini'ning xavfsizlik devori. "Ruxsat berish"ni bosing, aks holda hamkasblar ulana olmaydi.
- **Hamkasbning ilovasi serverni topmayapti.** Ba’zi ofis tarmoqlarida Bonjour e’lonlari bloklangan bo‘ladi. Bunday holda ilovada Sozlamalar → Ofis → Server manzili maydoniga `install.sh` ko‘rsatgan manzilni (masalan `192.168.1.20`) yozib, "Saqlash"ni bosing.
- **Ilova "mahalliy tarmoqqa ruxsat" so‘radi.** "Ruxsat berish"ni bosing. Usiz ilova ofis serverini ko‘ra olmaydi.
- **Mac mini — CI runner.** Server juda yengil: bir necha MB xotira va deyarli nol protsessor ishlatadi. U o‘yin taymerlari aniq ishlashi uchun oddiy ustuvorlikda ishlaydi (3.3 gacha orqa fon rejimida edi — o‘yinlar shundan qotardi); protsessorni deyarli ishlatmagani uchun yig‘ish (build) ishlarini sekinlashtirmaydi. Shunga qaramay, serverni faqat ofis ichki tarmog‘ida qoldiring va internetga ochmang: bu Mac'da ilovalarni imzolaydigan sertifikatlar saqlanadi.
- **Yangilash.** Yangi papkani Mac mini'ga ko‘chirib, `./deploy.sh` ni ishga tushiring.
- **Sahifa `build-mini.local` orqali ochilmayapti.** Tarmoq Bonjour nomlarini o‘tkazmayapti. IP bilan oching (`install.sh` oxirida ko‘rsatiladi) yoki havolaga IP yozilsin: `HOMEVIEW_PUBLIC_HOST=192.168.1.20 ./deploy.sh`.
- **O‘chirish.** `./uninstall.sh`.

---

## 4. Ilovada ofisni yoqish

1. ❄ menyusi → **Sozlamalar** (⌘,) → **Ofis**.
2. "Ofisga ulanish" ni yoqing, ismingiz va jamoangizni yozing.
3. Odamchangizni tanlang: bosh kiyim (do‘ppi, kepka, shapka, shlyapa), shapka, nimcha va yuz rangi. Chap tomonda u qanday ko‘rinishi darhol ko‘rinadi.
4. Ilova serverni o‘zi topadi. Topilmasa, server manzilini qo‘lda kiriting.

**Odamcha bilan nima qilish mumkin** (hamkasbning odamchasini bosing):

| Amal | Nima bo‘ladi |
|---|---|
| 👋 Salom berish | Uning ekranida sizning odamchangiz qo‘l silkitadi |
| ❄️ Koptok otish | Koptok uning ekraniga uchib borib, yopishadi (fasliga qarab qor, suv yoki barg) |
| 💬 Xabar yozish | Gap pufagi bo‘lib, uning ekranida sizning odamchangiz tepasida chiqadi |
| ☕ Choyga taklif | Unga "Boraman / Keyinroq" tugmali kartochka boradi |
| 🎮 O‘yinga taklif | Lobbi ochiladi, boshqalar ham qo‘shila oladi |

**Kim ekraningizda yuradi — o‘zingiz tanlaysiz.** Ofisga ulanadiganlar soni cheklanmagan. ❄ → Ofis → "👥 Hamkasblar" (yoki Sozlamalar → Ofis → "Tanlash…") oynasida hamma hamkasb ro‘yxati bor: onlayn turganlar va ilgari ko‘rilganlar (oflayn bo‘lsa ham — kelmasidan oldin tanlab qo‘yish mumkin). Har bir odam yonida yoqish/o‘chirish tugmasi, qidiruv, "Hammasi / Onlayn / Ekranda" filtri va jamoalar bo‘yicha guruhlar. "Yangi qo‘shilganlar avtomatik ko‘rinsin" o‘chirilsa, yangi odam kelganda kartochka chiqadi va uni bir bosishda ekranga chiqarasiz. Odamchani bosib, "🙈 Ekranimdan olib tashlash" ham mumkin. Ekrandan olib tashlangan hamkasb bilan xabar yozish, choyga chaqirish va o‘ynash odatdagidek ishlaydi.

**Holatlar:** 🟢 Faol, ☕ Uzoqda (5 daqiqa kompyuterga tegilmasa o‘zi yoqiladi, odamcha o‘tirib choy ichadi), 🔕 Band (takliflar va koptoklar kelmaydi), 👻 Ko‘rinmas.

---

## 5. Tarmoq o‘yinlari

| O‘yin | Kishi | Qoidasi |
|---|---|---|
| 💣 **Muz koptok** | 2–10 | Koptok kimningdir odamchasida paydo bo‘ladi. U sizga kelsa, tezda boshqa o‘yinchini bosib uzating. Koptok qachon yorilishini hech kim bilmaydi. Kimda yorilsa, o‘sha chiqadi, oxirida qolgan yutadi |
| 🎯 **Mergan** | 2–12 | Hammaning ekranida bir vaqtda nishon (shu faslning sovg‘asi) chiqadi. Kim birinchi bossa, ochko o‘shaniki. 15 ta nishon |

### Sport: 🔵 Ko‘klar va 🔴 Qizillar

| O‘yin | Kishi | Boshqaruv | Qoidasi |
|---|---|---|---|
| 🏐 **Voleybol** | 2–8 | Odamcha sichqonchaga ergashadi, bosish — sakrash | To‘p tekkan odamchadan o‘zi qaytadi. Sakrab urilsa — kuchliroq. To‘p yerga tushgan tomon ochko beradi. 7 ochkogacha yoki 3 daqiqa |
| 🏓 **Stol tennisi** | 2–4 | Raketka sichqonchaga ergashadi (yuqoriga-pastga) | Raketkaning chetiga tegsa to‘p qiyaroq uchadi. Har zarbada tezlashadi. 7 ochkogacha |
| ⚽ **Penalti** | 2–12 | Bitta bosish | Tepuvchi darvozaning bir joyini bosadi, darvozabon qayerga sakrashini tanlaydi — ikkalasi bir vaqtda, 5 soniyada. Burchakka tepsangiz, ustunga tegish xavfi bor. Har jamoaga 5 zarba, teng bo‘lsa — qo‘shimcha |
| 🏀 **Basketbol** | 2–12 | Bosib orqaga tortish va qo‘yib yuborish | Hamma bir vaqtda otadi. 3 raund: savat har safar uzoqroq va balandroq, 3-raundda 3 ochko |
| 🪢 **Arqon tortish** | 2–16 | Tez-tez bosish | Jamoaning bir kishiga to‘g‘ri keladigan bosishlari solishtiriladi — kam odamli jamoa ham yuta oladi. Bayroq chiziqqa yetguncha yoki 40 soniya |

**Jamoalar:** lobbiga qo‘shilganda kamroq odamli jamoaga tushasiz, "⇄ Jamoa" tugmasi bilan almashtirasiz. Formangiz rangi jamoangizga qarab o‘zgaradi.

**Sport o‘yini paytida** asosiy monitordagi bosishlar o‘yinga ketadi. Boshqa monitorlarda odatdagidek ishlayverasiz. O‘yindan istalgan payt "✕ Chiqish" tugmasi bilan chiqasiz.

### Shaxmat ♟

| Usul | Kishi | Vaqt | Qanday |
|---|---|---|---|
| ⚡ **Blits** | 2 | 5 daqiqa + har yurishga 3 soniya | Jonli. Raqib qabul qilishi bilan doska ochiladi |
| 📅 **Kunlik** | 2 | Har yurishga 24 soat | Bo‘sh paytda bitta yurish. Raqib yurganda "♞ Navbat sizda" kartochkasi keladi. Bir vaqtda bir nechta partiya mumkin |
| 👥 **Jamoaviy** | 2–12 | Har yurishga 60 soniya | Ko‘klar — oqlar, Qizillar — qoralar. Har kim o‘z variantini bosadi (bu — ovoz), eng ko‘p ovoz olgan yurish o‘ynaladi. Hech kim ovoz bermasa — tasodifiy yurish. Jamoangiz ovozlari faqat sizga ko‘rinadi |

- Doska **alohida kichik oynada** ochiladi: istalgan joyga suriladi, faqat o‘z ustidagi bosishlarni oladi. Yopsangiz ham partiya davom etadi — ❄ menyusida "♟ Shaxmat — navbat sizda" qatori chiqadi.
- Figurani bossangiz, qonuniy kataklar nuqta bilan ko‘rsatiladi; ikkinchi bosish — yurish. Piyoda oxirgi qatorga yetsa, figura tanlanadi.
- Doska ranglari faslga qarab o‘zgaradi.
- Durang taklif qilish va taslim bo‘lish (blits va kunlikda). Mot, pat, uch marta takrorlanish, 50 yurish va kuch yetmasligi — hammasi avtomatik.
- **Kuzatish:** o‘ynayotgan hamkasbning odamchasini bosing → "♟ Partiyani kuzatish".
- Partiyalar Mac mini'da `~/HomeViewServer/chess.json` ga saqlanadi: server qayta ishga tushsa ham kunlik partiyalar yo‘qolmaydi.

**Hammani chaqirish:** ❄ menyusi → Ofis → "🎮 Hammani o‘yinga chaqirish". Faol holatdagi hamma hamkasbga bir yo‘la taklif boradi.

**O‘yin qanday boshlanadi:**
1. Hamkasbning odamchasini bosib, o‘yinga taklif qilasiz.
2. U qabul qilsa, lobbi ochiladi va uning odamchasi tepasida bayroqcha chiqadi, masalan "💣 Muz koptok 2/10".
3. Boshqalar odamchani bosib, "qo‘shilish" ni tanlay oladi.
4. O‘yin 20 soniyadan keyin o‘zi boshlanadi, yoki taklif qilgan odam "Hozir boshlash" ni bosadi.

---

## 6. Tuzilma (dasturchilar uchun)

```
HomeViewProtocol/Protocol.swift   ClientMessage / ServerMessage, PeerInfo, RoomInfo, GameEvent
HomeViewServer/
├── main.swift                    Sozlamalar (port, nom, ofis kodi) va ishga tushirish
├── Server.swift                  NWListener + Bonjour e’loni (WebSocket)
├── Hub.swift                     Ulanishlar, hozirlik, xabarlar, o‘yin xonalari
├── Games.swift                   Hakam: Muz koptok va Mergan mantig‘i
├── SportGames.swift              Hakam: sport fizikasi (30 Hz) va qoidalari, jamoalar
└── install.sh / uninstall.sh     launchd orqali avtomatik ishga tushirish
HomeView/Sources/HomeView/
├── Season.swift, SeasonArt.swift Fasllar ssenariysi va rasmlari
├── Visitors.swift                Qorbobo / qaldirg‘ochlar / havo shari / turnalar
├── NetworkClient.swift           Serverni topish va ulanish (fon oqimida, avtomatik qayta ulanadi)
├── Office.swift                  Ofis boshqaruvchisi: hamkasblar, takliflar, menyular
├── PeerAvatar.swift              Hamkasb odamchasi (ism yorlig‘i, holatlar)
├── GameStage.swift               Ko‘ngilochar o‘yinlar sahnasi + NetStage shartnomasi
├── SportStage.swift              Sport maydonlari: voleybol, tennis, penalti, basketbol, arqon
├── SportArt.swift                To‘plar rasmlari
├── Toasts.swift                  O‘ng yuqori burchakdagi kartochkalar (SwiftUI)
└── ... (qolganlari 2.x dan: dunyo, brigada, sozlamalar)
```

Hamma animatsiyani Core Animation chizadi, tarmoq ishi esa fon oqimida bajariladi. Shuning uchun ilova ko‘p monitorda ham, ko‘p hamkasb ulanganda ham qotmaydi.

---

## 7. Qorli Kun'dan HomeView 3.2 ga o‘tish

Protokol versiyasi 3 ga ko‘tarildi: eski ilova ulanmoqchi bo‘lsa, server "Ilovangiz eski" deydi.

1. Mac mini'da: `./deploy.sh` (eski server o‘zi to‘xtatiladi, ofis kodi ko‘chiriladi).
2. Hamkasblar: sahifadan HomeView'ni o‘rnatadi. Sozlamalar o‘zi ko‘chadi, eski ilovani savatga tashlaydi.

---

## 8. Versiyalar

| Versiya | Build | Nima o‘zgardi |
|---|---|---|
| **1.0.0** | 14 | Realistik rasmlar (odamlar, qorbola, Qorbobo va Rudolf, 8 mashina, qushlar va laylaklar, havo shari, zarrachalar), har faslda 4 ob-havo holati (avtomatik yoki tanlab), yomg‘ir/tuman/chaqmoq/sumalak/qirov/kamalak/chiroq qo‘ng‘izlari, qor qatlamiga soya. Build raqami kamaymaydi — eski ilovalar yangilanishni ko‘radi |
| 3.7 | 13 | **macOS 26 Tahoe va undan yangisi.** Yangi Liquid Glass ikonka: uyning to‘rt ko‘zli derazasi, har ko‘zida bitta fasl, shisha kartochkalar va tugmalar, sport o‘yinlari monitor chastotasida (120 Hz gacha), Spotlight amallari, menyu satridagi belgi faslga qarab. Server o‘zgarmadi — eski macOS'dagilar 3.6 da qolishi mumkin |
| 3.6 | 12 | Ekrandagi hamkasblarni o‘zingiz tanlaysiz (ro‘yxat, qidiruv, on/off); "ko‘pi bilan 20 kishi" cheklovi olib tashlandi. Faqat ilova yangilanadi |
| 3.5 | 11 | Shaxmat: blits, kunlik va jamoaviy (ovoz berib). Protokol 4 — eski ilova ulanmoqchi bo‘lsa, yangi versiya havolasini oladi |
| 3.4 | 10 | O‘yinlar silliq: TCP kechikishsiz (noDelay), server orqa fonda sekinlashtirilmaydi (ProcessType Interactive), fizika 30 Hz aniq taymerda, ekran holatlar orasini 60 Hz da to‘ldiradi, o‘z odamcha va raketka serverni kutmay yuradi |
| 3.3 | 9 | Tozalovchi mashina qor ko‘zga yaqqol tashlanganda chiqadi (ilgari juda kech chiqardi), keyingi o‘tishgacha dam olish 30 → 15 soniya |
| 3.2 | 8 | Yangi nom (HomeView), Mac mini'dan yuklab olish sahifasi, yangi versiya haqida xabar |
| 3.1 | 7 | Sport o‘yinlari: voleybol, stol tennisi, penalti, basketbol, arqon tortish |

**Yangi versiya chiqarish tartibi:** `HomeView/Resources/Info.plist` da `CFBundleShortVersionString` (masalan 3.4) va `CFBundleVersion` (bittaga ko‘p) ni o‘zgartiring, keyin Mac mini'da `./deploy.sh "nima o‘zgardi"`. Ilovalar aynan `CFBundleVersion` raqamini solishtiradi.

---

## 9. TestFlight versiyasi (Xcode)

Bitta kod — ikki xil yig‘ish:

| | DMG (`make_dmg.sh`, `deploy.sh`) | TestFlight (`HomeView.xcodeproj`) |
|---|---|---|
| Bundle ID | `uz.homeview.app` | `com.home-view` |
| Sandbox | yo‘q | bor (App Store talabi) |
| Birinchi ochish | "Open Anyway" kerak | oddiy, TestFlight'dan |
| Yangilanish | Mac mini sahifasi + kartochka | TestFlight o‘zi |
| Kodda belgi | — | `APPSTORE` (yuklab olish kartochkasi o‘chiq) |

**Birinchi marta:**
1. `HomeView/HomeView.xcodeproj` ni oching. Target → Signing & Capabilities: Team to‘g‘ri tanlanganini tekshiring (kerak bo‘lsa almashtiring), "Automatically manage signing" yoqilgan.
2. ⌘R bilan ishga tushirib, sandbox ichida tekshiring: qor oynalar ustiga tushadimi (oynalar joyini o‘qish), ofisga ulanadimi (Bonjour va qo‘lda manzil), ⌃⌥G, sozlamalar oynasi, shaxmat oynasi.
3. App Store Connect → Apps → "+" → New App: macOS, Bundle ID `com.home-view`, nom (band bo‘lsa — boshqasi), SKU.
4. Product → Archive → Distribute App → App Store Connect → Upload. Xcode build raqamini o‘zi oshiradi.
5. TestFlight → tashqi guruh → build qo‘shish → ochiq havola.

**Hamkasblar uchun:** TestFlight'dan o‘rnatishdan oldin DMG'dan o‘rnatilgan HomeView'ni yopib, savatga tashlash kerak. Sandbox ichidagi ilova eski sozlamalarni o‘qiy olmaydi: ism va odamcha bir marta qayta kiritiladi, ofis serveri uni yangi odam deb ko‘radi.

**Versiya raqami:** Xcode loyihasida `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION` (Build Settings), DMG'da — `Resources/Info.plist`. Ikkalasini bir xil ushlang.

**Zaxira:** loyiha ochilmasa — `brew install xcodegen`, keyin `cd HomeView && xcodegen` (`project.yml` dan qayta yaratadi).

---

## 10. macOS 26 imkoniyatlari (3.7)

| Imkoniyat | Qayerda | Nima beradi |
|---|---|---|
| **Liquid Glass ikonka** | `AppStore/AppIcon.icon` (Icon Composer formati) | Uyning to‘rt ko‘zli derazasi — har ko‘zida bitta fasl (qish, bahor, yoz, kuz — soat yo‘nalishida). Uch qatlam: uy, fasllar, deraza romi. macOS uy va romga shisha yaltirog‘i va chuqurlik beradi, fasl rasmlari esa yorqin qoladi; yorug‘/qorong‘i/rangli rejimlarga o‘zi moslashadi. Icon Composer'da ochib tahrirlash mumkin. DMG'da `make_dmg.sh` uni `actool` bilan kompilyatsiya qiladi |
| **Shisha kartochkalar** | `Toasts.swift` | O‘ng yuqoridagi kartochkalar `glassEffect` bilan; yonma-yon turganlari bir-biriga suyuqlikdek quyiladi (`GlassEffectContainer`) |
| **Shisha tugmalar** | kartochkalar, shaxmat, hamkasblar oynasi | `.glass` va `.glassProminent` uslublari |
| **Ekranga sinxron sport** | `SportStage.swift` | Voleybol, tennis, arqon — monitor chastotasida (ProMotion'da 120 kadr/s) `CADisplayLink` bilan |
| **Spotlight amallari** | `Intents.swift` | ⌘ + Space → "HomeView band", "HomeView qish", "HomeView qorni tozala", "HomeView shaxmat", "HomeView hamkasblar". Shortcuts ilovasida ham bor |
| **Fasl belgisi** | menyu satri | ❄ qish, 🌸 bahor, ☀ yoz, 🍂 kuz |
| **Aksent rang** | `Assets.xcassets/AccentColor` | Ilova ranglari ikonkaning ko‘k rangiga mos |

---

## 11. Ob-havo (1.0.0)

Har faslda 4 holat. ❄ → **Ob-havo** yoki Sozlamalar → **Ob-havo** → "Holat". "Avtomatik"da holat 20–45 daqiqada o‘zi almashadi va kun vaqtiga qaraydi (chiroq qo‘ng‘izlari faqat kechasi, jazirama faqat kunduzi).

| Fasl | Holatlar |
|---|---|
| ❄️ Qish | 🌨 Qor yog‘moqda · 🧊 Muz va qor (sumalaklar, qirov, yerda muz) · 🌬 Bo‘ron (oq to‘zon) · ✨ Ayozli quyosh (muz uchqunlari) |
| 🌸 Bahor | 🌸 Gullar · 🌦 Bahor yomg‘iri (ko‘lmak, to‘lqin) · ⛈ Momaqaldiroq (chaqmoq) · 🌈 Kamalak |
| ☀️ Yoz | 🌾 Terak paxmog‘i · ☀️ Jazirama (quyosh nurlari) · 🌧 Yozgi jala · 🌙 Yulduzli kecha (chiroq qo‘ng‘izlari) |
| 🍂 Kuz | 🍂 Xazonrezgi · ☔️ Kuzgi yomg‘ir (barg + yomg‘ir) · 🌫 Tuman · 🍃 Kuzgi shamol |

"Qor miqdori" slayderi yomg‘ir kuchiga ham ta’sir qiladi. Effektlarning hammasi Core Animation — GPU chizadi, ilova faqat taymerlarni sanaydi.

## 12. Rasmlar

`HomeView/Art/` — 65 ta PNG (har nuqtaga 8 piksel), `tools/art/` dagi Python skriptlari bilan vektor grafika sifatida chizilgan. Kurtka, shapka va yuz kulrang chizilgan — ilova ularni tanlangan rangga bo‘yaydi. Rasmlar topilmasa (masalan, `swift run`), ilova avvalgi kod bilan chizilgan rasmlarga qaytadi. Rasmni o‘zgartirish: `tools/art/README.md`.

Hali eski uslubda: bahor, yoz va kuz yodgorliklari (lolazor, tarvuz uyumi, qo‘riqchi qo‘g‘irchoq).
