from lib import *

LEG = (-2.6, -11.2, 6.4, 11.4)
ARM = (-2.4, -12.4, 4.8, 12.6)
BODY = (-9.8, 9.6, 20.6, 33.4)
TOOL = (-6, -32, 27, 33)


def torso_path(c):
    path(c, (-6.5, 10.2),
         ("C", -6.9, 14, -7.1, 18, -6.6, 21.0),
         ("C", -6.1, 23.0, -4.3, 24.0, -1.6, 24.3),
         ("L", 2.6, 24.3),
         ("C", 5.0, 24.0, 6.6, 22.8, 6.9, 20.8),
         ("C", 7.2, 17.5, 7.0, 13.5, 6.7, 10.2),
         ("C", 4.0, 9.7, -3.8, 9.7, -6.5, 10.2))


def leg():
    cv = Canvas("hv_person_leg", LEG); c = cv.c
    rrect(c, -2.05, -9.4, 4.1, 9.9, 1.7)
    fill(c, linear(-2.05, 0, 2.05, 0, [(0, rgb(0x3A4767)), (0.45, rgb(0x2B3653)), (1, rgb(0x1B2236))]))
    line(c, [(-0.6, -2.0), (0.2, -6.2)], rgb(0xFFFFFF, 0.07), 0.6)
    # Etik
    path(c, (-2.35, -10.4), ("L", 2.9, -10.4), ("C", 3.9, -10.4, 4.0, -9.0, 3.2, -8.6),
         ("L", 1.6, -8.0), ("L", -2.25, -8.0), ("C", -2.6, -8.6, -2.6, -9.8, -2.35, -10.4))
    fill(c, linear(0, -8, 0, -10.4, [(0, rgb(0x4A423C)), (1, rgb(0x231F1C))]))
    rrect(c, -2.5, -11.0, 6.6, 0.85, 0.4)
    fill(c, rgb(0x151313))
    ellipse(c, 2.6, -8.9, 0.9, 0.35)
    fill(c, rgb(0xFFFFFF, 0.18))
    line(c, [(0.2, -8.3), (1.5, -8.6)], rgb(0xC8B9A6, 0.5), 0.25)
    return cv.save()


def sleeve():
    cv = Canvas("hv_person_sleeve", ARM); c = cv.c
    rrect(c, -1.9, -9.4, 3.8, 10.2, 1.85)
    fill(c, linear(-1.9, 0, 1.9, 0, [(0, gray(1.0)), (0.5, gray(0.9)), (1, gray(0.7))]))
    rrect(c, -1.95, -9.6, 3.9, 1.4, 0.6)
    fill(c, gray(0.74))
    line(c, [(0.5, -2.5), (0.9, -5.5)], gray(0.62, 0.35), 0.35)
    return cv.save()


def glove():
    cv = Canvas("hv_person_glove", ARM); c = cv.c
    ellipse(c, 1.35, -9.6, 0.85, 1.15)
    fill(c, rgb(0x2F333A))
    ellipse(c, 0.05, -10.4, 1.95, 2.15)
    fill(c, radial(-0.6, -9.6, 0.2, 0.05, -10.4, 2.4, [(0, rgb(0x5B616B)), (1, rgb(0x2A2E35))]))
    rrect(c, -1.9, -8.9, 3.8, 0.9, 0.4)
    fill(c, rgb(0x41464F))
    return cv.save()


def hand():
    cv = Canvas("hv_person_hand", ARM); c = cv.c
    ellipse(c, 1.25, -9.5, 0.7, 1.05)
    fill(c, gray(0.84))
    ellipse(c, 0.05, -10.3, 1.6, 1.95)
    fill(c, radial(-0.5, -9.6, 0.2, 0.05, -10.3, 2.2, [(0, gray(1.0)), (1, gray(0.8))]))
    return cv.save()


