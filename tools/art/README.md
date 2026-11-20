# HomeView rasmlari

Ilovadagi odamlar, qorbola, Qorbobo, mashinalar, qushlar, havo shari va yog‘ayotgan zarrachalar
shu skriptlar bilan vektor grafika sifatida chiziladi (yorug‘lik, soya, hajm), keyin PNG bo‘lib
`HomeView/Art/` papkasiga tushadi.

Har bir qism Swift kodidagi `Part.box` bilan aynan bir xil koordinatalarda chiziladi
(nuqta, y yuqoriga, (0,0) — aylanish nuqtasi), har nuqtaga 8 piksel.
Rangini foydalanuvchi tanlaydigan qismlar (kurtka, shapka, yuz) kulrang chiziladi —
ilova ularni tanlangan rangga ko‘paytirib bo‘yaydi.

```bash
pip3 install pycairo pillow numpy
cd tools/art
python3 person.py && python3 winter.py && python3 vehicles.py && python3 sky.py
cp out/*.png ../../HomeView/Art/
python3 preview.py   # /tmp/people.png — yig‘ilgan odamlarni ko‘rish
```

| Fayl | Nima chizadi |
|---|---|
| `person.py` | Odam: oyoq, yeng, qo‘lqop/qo‘l, tana, nimcha chiziqlari, bosh, yuz, 4 bosh kiyim, 3 asbob |
| `winter.py` | Qorbola (sharlar, yuz, 4 shapka, sharf), Qorbobo chanasi, bug‘u, Rudolf burni |
| `vehicles.py` | 4 fasl × 2 o‘lcham mashina, g‘ildirak, cho‘tka |
| `sky.py` | Qaldirg‘och, turna, laylak, havo shari; qor/gul/paxmoq/barg; yomg‘ir, tomchi, chiroq qo‘ng‘izi, uchqun, tuman |
