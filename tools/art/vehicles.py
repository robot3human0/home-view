from lib import *

BODY = (-59, -2, 132, 58)
WHEELS = [-42, -22, 30]
PALETTES = {
    ("winter", "big"): (0xFF8F00, 0xFFB74D, 0xC56000), ("winter", "small"): (0x1E88E5, 0x64B5F6, 0x0D47A1),
    ("spring", "big"): (0x43A047, 0x81C784, 0x1B5E20), ("spring", "small"): (0x7CB342, 0xAED581, 0x33691E),
    ("summer", "big"): (0x1E88E5, 0x90CAF9, 0x0D47A1), ("summer", "small"): (0x00ACC1, 0x80DEEA, 0x006064),
    ("autumn", "big"): (0xFBC02D, 0xFFE082, 0xC17900), ("autumn", "small"): (0xEF6C00, 0xFFB74D, 0xA33A00),
}


def paint(main, light, dark, x0, x1):
    return linear(0, x1, 0, x0, [(0, rgb(light)), (0.35, rgb(main)), (1, rgb(dark))])


def vehicle(season, size):
    main, light, dark = PALETTES[(season, size)]
    cv = Canvas(f"hv_vehicle_{season}_{size}", BODY); c = cv.c
    steel = [(0, rgb(0x5F6B73)), (1, rgb(0x262D32))]
    # Yer soyasi
    cv.soft(lambda cc: (ellipse(cc, 4, 0.2, 60, 1.6), cc.set_source_rgba(0, 0, 0, 0.35), cc.fill()), 1.0)
    # Rama
    rrect(c, -58, 7, 110, 9, 2)
    fill(c, linear(0, 16, 0, 7, steel))
    # Orqa qism
    if season == "summer":
        rrect(c, -58, 17, 63, 26, 12.5)
        fill(c, linear(0, 43, 0, 17, [(0, rgb(light)), (0.3, rgb(0xFFFFFF)), (0.45, rgb(light)), (1, rgb(dark))]))
        for x in [-44, -26, -8]:
            rrect(c, x, 16.6, 2.4, 26.8, 1.0); fill(c, linear(0, 43, 0, 17, steel))
        rrect(c, -56, 28.4, 59, 3.2, 1.2); fill(c, rgb(main))
        ellipse(c, -40, 38.6, 12, 2.0); fill(c, rgb(0xFFFFFF, 0.45))
        path(c, (-30, 22), ("C", -31.6, 24.4, -31.6, 26.0, -30, 26.4), ("C", -28.4, 26.0, -28.4, 24.4, -30, 22))
        fill(c, rgb(0xFFFFFF, 0.9))
    else:
        rrect(c, -58, 16, 64, 27, 3)
        fill(c, paint(main, light, dark, 16, 43), preserve=True)
        stroke(c, rgb(dark), 0.6)
        for x in [-48, -32, -16]:
            rrect(c, x, 18, 3, 23, 1.2)
            fill(c, linear(x, 0, x + 3, 0, [(0, rgb(dark, 0.9)), (1, rgb(light, 0.6))]))
        # Orqadagi ogohlantiruvchi chiziqlar
        c.save(); c.rectangle(-58, 16, 5, 27); c.clip()
        for i in range(-2, 8):
            poly(c, [(-60, 14 + i * 5), (-53, 21 + i * 5), (-53, 23.5 + i * 5), (-60, 16.5 + i * 5)])
            fill(c, rgb(0x212121))
        c.restore()
        # Yuk
        if season == "winter":
            path(c, (-57, 42), ("C", -50, 49.5, -30, 49.0, -20, 46.4), ("C", -10, 48.8, 0, 47.0, 5, 42))
            fill(c, radial(-30, 48, 1, -26, 44, 30, [(0, rgb(0xFFFFFF)), (1, rgb(0xC9D6E6))]))
        elif season == "spring":
            path(c, (-57, 42), ("C", -48, 50, -30, 50.6, -22, 47.2), ("C", -12, 50, -2, 48.6, 5, 42))
            fill(c, radial(-30, 48, 1, -26, 44, 30, [(0, rgb(0x8D6E63)), (1, rgb(0x4E342E))]))
            for x in [-46, -34, -20, -8]:
                path(c, (x, 47.6), ("C", x - 1.6, 50.2, x - 0.6, 51.6, x + 0.2, 51.8), close=False); stroke(c, rgb(0x66BB6A), 0.7)
                ellipse(c, x - 1.0, 51.4, 1.3, 0.7); fill(c, rgb(0x81C784))
        elif season == "autumn":
            cols = [0xFBC02D, 0xEF6C00, 0xC62828, 0x8D6E63]
            for i in range(16):
                x = -55 + i * 3.8
                ellipse(c, x, 43.6 + (i % 3) * 1.2, 2.6, 1.4); fill(c, rgb(cols[i % 4]))
    # Chiqindi quvuri
    rrect(c, 5.6, 18, 2.8, 34, 1.2)
    fill(c, linear(5.6, 0, 8.4, 0, [(0, rgb(0x90A4AE)), (0.4, rgb(0xECEFF1)), (1, rgb(0x546E7A))]))
    rrect(c, 5.2, 50.4, 3.6, 2.2, 0.8); fill(c, rgb(0x263238))
    # Kabina
    path(c, (9, 16), ("L", 9, 46), ("Q", 9, 49, 12, 49), ("L", 34, 49), ("Q", 39, 49, 41.6, 44.6),
         ("L", 45.6, 34), ("Q", 46.4, 32, 46.4, 30), ("L", 46.4, 16))
    fill(c, paint(main, light, dark, 16, 49), preserve=True)
    stroke(c, rgb(dark), 0.6)
    # Oynalar (osmon aksi)
    glass = linear(0, 45, 0, 30, [(0, rgb(0xE3F2FD)), (0.45, rgb(0x90CAF9)), (1, rgb(0x37474F))])
    rrect(c, 12, 31, 11, 14, 2); fill(c, glass, preserve=True); stroke(c, rgb(0x37474F), 0.6)
    path(c, (25.5, 31), ("L", 25.5, 45), ("L", 38.8, 45), ("Q", 40.6, 45, 41.4, 43.0), ("L", 44.4, 33.4),
         ("Q", 44.8, 31, 42.6, 31))
    fill(c, glass, preserve=True); stroke(c, rgb(0x37474F), 0.6)
    # Haydovchi
    c.save(); rrect(c, 25.5, 31, 19, 14, 2); c.clip()
    path(c, (26.6, 31), ("C", 26.6, 35.6, 28.2, 36.4, 31.2, 36.4), ("C", 34.2, 36.4, 35.8, 35.6, 35.8, 31))
    fill(c, rgb(0x263238, 0.6))
    circle(c, 31.2, 39.2, 2.6); fill(c, rgb(0x263238, 0.6))
    path(c, (28.4, 40.6), ("C", 28.8, 42.6, 33.6, 42.6, 34.0, 40.6), ("L", 35.8, 40.4), ("L", 34.0, 40.0), ("C", 33.0, 40.4, 29.4, 40.4, 28.4, 40.6))
    fill(c, rgb(0x263238, 0.6))
    c.restore()
    for (x0, y0, x1, y1) in [(12.6, 39.6, 15.2, 44.6), (36.4, 39.4, 39.4, 44.6)]:
        poly(c, [(x0, y0), (x0 + 1.6, y0), (x1 + 1.6, y1), (x1, y1)]); fill(c, rgb(0xFFFFFF, 0.4))
    line(c, [(23.6, 18), (23.6, 46)], rgb(dark), 0.7)
    rrect(c, 19.4, 27.2, 3.2, 0.9, 0.4); fill(c, rgb(0x263238))
    rrect(c, 13, 16.6, 8, 1.4, 0.6); fill(c, linear(0, 18, 0, 16.6, steel))
    # Ko'zgu
    rrect(c, 44.6, 38, 2.0, 5.0, 0.8); fill(c, rgb(0x263238))
    # Tom chirog'i
    rrect(c, 22.0, 48.6, 10.0, 1.6, 0.6); fill(c, rgb(0x37474F))
    path(c, (23.2, 50.2), ("C", 23.2, 55.6, 30.8, 55.6, 30.8, 50.2))
    fill(c, radial(25.6, 53.6, 0.2, 27, 51.6, 4.6, [(0, rgb(0xFFF8E1)), (0.4, rgb(0xFFC107)), (1, rgb(0xE65100))]))
    # Old fara va bamper
    rrect(c, 43.6, 21.0, 3.4, 4.6, 1.2)
    fill(c, radial(45.6, 23.6, 0.1, 45.3, 23.3, 2.6, [(0, rgb(0xFFFFFF)), (1, rgb(0xFFE082))]))
    rrect(c, 44, 8, 14, 6.4, 1.6); fill(c, linear(0, 14.4, 0, 8, [(0, rgb(0xCFD8DC)), (0.5, rgb(0x90A4AE)), (1, rgb(0x455A64))]))
    # G'ildirak o'rinlari
    for x in WHEELS:
        c.save(); rrect(c, -60, 7, 112, 13, 2); c.clip()
        circle(c, x, 9, 10.8); fill(c, rgb(0x161B1F))
        c.restore()
    # Old moslama
    if season == "winter":
        path(c, (55.6, 0.6), ("C", 61.0, -0.6, 66.0, -1.4, 69.6, -1.0), ("C", 73.4, 8, 73.4, 20, 71.4, 30.4),
             ("C", 66.4, 29.4, 62.0, 28.4, 59.4, 26.8), ("C", 61.6, 18.0, 60.4, 8.0, 55.6, 0.6))
        fill(c, linear(56, 0, 73, 0, [(0, rgb(0x546E7A)), (0.5, rgb(0xCFD8DC)), (1, rgb(0x78909C))]), preserve=True)
        c.save(); c.clip_preserve()
        for i in range(-1, 8):
            poly(c, [(54, 2 + i * 5), (76, 6 + i * 5), (76, 8.5 + i * 5), (54, 4.5 + i * 5)])
            fill(c, rgb(main, 0.55) if i % 2 else rgb(0x212121, 0.45))
        c.restore()
        path(c, (55.6, 0.6), ("C", 61.0, -0.6, 66.0, -1.4, 69.6, -1.0), ("C", 73.4, 8, 73.4, 20, 71.4, 30.4),
             ("C", 66.4, 29.4, 62.0, 28.4, 59.4, 26.8), ("C", 61.6, 18.0, 60.4, 8.0, 55.6, 0.6))
        stroke(c, rgb(0x37474F), 0.6)
        path(c, (60.6, 1.0), ("C", 64, 3.4, 69, 4.2, 71.8, 3.0), ("C", 70.4, 6.0, 64.0, 6.4, 60.6, 1.0))
        fill(c, rgb(0xFFFFFF, 0.9))
    elif season == "spring":
        rrect(c, 57.4, 2, 3.0, 20, 1); fill(c, linear(57, 0, 61, 0, steel))
        for y in [4, 8, 12, 16, 20]:
            line(c, [(59, y), (66.6, y - 3.4)], rgb(0x78909C), 1.2)
            circle(c, 66.6, y - 3.4, 0.7); fill(c, rgb(0x546E7A))
    elif season == "summer":
        rrect(c, 55.6, 3.0, 15, 3.4, 1.6); fill(c, linear(0, 6.4, 0, 3, [(0, rgb(0xB0BEC5)), (1, rgb(0x546E7A))]))
        for x in [59, 63, 67]:
            circle(c, x, 3.4, 1.1); fill(c, rgb(0x37474F))
    elif season == "autumn":
        line(c, [(52, 12), (63.4, 9.2)], rgb(0x37474F), 2.6)
        line(c, [(52, 12.6), (63.4, 9.8)], rgb(0x90A4AE, 0.6), 0.8)
    return cv.save()