def torso():
    cv = Canvas("hv_person_torso", BODY); c = cv.c
    torso_path(c)
    fill(c, linear(-7, 0, 7, 0, [(0, gray(1.0)), (0.55, gray(0.9)), (1, gray(0.72))]), preserve=True)
    c.save(); c.clip()
    rrect(c, -8, 9.4, 16, 1.9, 0.6)
    fill(c, gray(0.78))
    # Burmalar
    path(c, (-2.5, 12), ("C", -1.0, 15, -0.5, 18, -1.8, 21.5), ("L", -1.2, 21.5), ("C", 0.4, 18, 0, 15, -2.0, 12))
    fill(c, gray(0.6, 0.25))
    ellipse(c, -4.0, 22.6, 3.2, 1.8)
    fill(c, gray(1.0, 0.35))
    c.restore()
    # Yoqa
    path(c, (-2.6, 23.2), ("C", -1.0, 24.9, 2.6, 25.0, 4.0, 23.6), ("L", 3.2, 22.4), ("C", 1.8, 23.4, -0.6, 23.4, -1.8, 22.2))
    fill(c, gray(0.97))
    line(c, [(-1.8, 22.3), (0.2, 22.9), (3.1, 22.5)], gray(0.6, 0.45), 0.3)
    return cv.save()


def stripes():
    cv = Canvas("hv_person_stripes", BODY); c = cv.c
    torso_path(c); c.clip()
    for y0, h in [(15.0, 2.0), (19.4, 1.5)]:
        c.rectangle(-8, y0, 16, h)
        fill(c, linear(0, y0 + h, 0, y0, [(0, rgb(0xF4F7FA)), (0.5, rgb(0xC9D2DA)), (1, rgb(0x9AA6B2))]))
        c.rectangle(-8, y0 + h - 0.35, 16, 0.25)
        fill(c, rgb(0xFFFFFF, 0.8))
    return cv.save()


def jacket_details():
    cv = Canvas("hv_person_jacket", BODY); c = cv.c
    torso_path(c); c.clip()
    line(c, [(4.4, 10.6), (4.6, 22.6)], rgb(0x000000, 0.28), 0.35)
    line(c, [(4.75, 10.6), (4.95, 22.6)], rgb(0xFFFFFF, 0.18), 0.25)
    rrect(c, 4.3, 19.6, 0.9, 1.6, 0.3)
    fill(c, rgb(0xB0B6BD))
    line(c, [(0.6, 14.2), (3.6, 14.3)], rgb(0x000000, 0.22), 0.35)
    line(c, [(0.6, 14.5), (3.6, 14.6)], rgb(0xFFFFFF, 0.15), 0.2)
    return cv.save()


def head():
    cv = Canvas("hv_person_head", BODY); c = cv.c
    rrect(c, -1.6, 22.4, 4.2, 3.0, 1.0)
    fill(c, gray(0.74))
    circle(c, 0.6, 28.6, 5.6)
    ellipse(c, 3.3, 25.5, 2.6, 2.1)
    fill(c, radial(-1.4, 31.0, 0.5, 0.6, 28.6, 6.6, [(0, gray(1.0)), (0.7, gray(0.9)), (1, gray(0.76))]))
    # Burun
    ellipse(c, 6.05, 28.05, 1.35, 1.15)
    fill(c, radial(5.8, 28.5, 0.1, 6.05, 28.05, 1.4, [(0, gray(0.98)), (1, gray(0.82))]))
    circle(c, 6.35, 27.45, 0.22)
    fill(c, gray(0.55, 0.6))
    # Quloq
    ellipse(c, -1.7, 28.1, 1.35, 1.8)
    fill(c, radial(-2.0, 28.6, 0.1, -1.7, 28.1, 1.9, [(0, gray(0.95)), (1, gray(0.78))]))
    path(c, (-1.4, 29.0), ("C", -2.4, 28.8, -2.3, 27.4, -1.5, 27.2), close=False)
    stroke(c, gray(0.6, 0.6), 0.3)
    # Iyak osti soyasi
    path(c, (-1.0, 23.4), ("C", 1.0, 23.0, 3.4, 23.2, 5.0, 24.5), ("C", 3.4, 24.0, 1.0, 24.0, -1.0, 24.2))
    fill(c, gray(0.55, 0.3))
    return cv.save()


