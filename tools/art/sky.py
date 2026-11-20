from lib import *

def bird_parts():
    out = []
    # Qaldirg'och
    cv = Canvas("hv_swallow_body", (-15, -5, 31, 10)); c = cv.c
    navy = [(0, rgb(0x3949AB)), (1, rgb(0x0D1446))]
    path(c, (-6.6, 0.4), ("L", -14.6, 3.8), ("L", -10.6, 0.2), ("L", -14.6, -3.4), ("Z" if False else "L", -6.6, -0.4))
    fill(c, linear(0, 4, 0, -4, navy))
    path(c, (-8.0, 0.2), ("C", -5.0, 2.8, 4.0, 3.0, 7.6, 1.6), ("C", 9.6, 0.4, 8.6, -2.0, 6.0, -2.2),
         ("C", 2.0, -2.8, -4.0, -2.4, -8.0, 0.2))
    fill(c, linear(0, 3, 0, -2.6, navy))
    path(c, (-4.6, -1.0), ("C", -1.0, -2.6, 4.0, -2.6, 6.6, -1.6), ("C", 4.0, -0.4, -1.0, -0.2, -4.6, -1.0))
    fill(c, rgb(0xF6EFE6))
    circle(c, 7.6, 0.8, 2.5); fill(c, radial(7.0, 1.4, 0.1, 7.6, 0.8, 2.6, [(0, rgb(0x3949AB)), (1, rgb(0x0D1446))]))
    ellipse(c, 8.4, -0.7, 1.4, 0.9); fill(c, rgb(0xC62828))
    circle(c, 8.6, 1.3, 0.45); fill(c, rgb(0xFFFFFF)); circle(c, 8.7, 1.3, 0.25); fill(c, rgb(0x000000))
    poly(c, [(9.8, 0.7), (11.4, 0.3), (9.8, -0.1)]); fill(c, rgb(0x212121))
    out.append(cv.save())
    cv = Canvas("hv_swallow_wing", (-7, -1, 11, 13)); c = cv.c
    path(c, (-1.2, 0), ("C", -3.6, 4, -5.6, 8.4, -6.4, 11.6), ("C", -3.0, 11.4, 0.6, 7.6, 3.2, 1.0))
    fill(c, linear(-6, 12, 2, 0, [(0, rgb(0x0D1446)), (1, rgb(0x3949AB))]))
    for t in [0.35, 0.55, 0.75]:
        line(c, [(-1.0 + 2 * t, 0.4), (-5.6 + 3 * t, 10.6 - 6 * t)], rgb(0xFFFFFF, 0.12), 0.25)
    out.append(cv.save())

    # Turna
    cv = Canvas("hv_crane_body", (-20, -5, 46, 12)); c = cv.c
    line(c, [(-8, -1.0), (-19.4, -3.4)], rgb(0x37474F), 0.9)
    line(c, [(-8, -0.6), (-19.0, -2.2)], rgb(0x37474F), 0.9)
    path(c, (-10.0, 0.4), ("C", -8.0, 3.6, 4.0, 3.8, 8.6, 1.6), ("C", 9.4, 0.2, 7.6, -2.6, 2.0, -2.8),
         ("C", -4.0, -3.0, -9.0, -2.0, -10.0, 0.4))
    fill(c, linear(0, 3.8, 0, -3, [(0, rgb(0xFAFBFC)), (1, rgb(0xB8C4CC))]))
    path(c, (-12.6, 0.6), ("L", -9.6, 2.6), ("L", -9.4, -1.2)); fill(c, rgb(0x263238))
    path(c, (7.6, 1.8), ("C", 11.0, 2.6, 15.0, 3.6, 17.6, 4.6), close=False); stroke(c, rgb(0xECEFF1), 1.6)
    path(c, (10.6, 2.6), ("C", 13.0, 3.2, 15.4, 4.0, 17.4, 4.8), close=False); stroke(c, rgb(0x263238), 1.2)
    circle(c, 18.8, 4.6, 1.9); fill(c, rgb(0x263238))
    ellipse(c, 18.6, 6.1, 1.0, 0.6); fill(c, rgb(0xD32F2F))
    circle(c, 19.4, 4.9, 0.35); fill(c, rgb(0xFFD54F))
    poly(c, [(20.4, 5.0), (25.4, 3.6), (20.4, 3.8)]); fill(c, rgb(0x6D5A4A))
    out.append(cv.save())
    cv = Canvas("hv_crane_wing", (-11, -1, 18, 17)); c = cv.c
    def crane_shape(cc):
        pts = [(-2.0, 0.0), (-5.2, 4.0), (-8.0, 8.6), (-9.6, 12.4), (-10.4, 15.2), (-8.4, 13.4), (-7.6, 15.8), (-5.8, 13.4),
               (-4.6, 15.9), (-3.0, 13.5), (-1.6, 15.6), (0.0, 13.4), (1.6, 15.0), (2.8, 12.6), (4.6, 12.8), (5.4, 8.0),
               (5.0, 3.6), (4.2, 0.6)]
        cc.move_to(*pts[0])
        for q in pts[1:]:
            cc.line_to(*q)
        cc.close_path()
    crane_shape(c); fill(c, linear(0, 15, 0, 0, [(0, rgb(0xB0BEC5)), (1, rgb(0xF5F7F8))]))
    c.save(); crane_shape(c); c.clip()
    c.rectangle(-12, 11.2, 20, 7); fill(c, linear(0, 16, 0, 11, [(0, rgb(0x1C2429)), (1, rgb(0x37474F))]))
    for x in [-7.2, -4.4, -1.6, 1.2]:
        line(c, [(x, 6.5), (x - 0.8, 15.4)], rgb(0x78909C, 0.35), 0.3)
    c.restore()
    out.append(cv.save())

    # Laylak (yangi)
    cv = Canvas("hv_stork_body", (-30, -9, 64, 18)); c = cv.c
    line(c, [(-10.0, -2.6), (-29.0, -6.0)], rgb(0xE53935), 0.9)
    line(c, [(-10.0, -1.8), (-28.6, -4.6)], rgb(0xE53935), 0.9)
    path(c, (-13.0, 0.6), ("C", -10.0, 5.6, 6.0, 5.8, 11.0, 2.6), ("C", 12.0, 0.6, 9.6, -3.6, 2.0, -3.8),
         ("C", -6.0, -4.0, -12.6, -2.4, -13.0, 0.6))
    fill(c, linear(0, 5.6, 0, -4, [(0, rgb(0xFFFFFF)), (1, rgb(0xC9D3DA))]))
    path(c, (-16.0, 1.0), ("L", -12.0, 3.6), ("L", -11.6, -2.0)); fill(c, rgb(0x1C1C1C))
    path(c, (9.8, 2.4), ("C", 14.0, 3.6, 18.0, 5.0, 21.2, 6.2), close=False); stroke(c, rgb(0xF7F7F7), 2.2)
    circle(c, 22.6, 6.4, 2.3); fill(c, radial(22.0, 7.0, 0.1, 22.6, 6.4, 2.4, [(0, rgb(0xFFFFFF)), (1, rgb(0xD5DDE3))]))
    circle(c, 23.2, 7.0, 0.42); fill(c, rgb(0x1C1C1C))
    path(c, (24.4, 7.2), ("L", 33.6, 4.6), ("L", 24.4, 5.4)); fill(c, linear(24, 0, 34, 0, [(0, rgb(0xE53935)), (1, rgb(0xFF7043))]))
    out.append(cv.save())
    cv = Canvas("hv_stork_wing", (-15, -1, 26, 23)); c = cv.c
    def stork_shape(cc):
        pts = [(-3.0, 0.0), (-7.0, 5.6), (-10.6, 11.6), (-12.8, 16.6), (-14.2, 20.6), (-11.6, 18.4), (-10.6, 21.8),
               (-8.4, 18.6), (-7.0, 22.0), (-4.8, 18.8), (-3.2, 22.0), (-1.0, 18.8), (0.8, 21.6), (2.8, 18.4), (4.6, 20.4),
               (6.0, 17.2), (8.4, 17.0), (8.6, 11.0), (7.6, 5.0), (6.0, 0.6)]
        cc.move_to(*pts[0])
        for q in pts[1:]:
            cc.line_to(*q)
        cc.close_path()
    stork_shape(c); fill(c, linear(0, 21, 0, 0, [(0, rgb(0xDDE3E7)), (1, rgb(0xFFFFFF))]))
    c.save(); stork_shape(c); c.clip()
    c.rectangle(-16, 13.6, 28, 10); fill(c, linear(0, 22, 0, 13.6, [(0, rgb(0x0E0E0E)), (1, rgb(0x2E2E2E))]))
    for x in [-9.6, -6.0, -2.4, 1.2, 4.6]:
        line(c, [(x, 8.0), (x - 1.0, 20.6)], rgb(0x9AA6AE, 0.3), 0.32)
    c.restore()
    out.append(cv.save())

    # Havo shari
    cv = Canvas("hv_balloon", (-32, -1, 64, 99)); c = cv.c
    env = lambda cc: path(cc, (0, 96), ("C", 18, 96, 30, 82, 30, 62), ("C", 30, 46, 18, 36, 9, 26), ("L", -9, 26),
                          ("C", -18, 36, -30, 46, -30, 62), ("C", -30, 82, -18, 96, 0, 96))
    env(c); c.save(); c.clip()
    cols = [0xE53935, 0xFDD835, 0x1E88E5, 0xFFFFFF, 0x43A047, 0xFB8C00]
    for i in range(12):
        x0 = -30 + i * 5
        c.rectangle(x0, 20, 5.2, 80); fill(c, rgb(cols[i % 6]))
    c.rectangle(-32, 20, 64, 80)
    fill(c, radial(-12, 74, 2, 0, 62, 36, [(0, rgb(0xFFFFFF, 0.35)), (0.55, rgb(0xFFFFFF, 0.0)), (1, rgb(0x000000, 0.35))]))
    for i in range(1, 6):
        x = -30 + i * 10
        path(c, (x * 0.3, 96), ("C", x * 0.9, 88, x * 1.05, 70, x * 0.9, 56), ("C", x * 0.75, 44, x * 0.4, 34, x * 0.3, 26), close=False)
        stroke(c, rgb(0x000000, 0.12), 0.4)
    c.restore()
    env(c); stroke(c, rgb(0x000000, 0.25), 0.6)
    rrect(c, -9.4, 23.6, 18.8, 3.2, 1.2); fill(c, linear(0, 27, 0, 23.6, [(0, rgb(0xEF5350)), (1, rgb(0x8E1414))]))
    for (a, b) in [((-8.6, 23.6), (-8.2, 11.4)), ((8.6, 23.6), (8.2, 11.4)), ((-3, 23.6), (-3.2, 11.4)), ((3, 23.6), (3.2, 11.4))]:
        line(c, [a, b], rgb(0x5D4037), 0.4)
    for (x, col) in [(-3.6, 0xF1C27D), (3.6, 0xC68642)]:
        circle(c, x, 13.8, 2.5); fill(c, radial(x - 0.6, 14.4, 0.1, x, 13.8, 2.6, [(0, rgb(col)), (1, rgb(col, 1.0))]))
        circle(c, x + 0.9, 14.1, 0.3); fill(c, rgb(0x1A1A1A))
    path(c, (-3.6, 16.2), ("C", -5.0, 17.4, -4.6, 18.4, -3.8, 18.0), close=False); stroke(c, rgb(0x6D4C41), 0.8)
    rrect(c, -9.4, 0, 18.8, 12.2, 1.8)
    fill(c, linear(-9, 0, 9, 0, [(0, rgb(0xC8A47E)), (1, rgb(0x8D6E63))]))
    c.save(); rrect(c, -9.4, 0, 18.8, 12.2, 1.8); c.clip()
    for y in [1.6 + i * 1.6 for i in range(7)]:
        line(c, [(-9.4, y), (9.4, y)], rgb(0x5D4037, 0.45), 0.35)
    for x in [-6.4, -3.2, 0, 3.2, 6.4]:
        line(c, [(x, 0), (x, 12.2)], rgb(0x5D4037, 0.3), 0.3)
    c.restore()
    rrect(c, -10.0, 10.6, 20.0, 2.0, 0.9); fill(c, rgb(0x6D4C41))
    out.append(cv.save())
    return out