def wheel():
    cv = Canvas("hv_vehicle_wheel", (-9.5, -9.5, 19, 19)); c = cv.c
    circle(c, 0, 0, 9.1)
    fill(c, radial(-2.4, 2.4, 0.5, 0, 0, 9.3, [(0, rgb(0x3A3F44)), (0.8, rgb(0x1C1F22)), (1, rgb(0x0C0D0E))]))
    for i in range(18):
        a = i / 18 * 2 * math.pi
        line(c, [(math.cos(a) * 7.6, math.sin(a) * 7.6), (math.cos(a) * 9.0, math.sin(a) * 9.0)], rgb(0x000000, 0.5), 0.6)
    circle(c, 0, 0, 5.0)
    fill(c, radial(-1.4, 1.6, 0.3, 0, 0, 5.2, [(0, rgb(0xFFFFFF)), (0.5, rgb(0xB0BEC5)), (1, rgb(0x546E7A))]))
    for i in range(5):
        a = i / 5 * 2 * math.pi + 0.3
        circle(c, math.cos(a) * 3.1, math.sin(a) * 3.1, 0.55); fill(c, rgb(0x37474F))
    circle(c, 0, 0, 1.3); fill(c, rgb(0x455A64))
    line(c, [(-4.6, -0.6), (4.6, 0.6)], rgb(0x263238, 0.35), 0.6)
    return cv.save()


def brush():
    cv = Canvas("hv_vehicle_brush", (-10, -10, 20, 20)); c = cv.c
    for i in range(36):
        a = i / 36 * 2 * math.pi
        line(c, [(math.cos(a) * 3.4, math.sin(a) * 3.4), (math.cos(a + 0.12) * 9.6, math.sin(a + 0.12) * 9.6)],
             rgb(0x3E2723 if i % 2 else 0x6D4C41), 0.7)
    circle(c, 0, 0, 3.6)
    fill(c, radial(-1, 1, 0.2, 0, 0, 3.8, [(0, rgb(0xB0BEC5)), (1, rgb(0x455A64))]))
    circle(c, 0, 0, 1.0); fill(c, rgb(0x263238))
    return cv.save()


if __name__ == "__main__":
    for season in ["winter", "spring", "summer", "autumn"]:
        for size in ["big", "small"]:
            print(vehicle(season, size).name)
    print(wheel().name, brush().name)