def face():
    cv = Canvas("hv_person_face", BODY); c = cv.c
    # Soch (bosh kiyim ostidan ko'rinadigan qismi)
    path(c, (-4.95, 27.0), ("C", -5.6, 29.4, -5.1, 31.9, -3.6, 33.0), ("L", 0.2, 32.8),
         ("C", -1.0, 31.6, -1.4, 30.4, -1.3, 29.6), ("C", -2.4, 30.0, -3.2, 29.0, -3.0, 27.4),
         ("C", -3.6, 26.8, -4.4, 26.6, -4.95, 27.0))
    fill(c, linear(-5, 27, -1, 33, [(0, rgb(0x2A1D16)), (1, rgb(0x4A3426))]))
    path(c, (0.6, 30.6), ("L", 1.3, 30.4), ("L", 1.2, 28.7), ("L", 0.7, 28.9))
    fill(c, rgb(0x3A281D))
    # Ko'z
    ellipse(c, 3.35, 29.7, 0.95, 1.05)
    fill(c, rgb(0xFBFBFB))
    circle(c, 3.65, 29.6, 0.68)
    fill(c, radial(3.6, 29.8, 0.05, 3.65, 29.6, 0.7, [(0, rgb(0x5A3A24)), (1, rgb(0x1C120C))]))
    circle(c, 3.9, 29.95, 0.22)
    fill(c, rgb(0xFFFFFF))
    path(c, (2.45, 30.25), ("C", 2.9, 30.95, 3.9, 31.0, 4.35, 30.35), close=False)
    stroke(c, rgb(0x2A1C14, 0.75), 0.32)
    # Og'iz
    path(c, (3.0, 26.45), ("C", 3.6, 26.1, 4.4, 26.15, 4.95, 26.65), close=False)
    stroke(c, rgb(0x7A3B2E), 0.42)
    return cv.save()