def particles():
    out = []
    P = (-8, -8, 16, 16)
    cv = Canvas("hv_p_flake_soft", P); c = cv.c
    cv.soft(lambda cc: (circle(cc, 0, 0, 4.6), cc.set_source_rgba(1, 1, 1, 1), cc.fill()), 1.4)
    circle(c, 0, 0, 3.4); fill(c, radial(-0.8, 0.8, 0.2, 0, 0, 3.6, [(0, rgb(0xFFFFFF)), (0.8, rgb(0xF4F8FC)), (1, rgb(0xC7D5E6, 0.9))]))
    out.append(cv.save())

    cv = Canvas("hv_p_flake_crystal", P); c = cv.c
    def crystal(cc, col, w):
        for k in range(6):
            a = k * math.pi / 3
            ca, sa = math.cos(a), math.sin(a)
            line(cc, [(0, 0), (ca * 6.6, sa * 6.6)], col, w)
            for d in [2.6, 4.4]:
                for side in [-1, 1]:
                    b = a + side * 0.75
                    line(cc, [(ca * d, sa * d), (ca * d + math.cos(b) * 1.8, sa * d + math.sin(b) * 1.8)], col, w * 0.8)
    crystal(c, rgb(0x9DB3CC, 0.8), 1.3)
    crystal(c, rgb(0xFFFFFF), 0.8)
    circle(c, 0, 0, 1.0); fill(c, rgb(0xFFFFFF))
    out.append(cv.save())

    cv = Canvas("hv_p_flake_dot", P); c = cv.c
    cv.soft(lambda cc: (circle(cc, 0, 0, 3.0), cc.set_source_rgba(1, 1, 1, 1), cc.fill()), 1.2)
    out.append(cv.save())

    def petal(name, base, edge):
        cv = Canvas(name, P); c = cv.c
        path(c, (0, -6.6), ("C", 4.6, -3.6, 5.4, 3.0, 2.2, 6.4), ("C", 1.2, 5.6, -1.2, 5.6, -2.2, 6.4),
             ("C", -5.4, 3.0, -4.6, -3.6, 0, -6.6))
        fill(c, radial(-1, 2, 0.5, 0, 0, 7.4, [(0, rgb(base)), (0.7, rgb(edge)), (1, rgb(edge))]))
        for a in [-0.25, 0, 0.25]:
            line(c, [(0, -5.6), (math.sin(a) * 5, 4.6)], rgb(0xFFFFFF, 0.3), 0.25)
        return cv.save()
    out.append(petal("hv_p_petal_pink", 0xFFF0F5, 0xF48FB1))
    out.append(petal("hv_p_petal_white", 0xFFFFFF, 0xF8C8D8))

    cv = Canvas("hv_p_fluff", P); c = cv.c
    import random
    rnd = random.Random(7)
    for i in range(26):
        a = rnd.uniform(0, 2 * math.pi); r = rnd.uniform(3.4, 7.2)
        path(c, (0, 0), ("C", math.cos(a + 0.3) * r * 0.4, math.sin(a + 0.3) * r * 0.4, math.cos(a - 0.2) * r * 0.7,
                         math.sin(a - 0.2) * r * 0.7, math.cos(a) * r, math.sin(a) * r), close=False)
        stroke(c, rgb(0xFFFFFF, rnd.uniform(0.5, 0.9)), 0.28)
    circle(c, 0, 0, 0.9); fill(c, rgb(0xEDE6D6))
    out.append(cv.save())

    def leaf(name, base, dark, maple):
        cv = Canvas(name, P); c = cv.c
        if maple:
            pts = []
            for i in range(10):
                a = math.pi / 2 + i * 2 * math.pi / 10
                rr = 7.0 if i % 2 == 0 else 3.6
                if i in (4, 6): rr = 5.6 if i % 2 == 0 else 3.4
                pts.append((math.cos(a) * rr, math.sin(a) * rr + 0.6))
            poly(c, pts)
        else:
            path(c, (0, -6.8), ("C", 5.2, -3.0, 5.0, 3.6, 0, 7.0), ("C", -5.0, 3.6, -5.2, -3.0, 0, -6.8))
        fill(c, radial(-1.4, 2.0, 0.3, 0, 0, 7.6, [(0, rgb(base)), (1, rgb(dark))]))
        line(c, [(0, -7.4), (0, 6.2)], rgb(dark), 0.5)
        for y in [-2.4, 0.6, 3.4]:
            line(c, [(0, y), (3.2, y + 2.2)], rgb(dark, 0.7), 0.3)
            line(c, [(0, y), (-3.2, y + 2.2)], rgb(dark, 0.7), 0.3)
        return cv.save()
    out.append(leaf("hv_p_leaf_gold", 0xFFE082, 0xE09A16, True))
    out.append(leaf("hv_p_leaf_orange", 0xFFB74D, 0xC6531A, False))
    out.append(leaf("hv_p_leaf_red", 0xEF6C5A, 0x8E1B1B, True))

    # Ob-havo zarrachalari
    cv = Canvas("hv_w_rain", (-1, -14, 2, 28)); c = cv.c
    rrect(c, -0.45, -13, 0.9, 26, 0.45)
    fill(c, linear(0, 13, 0, -13, [(0, rgb(0xFFFFFF, 0.0)), (0.7, rgb(0xDDEBF7, 0.65)), (1, rgb(0xFFFFFF, 0.9))]))
    out.append(cv.save())
    cv = Canvas("hv_w_drop", (-4, -4, 8, 8)); c = cv.c
    circle(c, 0, 0, 2.2); fill(c, radial(-0.6, 0.6, 0.1, 0, 0, 2.4, [(0, rgb(0xFFFFFF)), (1, rgb(0xB3D4F0, 0.85))]))
    out.append(cv.save())
    cv = Canvas("hv_w_firefly", (-12, -12, 24, 24)); c = cv.c
    cv.soft(lambda cc: (circle(cc, 0, 0, 6.5), cc.set_source_rgba(0.85, 1.0, 0.45, 0.55), cc.fill()), 3.2)
    circle(c, 0, 0, 1.6); fill(c, radial(0, 0, 0.1, 0, 0, 1.7, [(0, rgb(0xFFFFF0)), (1, rgb(0xE6FF6A))]))
    out.append(cv.save())
    cv = Canvas("hv_w_sparkle", (-8, -8, 16, 16)); c = cv.c
    cv.soft(lambda cc: (circle(cc, 0, 0, 2.2), cc.set_source_rgba(1, 1, 1, 0.8), cc.fill()), 1.0)
    path(c, (0, 7), ("Q", 0.7, 0.7, 7, 0), ("Q", 0.7, -0.7, 0, -7), ("Q", -0.7, -0.7, -7, 0), ("Q", -0.7, 0.7, 0, 7))
    fill(c, rgb(0xFFFFFF))
    out.append(cv.save())
    cv = Canvas("hv_w_fog", (-128, -48, 256, 96), res=3); c = cv.c
    def cloud(cc):
        for (x, y, r) in [(-80, -6, 34), (-40, 8, 42), (0, -2, 46), (40, 10, 40), (84, -4, 32), (-20, -20, 30), (24, -18, 32)]:
            circle(cc, x, y, r); cc.set_source_rgba(1, 1, 1, 0.55); cc.fill()
    cv.soft(cloud, 14)
    out.append(cv.save())
    return out


if __name__ == "__main__":
    for f in bird_parts() + particles():
        print(f.name)
