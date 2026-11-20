import random
from lib import *

def snow_sphere(c, cx, cy, r, seed):
    circle(c, cx, cy, r)
    fill(c, radial(cx - r * 0.38, cy + r * 0.42, r * 0.05, cx, cy, r * 1.02,
                   [(0, rgb(0xFFFFFF)), (0.55, rgb(0xF3F7FB)), (0.85, rgb(0xDCE6F1)), (1, rgb(0xC3D2E4))]))
    c.save(); circle(c, cx, cy, r); c.clip()
    rnd = random.Random(seed)
    for _ in range(int(r * 9)):
        a = rnd.uniform(0, 2 * math.pi); d = r * math.sqrt(rnd.random())
        x, y = cx + math.cos(a) * d, cy + math.sin(a) * d
        circle(c, x, y, rnd.uniform(0.12, 0.38))
        fill(c, rgb(0x9FB4CC, rnd.uniform(0.08, 0.22)) if rnd.random() < 0.6 else rgb(0xFFFFFF, 0.7))
    # o'ng chetdagi aks nur
    path(c, (cx + r * 0.62, cy - r * 0.62), ("C", cx + r * 1.02, cy - r * 0.1, cx + r * 0.92, cy + r * 0.45, cx + r * 0.7, cy + r * 0.72),
         ("C", cx + r * 0.84, cy + r * 0.3, cx + r * 0.86, cy - r * 0.2, cx + r * 0.62, cy - r * 0.62))
    fill(c, rgb(0xFFFFFF, 0.45))
    c.restore()