def hats():
    out = []
    # Qishki shapka
    cv = Canvas("hv_hat_beanie", BODY); c = cv.c
    path(c, (-6.0, 31.3), ("C", -6.3, 35.4, -3.4, 37.5, 0.6, 37.5), ("C", 4.6, 37.5, 7.4, 35.4, 7.1, 31.3))
    fill(c, radial(-1.8, 36.0, 0.5, 0.6, 33.0, 7.5, [(0, gray(1.0)), (0.75, gray(0.88)), (1, gray(0.72))]), preserve=True)
    c.save(); c.clip()
    for x in [i * 1.05 - 6 for i in range(13)]:
        line(c, [(x, 31), (x + 0.35, 38)], gray(0.4, 0.12), 0.3)
    c.restore()
    rrect(c, -6.4, 30.1, 13.9, 2.8, 1.1)
    fill(c, linear(0, 32.9, 0, 30.1, [(0, gray(0.86)), (1, gray(0.68))]), preserve=True)
    c.save(); c.clip()
    for x in [i * 0.9 - 6.4 for i in range(16)]:
        line(c, [(x, 30.1), (x, 32.9)], gray(0.35, 0.16), 0.28)
    c.restore()
    out.append(cv.save())

    cv = Canvas("hv_hat_beanie_pom", BODY); c = cv.c
    def fuzz(cc):
        for i in range(18):
            a = i / 18 * 2 * math.pi
            circle(cc, 0.4 + math.cos(a) * 1.7, 37.9 + math.sin(a) * 1.7, 0.9)
            cc.set_source_rgba(0.97, 0.98, 1.0, 0.9); cc.fill()
    cv.soft(fuzz, 0.15)
    circle(c, 0.4, 37.9, 2.05)
    fill(c, radial(-0.4, 38.7, 0.2, 0.4, 37.9, 2.3, [(0, rgb(0xFFFFFF)), (0.8, rgb(0xF3F6F9)), (1, rgb(0xE6ECF2))]))
    out.append(cv.save())

    # Kepka
    cv = Canvas("hv_hat_cap", BODY); c = cv.c
    path(c, (-5.7, 31.0), ("C", -6.0, 35.4, -1.8, 37.0, 1.4, 36.9), ("C", 5.2, 36.8, 7.2, 34.2, 7.0, 31.0))
    fill(c, radial(-1.6, 35.8, 0.4, 0.8, 33.0, 7.0, [(0, gray(1.0)), (0.8, gray(0.88)), (1, gray(0.74))]), preserve=True)
    c.save(); c.clip()
    line(c, [(0.9, 36.9), (2.6, 31.0)], gray(0.45, 0.25), 0.3)
    line(c, [(0.9, 36.9), (-2.8, 31.0)], gray(0.45, 0.25), 0.3)
    c.restore()
    circle(c, 0.9, 36.95, 0.65)
    fill(c, gray(0.7))
    path(c, (5.4, 31.2), ("C", 7.6, 31.6, 9.8, 31.3, 11.2, 30.9), ("C", 11.4, 31.5, 11.0, 32.0, 10.4, 32.2),
         ("C", 8.6, 32.6, 7.0, 32.9, 5.6, 32.9))
    fill(c, linear(5.4, 33, 11.2, 30.9, [(0, gray(0.78)), (1, gray(0.62))]))
    line(c, [(5.6, 32.85), (10.5, 32.15)], gray(1.0, 0.35), 0.25)
    out.append(cv.save())

    # Do'ppi
    cv = Canvas("hv_hat_doppi", BODY); c = cv.c
    path(c, (-5.9, 30.8), ("C", -6.0, 33.2, -5.6, 35.0, -4.9, 35.6), ("C", -1.6, 36.4, 3.4, 36.4, 6.6, 35.6),
         ("C", 7.2, 35.0, 7.4, 33.2, 7.2, 30.8))
    fill(c, linear(-6, 0, 7.4, 0, [(0, rgb(0x2A2A2A)), (0.5, rgb(0x161616)), (1, rgb(0x0B0B0B))]), preserve=True)
    c.save(); c.clip()
    # Qalampir naqshlari: oq, uchi qayrilgan (Chust do'ppisi)
    for cx, flip in [(-2.6, 1), (3.6, 1)]:
        path(c, (cx - 1.6, 31.7), ("C", cx - 2.2, 33.6, cx - 0.6, 35.3, cx + 1.4, 35.0),
             ("C", cx + 2.1, 34.9, cx + 2.2, 34.2, cx + 1.6, 34.0),
             ("C", cx + 0.2, 34.0, cx - 0.6, 33.0, cx - 0.4, 31.9),
             ("C", cx - 0.6, 31.4, cx - 1.2, 31.3, cx - 1.6, 31.7))
        fill(c, linear(cx - 2, 31.5, cx + 2, 35, [(0, rgb(0xFFFFFF)), (1, rgb(0xDADADA))]))
    ellipse(c, -1.0, 35.1, 4.0, 0.7)
    fill(c, rgb(0xFFFFFF, 0.12))
    c.restore()
    rrect(c, -6.0, 30.5, 13.3, 0.9, 0.3)
    fill(c, rgb(0xEDEDED))
    line(c, [(-4.9, 35.6), (6.6, 35.6)], rgb(0xE0E0E0, 0.9), 0.3)
    out.append(cv.save())

    # Somon shlyapa
    cv = Canvas("hv_hat_straw", BODY); c = cv.c
    ellipse(c, 0.6, 31.4, 10.1, 1.75)
    fill(c, linear(0, 33.1, 0, 29.6, [(0, rgb(0xF1D58A)), (1, rgb(0xB8913E))]))
    c.save(); ellipse(c, 0.6, 31.4, 10.1, 1.75); c.clip()
    for x in [i * 1.1 - 10 for i in range(20)]:
        line(c, [(x, 29.6), (x + 0.6, 33.2)], rgb(0x9C7A30, 0.25), 0.22)
    c.restore()
    rrect(c, -4.7, 31.2, 10.6, 5.8, 2.2)
    fill(c, linear(-4.7, 0, 5.9, 0, [(0, rgb(0xF6DE96)), (0.6, rgb(0xE2C06A)), (1, rgb(0xB89040))]), preserve=True)
    c.save(); c.clip()
    for y in [32 + i * 0.75 for i in range(7)]:
        line(c, [(-4.7, y), (5.9, y + 0.15)], rgb(0x9C7A30, 0.22), 0.22)
    c.restore()
    out.append(cv.save())

    cv = Canvas("hv_hat_straw_band", BODY); c = cv.c
    rrect(c, -4.75, 32.0, 10.7, 1.6, 0.5)
    fill(c, linear(0, 33.6, 0, 32.0, [(0, gray(1.0)), (1, gray(0.72))]))
    out.append(cv.save())
    return out


