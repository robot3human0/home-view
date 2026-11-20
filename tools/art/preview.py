import numpy as np
from PIL import Image
from lib import OUT, R

def load(name):
    return Image.open(OUT / f"{name}.png").convert("RGBA")

def tint(img, hexv):
    a = np.array(img).astype(np.float32)
    col = np.array([(hexv >> 16) & 255, (hexv >> 8) & 255, hexv & 255], np.float32) / 255
    a[..., :3] = a[..., :3] * col
    return Image.fromarray(a.clip(0, 255).astype(np.uint8), "RGBA")

class Scene:
    """Nuqta koordinatalarida (y yuqoriga) sahna: Swift'dagi partLayer kabi joylash."""
    def __init__(self, x0, y0, w, h, res=R):
        self.x0, self.y0, self.w, self.h, self.res = x0, y0, w, h, res
        self.img = Image.new("RGBA", (int(w * res), int(h * res)), (0, 0, 0, 0))

    def put(self, img, box, at=(0, 0), angle=0.0, flip=False):
        bx, by, bw, bh = box
        im = img.resize((int(bw * self.res), int(bh * self.res)), Image.LANCZOS)
        if flip:
            im = im.transpose(Image.FLIP_LEFT_RIGHT); bx = -bx - bw
        if angle:
            # Pivot (0,0) atrofida aylantirish: kattaroq kanvasda
            pad = int(max(bw, bh) * self.res * 2)
            big = Image.new("RGBA", (pad * 2, pad * 2), (0, 0, 0, 0))
            px, py = int(pad + bx * self.res), int(pad - (by + bh) * self.res)
            big.alpha_composite(im, (px, py))
            big = big.rotate(np.degrees(angle), resample=Image.BICUBIC, center=(pad, pad))
            ox = int((at[0] - self.x0) * self.res - pad)
            oy = int((self.y0 + self.h - at[1]) * self.res - pad)
            self.img.alpha_composite(big, (max(ox, 0), max(oy, 0)), (max(-ox, 0), max(-oy, 0)))
            return
        ox = int((at[0] + bx - self.x0) * self.res)
        oy = int((self.y0 + self.h - (at[1] + by + bh)) * self.res)
        self.img.alpha_composite(im, (ox, oy))

LEG, ARM, BODY, TOOL = (-2.6, -11.2, 6.4, 11.4), (-2.4, -12.4, 4.8, 12.6), (-9.8, 9.6, 20.6, 33.4), (-6, -32, 27, 33)

def person(hat, hat_color, vest, skin, tool=None, worker=True, arm_angle=0.15):
    s = Scene(-14, -2, 40, 48)
    sleeve = load("hv_person_sleeve")
    hand = load("hv_person_glove") if worker else tint(load("hv_person_hand"), skin)
    def arm(color_dark):
        a = Image.alpha_composite(tint(sleeve, color_dark), hand)
        return a
    vest_dark = tuple(int(v * 0.85) for v in [(vest >> 16) & 255, (vest >> 8) & 255, vest & 255])
    vd = (vest_dark[0] << 16) | (vest_dark[1] << 8) | vest_dark[2]
    s.put(arm(vd), ARM, (-4, 22), angle=-0.1)
    s.put(load("hv_person_leg"), LEG, (-2.6, 11))
    s.put(load("hv_person_leg"), LEG, (2.6, 11))
    body = tint(load("hv_person_torso"), vest)
    body.alpha_composite(load("hv_person_stripes" if worker else "hv_person_jacket"))
    body.alpha_composite(tint(load("hv_person_head"), skin))
    body.alpha_composite(load("hv_person_face"))
    if hat == "beanie":
        body.alpha_composite(tint(load("hv_hat_beanie"), hat_color)); body.alpha_composite(load("hv_hat_beanie_pom"))
    elif hat == "cap":
        body.alpha_composite(tint(load("hv_hat_cap"), hat_color))
    elif hat == "doppi":
        body.alpha_composite(load("hv_hat_doppi"))
    else:
        body.alpha_composite(load("hv_hat_straw")); body.alpha_composite(tint(load("hv_hat_straw_band"), hat_color))
    s.put(body, BODY)
    front = arm(vest)
    if tool:
        t = load(f"hv_tool_{tool}")
        canvas = Image.new("RGBA", (int(27 * R), int(33 * R + 12.6 * R)), (0, 0, 0, 0))
        s.put(t, TOOL, (3, 22), angle=arm_angle)
    s.put(front, ARM, (3, 22), angle=arm_angle)
    return s.img

if __name__ == "__main__":
    from lib import sheet
    items = [
        ("qish ishchi", person("beanie", 0x1E3A5F, 0xF57C00, 0xF1C27D, "shovel")),
        ("bahor ishchi", person("cap", 0x2E7D32, 0xF57C00, 0xE0AC69, "rake")),
        ("yoz ishchi", person("straw", 0xC62828, 0xF57C00, 0xC68642, "broom")),
        ("kuz ishchi", person("cap", 0x6D4C41, 0xF57C00, 0xFFDBAC, "rake")),
        ("hamkasb doppi", person("doppi", 0, 0x1E88E5, 0xF1C27D, None, worker=False)),
        ("hamkasb shapka", person("beanie", 0xC62828, 0x43A047, 0x8D5524, None, worker=False)),
    ]
    sheet(items, "/tmp/people.png", cell=260, cols=6)