def snowman():
    out = []
    cv = Canvas("hv_sm_bottom", (-15.5, -1.5, 31, 30)); c = cv.c
    cv.soft(lambda cc: (ellipse(cc, 1, 0.2, 13.5, 1.5), cc.set_source_rgba(0.35, 0.45, 0.6, 0.55), cc.fill()), 0.8)
    snow_sphere(c, 0, 13, 14, 1)
    out.append(cv.save())
    cv = Canvas("hv_sm_middle", (-11.5, -11.5, 23, 23)); c = cv.c
    snow_sphere(c, 0, 0, 10.5, 2)
    ellipse(c, 0, 9.3, 5.2, 1.4); fill(c, rgb(0x9FB4CC, 0.25))
    out.append(cv.save())
    cv = Canvas("hv_sm_head", (-9, -9, 18, 18)); c = cv.c
    snow_sphere(c, 0, 0, 8, 3)
    out.append(cv.save())

    cv = Canvas("hv_sm_face", (-4.5, -5.5, 15.5, 9.5)); c = cv.c
    for x in [-2.8, 2.8]:
        circle(c, x, 2.2, 1.15)
        fill(c, radial(x - 0.3, 2.6, 0.05, x, 2.2, 1.2, [(0, rgb(0x5A5F66)), (1, rgb(0x15171A))]))
        circle(c, x - 0.35, 2.6, 0.3); fill(c, rgb(0xFFFFFF, 0.85))
    path(c, (0, 1.05), ("C", 3.0, 0.8, 7.0, 0.1, 9.8, -0.55), ("C", 7.0, -0.9, 3.0, -1.4, 0, -1.6))
    fill(c, linear(0, 1, 0, -1.6, [(0, rgb(0xFFA040)), (0.5, rgb(0xF57C00)), (1, rgb(0xC85A00))]))
    for x in [2.2, 4.3, 6.3]:
        line(c, [(x, 0.9 - x * 0.06), (x + 0.4, -1.3 + x * 0.05)], rgb(0x9C4A00, 0.5), 0.22)
    for i in range(5):
        t = i / 4
        x, y = -3.6 + 7.2 * t, -3.3 - math.sin(t * math.pi) * 1.1
        circle(c, x, y, 0.62)
        fill(c, radial(x - 0.15, y + 0.15, 0.05, x, y, 0.65, [(0, rgb(0x4A4F55)), (1, rgb(0x15171A))]))
    out.append(cv.save())

    HAT = (-9.5, 4.5, 19, 15.5)
    cv = Canvas("hv_sm_tophat", HAT); c = cv.c
    ellipse(c, 0, 7.4, 8.6, 1.5)
    fill(c, linear(0, 8.9, 0, 5.9, [(0, rgb(0x3A3D42)), (1, rgb(0x0E0F11))]))
    rrect(c, -5.8, 7.3, 11.6, 10.4, 1.4)
    fill(c, linear(-5.8, 0, 5.8, 0, [(0, rgb(0x3E4248)), (0.35, rgb(0x1B1D20)), (1, rgb(0x0A0B0C))]))
    ellipse(c, 0, 17.6, 5.8, 0.9)
    fill(c, rgb(0x2A2D31))
    line(c, [(-4.4, 8.4), (-4.2, 16.8)], rgb(0xFFFFFF, 0.12), 0.6)
    out.append(cv.save())
    cv = Canvas("hv_sm_tophat_band", HAT); c = cv.c
    rrect(c, -5.85, 8.6, 11.7, 2.4, 0.4)
    fill(c, linear(0, 11, 0, 8.6, [(0, gray(1.0)), (1, gray(0.7))]))
    out.append(cv.save())

    cv = Canvas("hv_sm_bucket", HAT); c = cv.c
    poly(c, [(-7.2, 5.8), (7.2, 5.8), (5.4, 17.2), (-5.4, 17.2)])
    fill(c, linear(-7, 0, 7, 0, [(0, gray(0.95)), (0.3, gray(1.0)), (0.55, gray(0.78)), (1, gray(0.62))]))
    for y in [9.0, 13.4]:
        line(c, [(-6.7 + (y - 5.8) * 0.16, y), (6.7 - (y - 5.8) * 0.16, y)], gray(0.55, 0.5), 0.35)
    rrect(c, -7.6, 5.2, 15.2, 2.0, 0.8)
    fill(c, linear(0, 7.2, 0, 5.2, [(0, gray(0.86)), (1, gray(0.6))]))
    path(c, (-6.6, 7.0), ("C", -9.4, 9.0, -9.0, 13.0, -6.0, 15.0), close=False)
    stroke(c, rgb(0x8A9097), 0.6)
    out.append(cv.save())

    cv = Canvas("hv_sm_doppi", HAT); c = cv.c
    path(c, (-7.6, 5.6), ("C", -7.8, 9.0, -7.2, 12.0, -6.6, 13.0), ("C", -2.2, 14.0, 2.2, 14.0, 6.6, 13.0),
         ("C", 7.2, 12.0, 7.8, 9.0, 7.6, 5.6))
    fill(c, linear(-7.6, 0, 7.6, 0, [(0, rgb(0x2C2C2C)), (0.5, rgb(0x161616)), (1, rgb(0x090909))]))
    for cx in [-3.6, 2.6]:
        path(c, (cx - 1.7, 6.6), ("C", cx - 2.3, 9.0, cx - 0.6, 11.4, cx + 1.6, 11.0),
             ("C", cx + 2.4, 10.9, cx + 2.4, 10.1, cx + 1.8, 9.9), ("C", cx + 0.3, 9.9, cx - 0.5, 8.6, cx - 0.4, 7.0),
             ("C", cx - 0.6, 6.4, cx - 1.3, 6.3, cx - 1.7, 6.6))
        fill(c, rgb(0xF4F4F4))
    rrect(c, -7.7, 5.2, 15.4, 1.0, 0.3); fill(c, rgb(0xEDEDED))
    out.append(cv.save())

    cv = Canvas("hv_sm_beanie", HAT); c = cv.c
    path(c, (-7.8, 6.4), ("C", -8.2, 13.0, -3.8, 16.4, 0, 16.4), ("C", 3.8, 16.4, 8.2, 13.0, 7.8, 6.4))
    fill(c, radial(-2.6, 13.6, 0.4, 0, 10, 9, [(0, gray(1.0)), (0.75, gray(0.88)), (1, gray(0.7))]), preserve=True)
    c.save(); c.clip()
    for x in [i * 1.2 - 8 for i in range(14)]:
        line(c, [(x, 6), (x + 0.3, 17)], gray(0.35, 0.12), 0.32)
    c.restore()
    rrect(c, -8.2, 5.0, 16.4, 3.4, 1.3)
    fill(c, linear(0, 8.4, 0, 5.0, [(0, gray(0.86)), (1, gray(0.66))]))
    out.append(cv.save())
    cv = Canvas("hv_sm_pompom", HAT); c = cv.c
    def fuzz(cc):
        for i in range(16):
            a = i / 16 * 2 * math.pi
            circle(cc, math.cos(a) * 2.0, 16.8 + math.sin(a) * 2.0, 1.0)
            cc.set_source_rgba(0.97, 0.98, 1.0, 0.9); cc.fill()
    cv.soft(fuzz, 0.15)
    circle(c, 0, 16.8, 2.3)
    fill(c, radial(-0.8, 17.6, 0.2, 0, 16.8, 2.5, [(0, rgb(0xFFFFFF)), (1, rgb(0xE8EEF4))]))
    out.append(cv.save())

    DECOR = (-23, -8, 46, 24)
    cv = Canvas("hv_sm_decor", DECOR); c = cv.c
    wood = rgb(0x5D4037)
    for pts, w in [([(-9, 2), (-15, 6.4), (-21, 11)], 1.5), ([(-16.6, 7.6), (-18.6, 13.6)], 1.0), ([(-19.2, 9.6), (-22.2, 9.8)], 0.8),
                   ([(9, 2), (15, 6.6), (21, 11)], 1.5), ([(16.8, 7.8), (21.8, 6.0)], 1.0), ([(19.0, 9.6), (19.6, 13.2)], 0.8)]:
        line(c, pts, wood, w)
        line(c, pts, rgb(0x8D6E63, 0.5), w * 0.35)
    for y in [3.4, -1.2, -5.8]:
        circle(c, 0.4, y, 1.15)
        fill(c, radial(0.1, y + 0.3, 0.05, 0.4, y, 1.2, [(0, rgb(0x5A5F66)), (1, rgb(0x15171A))]))
    out.append(cv.save())
    cv = Canvas("hv_sm_scarf", DECOR); c = cv.c
    path(c, (-9.6, 6.6), ("C", -6, 5.6, 6, 5.6, 9.6, 6.6), ("L", 9.4, 10.6), ("C", 6, 11.6, -6, 11.6, -9.4, 10.6))
    fill(c, linear(0, 11.6, 0, 5.6, [(0, gray(1.0)), (0.5, gray(0.88)), (1, gray(0.7))]))
    for x in [-6, -2, 2, 6]:
        line(c, [(x, 6.0), (x, 11.2)], gray(0.4, 0.15), 0.5)
    path(c, (3.0, 7.0), ("C", 2.6, 3.0, 3.4, -1.0, 3.0, -4.2), ("L", 7.4, -4.0), ("C", 7.6, -0.6, 7.0, 3.2, 7.4, 7.0))
    fill(c, linear(3, 0, 7.4, 0, [(0, gray(0.92)), (1, gray(0.68))]))
    for x in [3.4, 4.4, 5.4, 6.4]:
        line(c, [(x, -4.0), (x, -5.4)], gray(0.8), 0.35)
    out.append(cv.save())
    return out