def tools():
    out = []
    wood = [(0, rgb(0xB07C4A)), (1, rgb(0x6E4A2A))]
    # Kurak
    cv = Canvas("hv_tool_shovel", TOOL); c = cv.c
    line(c, [(-3.0, -3.0), (11.0, -21.0)], rgb(0x6E4A2A), 1.9)
    line(c, [(-2.8, -3.4), (10.8, -20.8)], rgb(0xB58353, 0.8), 0.7)
    path(c, (-4.6, -1.4), ("C", -4.9, -3.0, -2.2, -4.2, -1.4, -2.6), close=False)
    stroke(c, rgb(0x4E3420), 1.0)
    path(c, (8.6, -19.6), ("L", 16.8, -24.6), ("C", 17.4, -26.0, 16.0, -28.8, 14.4, -28.8), ("L", 6.8, -23.6),
         ("C", 6.4, -22.0, 7.4, -20.4, 8.6, -19.6))
    fill(c, linear(6.8, -20, 17, -29, [(0, rgb(0xDDE5EA)), (0.5, rgb(0xA6B4BE)), (1, rgb(0x6F7E89))]), preserve=True)
    stroke(c, rgb(0x4F5D67), 0.45)
    path(c, (9.3, -23.4), ("C", 11.6, -22.0, 14.6, -24.0, 15.8, -25.6), ("C", 15.0, -27.4, 12.0, -26.8, 9.3, -23.4))
    fill(c, rgb(0xFFFFFF, 0.95))
    line(c, [(8.0, -20.4), (16.2, -25.4)], rgb(0xFFFFFF, 0.5), 0.3)
    out.append(cv.save())

    # Xaskash
    cv = Canvas("hv_tool_rake", TOOL); c = cv.c
    line(c, [(-3.0, -3.0), (12.0, -22.0)], rgb(0x7A5634), 1.7)
    line(c, [(-2.8, -3.4), (11.8, -21.8)], rgb(0xC09060, 0.7), 0.6)
    line(c, [(8.0, -25.2), (16.4, -18.8)], rgb(0x55626C), 1.6)
    line(c, [(8.2, -25.0), (16.2, -19.0)], rgb(0xB0BCC5, 0.7), 0.5)
    for i in range(6):
        t = i / 5
        bx, by = 8.0 + 8.4 * t, -25.2 + 6.4 * t
        line(c, [(bx, by), (bx + 2.0, by - 3.4)], rgb(0x5B6872), 0.75)
    out.append(cv.save())

    # Supurgi
    cv = Canvas("hv_tool_broom", TOOL); c = cv.c
    line(c, [(-3.0, -3.0), (10.0, -19.0)], rgb(0x8A6A48), 1.6)
    line(c, [(-2.8, -3.4), (9.8, -18.8)], rgb(0xD0AA7E, 0.7), 0.55)
    path(c, (8.0, -18.0), ("L", 12.6, -21.4), ("C", 16.0, -24.0, 19.0, -27.6, 20.4, -30.2),
         ("C", 16.5, -31.6, 12.0, -31.8, 8.8, -31.0), ("C", 8.0, -27.0, 7.8, -22.0, 8.0, -18.0))
    fill(c, linear(8, -18, 18, -31, [(0, rgb(0xE6C277)), (1, rgb(0xB88A3C))]), preserve=True)
    c.save(); c.clip()
    for i in range(16):
        t = i / 15
        x0, y0 = 8.2 + 4.0 * t, -18.4 - 2.8 * t
        x1, y1 = 9.0 + 11.4 * t, -31.0 + 0.8 * t
        line(c, [(x0, y0), (x1, y1)], rgb(0x8C6424, 0.35), 0.22)
    c.restore()
    path(c, (8.6, -19.6), ("L", 12.4, -22.4), ("L", 12.9, -21.4), ("L", 9.0, -18.6))
    fill(c, rgb(0xC62828))
    out.append(cv.save())
    return out


def render_all():
    files = [leg(), sleeve(), glove(), hand(), torso(), stripes(), jacket_details(), head(), face()]
    files += hats()
    files += tools()
    return files


if __name__ == "__main__":
    for f in render_all():
        print(f.name)
