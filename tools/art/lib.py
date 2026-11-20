"""HomeView rasmlari uchun chizish asboblari.

Koordinatalar Swift kodidagidek: nuqta (pt), y yuqoriga, (0,0) — qismning aylanish nuqtasi.
Har bir qism o'z "qutisi" (box) bilan chiziladi va R piksel/pt aniqlikda PNG bo'ladi.
"""
import math, pathlib
import cairo
import numpy as np
from PIL import Image, ImageFilter

R = 8
OUT = pathlib.Path(__file__).parent / "out"


def rgb(hexv, a=1.0):
    return ((hexv >> 16) & 255) / 255, ((hexv >> 8) & 255) / 255, (hexv & 255) / 255, a


def gray(v, a=1.0):
    return v, v, v, a


class Canvas:
    def __init__(self, name, box, res=R):
        self.name, self.box, self.res = name, box, res
        x, y, w, h = box
        self.W, self.H = int(math.ceil(w * res)), int(math.ceil(h * res))
        self.surface = cairo.ImageSurface(cairo.FORMAT_ARGB32, self.W, self.H)
        self.c = cairo.Context(self.surface)
        self.c.translate(-x * res, (y + h) * res)
        self.c.scale(res, -res)
        self.c.set_line_cap(cairo.LINE_CAP_ROUND)
        self.c.set_line_join(cairo.LINE_JOIN_ROUND)
        self.c.set_antialias(cairo.ANTIALIAS_BEST)

    # --- yumshoq soya va nur (xiralashtirilgan shakl) ---
    def soft(self, draw, radius, opacity=1.0):
        tmp = cairo.ImageSurface(cairo.FORMAT_ARGB32, self.W, self.H)
        tc = cairo.Context(tmp)
        tc.set_matrix(self.c.get_matrix())
        tc.set_antialias(cairo.ANTIALIAS_BEST)
        draw(tc)
        tmp.flush()
        stride = tmp.get_stride()
        arr = np.ndarray((self.H, stride // 4, 4), np.uint8, buffer=tmp.get_data())[:, :self.W, :].copy()
        img = Image.fromarray(arr, "RGBA").filter(ImageFilter.GaussianBlur(radius * self.res))
        data = np.ascontiguousarray(np.array(img))
        out = cairo.ImageSurface.create_for_data(bytearray(data.tobytes()), cairo.FORMAT_ARGB32, self.W, self.H, self.W * 4)
        self.c.save()
        self.c.identity_matrix()
        self.c.set_source_surface(out, 0, 0)
        self.c.paint_with_alpha(opacity)
        self.c.restore()

    def save(self):
        OUT.mkdir(parents=True, exist_ok=True)
        self.surface.write_to_png(str(OUT / f"{self.name}.png"))
        return OUT / f"{self.name}.png"


# --- yo'llar ---
def rrect(c, x, y, w, h, r):
    r = min(r, w / 2, h / 2)
    c.new_sub_path()
    c.arc(x + w - r, y + h - r, r, 0, math.pi / 2)
    c.arc(x + r, y + h - r, r, math.pi / 2, math.pi)
    c.arc(x + r, y + r, r, math.pi, 1.5 * math.pi)
    c.arc(x + w - r, y + r, r, 1.5 * math.pi, 2 * math.pi)
    c.close_path()


def ellipse(c, cx, cy, rx, ry):
    c.save()
    c.translate(cx, cy)
    c.scale(rx, ry)
    c.new_sub_path()
    c.arc(0, 0, 1, 0, 2 * math.pi)
    c.restore()
    c.close_path()


def circle(c, cx, cy, r):
    c.new_sub_path()
    c.arc(cx, cy, r, 0, 2 * math.pi)
    c.close_path()


def poly(c, pts):
    c.move_to(*pts[0])
    for p in pts[1:]:
        c.line_to(*p)
    c.close_path()


def path(c, start, *segments, close=True):
    """segments: ('L', x, y) yoki ('C', x1, y1, x2, y2, x, y) yoki ('Q', cx, cy, x, y)."""
    c.move_to(*start)
    cur = start
    for s in segments:
        if s[0] == "L":
            c.line_to(s[1], s[2]); cur = (s[1], s[2])
        elif s[0] == "C":
            c.curve_to(*s[1:]); cur = (s[5], s[6])
        elif s[0] == "Q":
            cx, cy, x, y = s[1:]
            x0, y0 = cur
            c.curve_to(x0 + 2 / 3 * (cx - x0), y0 + 2 / 3 * (cy - y0), x + 2 / 3 * (cx - x), y + 2 / 3 * (cy - y), x, y)
            cur = (x, y)
    if close:
        c.close_path()


# --- bo'yoqlar ---
def linear(x0, y0, x1, y1, stops):
    g = cairo.LinearGradient(x0, y0, x1, y1)
    for off, col in stops:
        g.add_color_stop_rgba(off, *col)
    return g


def radial(cx0, cy0, r0, cx1, cy1, r1, stops):
    g = cairo.RadialGradient(cx0, cy0, r0, cx1, cy1, r1)
    for off, col in stops:
        g.add_color_stop_rgba(off, *col)
    return g


def fill(c, source, preserve=False):
    c.set_source(source) if isinstance(source, cairo.Pattern) else c.set_source_rgba(*source)
    c.fill_preserve() if preserve else c.fill()


def stroke(c, color, width, preserve=False):
    c.set_source(color) if isinstance(color, cairo.Pattern) else c.set_source_rgba(*color)
    c.set_line_width(width)
    c.stroke_preserve() if preserve else c.stroke()


def line(c, pts, color, width):
    c.move_to(*pts[0])
    for p in pts[1:]:
        c.line_to(*p)
    stroke(c, color, width)


def mix(a, b, t):
    return tuple(a[i] * (1 - t) + b[i] * t for i in range(4))


def shade(col, k):
    """k<0 — qoraytirish, k>0 — oqartirish."""
    if k < 0:
        return tuple(col[i] * (1 + k) for i in range(3)) + (col[3],)
    return tuple(col[i] + (1 - col[i]) * k for i in range(3)) + (col[3],)


# --- tekshirish uchun varaq ---
def sheet(items, path_out, cell=180, cols=6, bg=(236, 239, 244)):
    rows = math.ceil(len(items) / cols)
    board = Image.new("RGBA", (cols * cell, rows * cell), bg + (255,))
    for i, (label, img) in enumerate(items):
        im = img.copy()
        im.thumbnail((cell - 20, cell - 20), Image.LANCZOS)
        x = (i % cols) * cell + (cell - im.width) // 2
        y = (i // cols) * cell + (cell - im.height) // 2
        board.alpha_composite(im, (x, y))
    board.save(path_out)