def santa():
    out = []
    cv = Canvas("hv_santa_body", (-57, -9, 211, 63)); c = cv.c
    gold = [(0, rgb(0xFFE38A)), (0.5, rgb(0xE6B53C)), (1, rgb(0xA67C1A))]
    line(c, [(30, 9), (70, 6.6), (112, 6.2), (152, 6.0)], rgb(0xC9A040), 0.9)
    # Qop
    path(c, (-56, 10), ("C", -57, 22, -50, 28, -45, 27), ("C", -38, 26, -35, 18, -37, 9), ("Z" if False else "L", -37, 9))
    fill(c, radial(-49, 20, 1, -46, 17, 13, [(0, rgb(0xA98262)), (1, rgb(0x6B4A33))]))
    for (x, y, col) in [(-50, 26, 0xD32F2F), (-44, 27.5, 0x2E7D32), (-47, 29.5, 0x1E88E5)]:
        rrect(c, x - 2.3, y - 2, 4.6, 4.2, 0.6); fill(c, rgb(col))
        line(c, [(x, y - 2), (x, y + 2.2)], rgb(0xFFD54F), 0.5)
    rrect(c, -50.5, 24, 8, 2.2, 1); fill(c, rgb(0x5D4037))
    # Qorqiz
    path(c, (-40.5, 8), ("C", -41.5, 16, -40, 22, -36.5, 25.5), ("L", -30.5, 25.5), ("C", -27.5, 22, -26.5, 15, -27.5, 8))
    fill(c, linear(-41, 0, -27, 0, [(0, rgb(0x64B5F6)), (0.5, rgb(0x1E88E5)), (1, rgb(0x0D47A1))]))
    rrect(c, -41.2, 7.6, 14.2, 2.0, 0.9); fill(c, rgb(0xF4F8FC))
    line(c, [(-34, 9.5), (-34, 24.5)], rgb(0xF4F8FC), 1.0)
    path(c, (-37.8, 28.6), ("C", -40.2, 24, -40.6, 19, -39.2, 15.6), close=False)
    stroke(c, rgb(0xC69C3F), 1.6)
    circle(c, -33.5, 29.2, 4.6)
    fill(c, radial(-34.8, 30.4, 0.3, -33.5, 29.2, 5, [(0, rgb(0xFFE3CF)), (1, rgb(0xE9B99A))]))
    circle(c, -31.6, 29.8, 0.55); fill(c, rgb(0x1A1A1A))
    circle(c, -31.2, 28.0, 0.9); fill(c, rgb(0xF48FB1, 0.6))
    path(c, (-39.2, 31.6), ("C", -39.4, 36.6, -27.6, 36.6, -27.8, 31.6), ("L", -28.6, 33.4), ("C", -31, 32.6, -36, 32.6, -38.4, 33.4))
    fill(c, linear(0, 37, 0, 31.6, [(0, rgb(0x90CAF9)), (1, rgb(0x1E88E5))]))
    rrect(c, -39.6, 31.2, 12.2, 2.0, 0.9); fill(c, rgb(0xF4F8FC))
    # Qorbobo
    path(c, (-24.5, 8), ("C", -25.6, 18, -23.6, 27, -19, 29.6), ("L", -9.5, 29.6), ("C", -5.2, 26, -4.0, 17, -5.0, 8))
    fill(c, linear(-25, 0, -5, 0, [(0, rgb(0xEF5350)), (0.45, rgb(0xD32F2F)), (1, rgb(0x8E1414))]))
    rrect(c, -25, 14.4, 20.4, 3.2, 0.6); fill(c, linear(0, 17.6, 0, 14.4, [(0, rgb(0x3A3A3A)), (1, rgb(0x141414))]))
    rrect(c, -16.8, 14.2, 4.2, 3.6, 0.6); fill(c, linear(0, 17.8, 0, 14.2, gold))
    rrect(c, -25.2, 7.4, 20.8, 2.4, 1.0); fill(c, rgb(0xF4F8FC))
    line(c, [(-14.8, 9.6), (-14.8, 14.2)], rgb(0xF4F8FC), 1.2)
    circle(c, -13, 34, 5.8)
    fill(c, radial(-14.6, 35.6, 0.3, -13, 34, 6.2, [(0, rgb(0xFFE3CF)), (1, rgb(0xE6AE8E))]))
    path(c, (-20.4, 33.6), ("C", -21.2, 27.6, -17.6, 22.6, -12.6, 22.4), ("C", -8.2, 22.8, -5.6, 27.0, -6.0, 32.2),
         ("C", -7.6, 31.0, -9.6, 31.4, -11.6, 32.6), ("C", -14.4, 31.0, -17.4, 31.6, -20.4, 33.6))
    fill(c, radial(-14, 29, 0.5, -13, 28, 8, [(0, rgb(0xFFFFFF)), (1, rgb(0xD5DEE7))]))
    circle(c, -10.4, 35.6, 0.65); fill(c, rgb(0x1A1A1A))
    circle(c, -7.6, 33.2, 1.35); fill(c, radial(-7.9, 33.5, 0.1, -7.6, 33.2, 1.4, [(0, rgb(0xF8A5A5)), (1, rgb(0xD96B6B))]))
    path(c, (-13.0, 33.0), ("C", -10.6, 34.4, -8.4, 33.8, -7.4, 32.6), close=False); stroke(c, rgb(0xFFFFFF), 1.4)
    path(c, (-20.2, 38.2), ("C", -18.0, 44.0, -18.6, 47.6, -17.0, 50.2), ("C", -14.0, 46.0, -9.0, 41.0, -6.0, 38.2))
    fill(c, linear(-20, 0, -6, 0, [(0, rgb(0xEF5350)), (1, rgb(0x9E1B1B))]))
    rrect(c, -20.8, 36.4, 15.8, 3.2, 1.5); fill(c, linear(0, 39.6, 0, 36.4, [(0, rgb(0xFFFFFF)), (1, rgb(0xD5DEE7))]))
    circle(c, -17, 50.2, 2.5); fill(c, radial(-17.7, 50.9, 0.2, -17, 50.2, 2.6, [(0, rgb(0xFFFFFF)), (1, rgb(0xDCE4EC))]))
    # Chana
    path(c, (-46, 0), ("L", -46, 17), ("Q", -46, 20.4, -38, 19.4), ("L", 14, 11.4), ("Q", 26, 8.6, 30, 17.2),
         ("Q", 36, 3.6, 26, 0))
    fill(c, linear(0, 20, 0, 0, [(0, rgb(0xE53935)), (0.6, rgb(0xB71C1C)), (1, rgb(0x6D0F0F))]), preserve=True)
    stroke(c, linear(0, 20, 0, 0, gold), 1.4)
    path(c, (-42, 4.0), ("C", -30, 8.0, -12, 3.0, 4, 6.0), ("C", 12, 7.6, 18, 5.0, 22, 3.4), close=False)
    stroke(c, rgb(0xFFD54F, 0.7), 0.7)
    for x in [-36, -16, 4]:
        circle(c, x, 3.4, 1.2); fill(c, rgb(0xFFD54F))
    # Oyoqlar
    path(c, (-50, -7), ("L", 28, -7), ("Q", 40, -7, 38, 4.4), close=False)
    stroke(c, linear(0, -6, 0, -8, gold), 2.0)
    line(c, [(-50, -7.3), (28, -7.3)], rgb(0xFFF4C4, 0.8), 0.5)
    for x in [-36, -12, 12]:
        line(c, [(x, -7), (x, 0)], rgb(0xC9A040), 1.5)
    out.append(cv.save())

    cv = Canvas("hv_santa_reindeer", (-17, -2, 47, 36)); c = cv.c
    fur = [(0, rgb(0xB08968)), (0.5, rgb(0x8D6E63)), (1, rgb(0x5D4037))]
    ellipse(c, 0, 5.6, 14, 6.6)
    fill(c, linear(0, 12, 0, -1, fur))
    ellipse(c, -2, 2.2, 9, 2.6); fill(c, rgb(0xEFE3D6, 0.55))
    circle(c, -14, 8.2, 2.3); fill(c, rgb(0xF4EDE6))
    path(c, (8.6, 6.0), ("C", 11.0, 10.0, 12.6, 14.0, 13.6, 17.6), ("L", 18.0, 14.0), ("C", 16.8, 10.0, 14.8, 6.6, 13.6, 3.6))
    fill(c, linear(8, 4, 17, 16, fur))
    circle(c, 17, 16.4, 4.9); fill(c, radial(16, 17.6, 0.4, 17, 16.4, 5.2, [(0, rgb(0xB08968)), (1, rgb(0x6D4C41))]))
    ellipse(c, 22.4, 14.2, 5.0, 3.2); fill(c, linear(0, 17, 0, 11, [(0, rgb(0xC7A27F)), (1, rgb(0x8D6E63))]))
    circle(c, 18.6, 17.8, 0.85); fill(c, rgb(0x1A1A1A)); circle(c, 18.9, 18.1, 0.25); fill(c, rgb(0xFFFFFF))
    ellipse(c, 14.0, 19.6, 1.6, 0.9); fill(c, rgb(0x6D4C41))
    antler = rgb(0x4E342E)
    for pts in [[(15.2, 20.2), (13.6, 26.0), (10.0, 31.4)], [(13.9, 24.6), (17.2, 28.8)], [(12.0, 28.6), (12.6, 32.4)],
                [(17.6, 20.6), (18.6, 27.0), (21.6, 32.6)], [(18.4, 25.0), (21.8, 26.6)], [(20.0, 29.4), (19.4, 33.0)]]:
        line(c, pts, antler, 1.3)
        line(c, pts, rgb(0x8D6E63, 0.6), 0.45)
    circle(c, 27.2, 13.8, 1.5); fill(c, radial(26.8, 14.2, 0.1, 27.2, 13.8, 1.6, [(0, rgb(0x6D4C41)), (1, rgb(0x2B1D16))]))
    path(c, (10.0, 9.8), ("C", 12.0, 11.6, 14.0, 12.6, 16.0, 12.6), close=False)
    stroke(c, rgb(0xC62828), 1.8)
    circle(c, 13.5, 8.7, 2.1)
    fill(c, radial(12.9, 9.3, 0.1, 13.5, 8.7, 2.2, [(0, rgb(0xFFF1B0)), (0.6, rgb(0xFFC107)), (1, rgb(0xB28704))]))
    out.append(cv.save())

    # Oldingi bug'uning (Rudolf) qizil burni — ilovada alohida qatlam bo'lib miltillaydi
    cv = Canvas("hv_santa_nose", (22.7, 9.3, 9, 9)); c = cv.c
    cv.soft(lambda cc: (circle(cc, 27.2, 13.8, 3.0), cc.set_source_rgba(1, 0.25, 0.2, 0.7), cc.fill()), 0.9)
    circle(c, 27.2, 13.8, 1.7); fill(c, radial(26.7, 14.3, 0.1, 27.2, 13.8, 1.8, [(0, rgb(0xFFB3A7)), (0.5, rgb(0xFF3D2E)), (1, rgb(0xB71C1C))]))
    out.append(cv.save())

    cv = Canvas("hv_santa_leg", (-1.5, -10.5, 3.2, 11)); c = cv.c
    rrect(c, -1.05, -8.8, 2.1, 9.4, 1.0)
    fill(c, linear(-1, 0, 1, 0, [(0, rgb(0x9C7A5E)), (1, rgb(0x5D4037))]))
    rrect(c, -1.2, -10.3, 2.5, 1.8, 0.6); fill(c, rgb(0x2B1D16))
    out.append(cv.save())
    return out


if __name__ == "__main__":
    for f in snowman() + santa():
        print(f.name)
