"""Generate a 1366x768 'Midnight Aurora' wallpaper using only Pillow."""
import random
import math
from PIL import Image, ImageDraw, ImageFilter, ImageChops

W, H = 1366, 768
random.seed(7)

# ---------------------------------------------------------------- helpers
def vertical_gradient(stops, w=W, h=H):
    small = Image.new("RGB", (1, h))
    d = ImageDraw.Draw(small)
    for y in range(h):
        t = y / (h - 1)
        for i in range(len(stops) - 1):
            p0, c0 = stops[i]
            p1, c1 = stops[i + 1]
            if p0 <= t <= p1:
                k = 0 if p1 == p0 else (t - p0) / (p1 - p0)
                col = tuple(int(c0[j] + (c1[j] - c0[j]) * k) for j in range(3))
                d.point((0, y), fill=col)
                break
    return small.resize((w, h), Image.BILINEAR)


def radial_mask(radius):
    m = Image.new("L", (W, H), 0)
    ImageDraw.Draw(m).ellipse(
        [W / 2 - radius, H / 2 - radius, W / 2 + radius, H / 2 + radius], fill=255
    )
    return m.filter(ImageFilter.GaussianBlur(radius * 0.55))


def glow(canvas, cx, cy, radius, colour, strength):
    m = Image.new("L", (W, H), 0)
    ImageDraw.Draw(m).ellipse(
        [cx - radius, cy - radius, cx + radius, cy + radius], fill=255
    )
    m = m.filter(ImageFilter.GaussianBlur(radius * 0.55))
    col = Image.new("RGB", (W, H), tuple(int(c * strength) for c in colour))
    return ImageChops.add(canvas, ImageChops.multiply(col, Image.merge("RGB", (m, m, m))))


# ---------------------------------------------------------------- base
img = vertical_gradient(
    [(0.0, (4, 6, 16)), (0.55, (9, 14, 32)), (1.0, (13, 22, 46))]
)

img = glow(img, int(W * 0.16), int(H * 1.02), 420, (18, 120, 110), 0.85)
img = glow(img, int(W * 0.86), int(H * 0.06), 470, (96, 52, 150), 0.80)
img = glow(img, int(W * 0.60), int(H * 0.30), 340, (20, 90, 140), 0.55)

# ---------------------------------------------------------------- aurora
aw, ah = W // 2, H // 2
aur = Image.new("RGB", (aw, ah), (0, 0, 0))
ad = ImageDraw.Draw(aur)
ribbons = [((34, 226, 190), 0.16, 0.045, 26), ((86, 130, 255), 0.27, 0.060, 34),
           ((168, 92, 255), 0.38, 0.050, 30)]
for i, (colour, base, width, thickness) in enumerate(ribbons):
    phase = random.uniform(0, 6.28)
    freq = random.uniform(1.1, 1.9)
    pts = []
    for px in range(-10, aw + 11, 3):
        xn = px / aw
        cy = base + 0.055 * math.sin(xn * 6.28 * freq + phase)
        cy += 0.025 * math.sin(xn * 6.28 * freq * 2.3 + phase * 1.7)
        pts.append((px, cy * ah))
    ad.line(pts, fill=colour, width=thickness, joint="curve")
aur = aur.filter(ImageFilter.GaussianBlur(16))

# vertical streaks so the ribbons read as light shafts
streaks = Image.new("L", (aw, ah), 0)
sd = ImageDraw.Draw(streaks)
for x in range(0, aw, 3):
    v = 95 + 160 * (0.5 + 0.5 * math.sin(x * 0.55 + random.uniform(0, 6)))
    v *= random.uniform(0.7, 1.0)
    sd.line([(x, 0), (x, ah)], fill=int(v), width=2)
streaks = streaks.filter(ImageFilter.GaussianBlur(2.4))
aur = ImageChops.multiply(aur, Image.merge("RGB", (streaks, streaks, streaks)))

# fade the aurora at the top and clear a soft gutter on the left for the icons
gutter = Image.new("L", (256, 1))
gd = ImageDraw.Draw(gutter)
for x in range(256):
    t = x / 255
    gd.point((x, 0), fill=int(255 * min(1.0, 0.10 + (t / 0.34) ** 1.5 * 0.90)))
gutter = gutter.resize((W, H), Image.BILINEAR)

vfade = Image.new("L", (1, H))
vd = ImageDraw.Draw(vfade)
for y in range(H):
    t = y / (H - 1)
    vd.point((0, y), fill=int(255 * min(1.0, (t / 0.16) ** 1.2)))
vfade = vfade.resize((W, H), Image.BILINEAR)

fade = ImageChops.multiply(gutter, vfade)
aur = aur.resize((W, H), Image.BILINEAR).filter(ImageFilter.GaussianBlur(2))
aur = ImageChops.multiply(aur, Image.merge("RGB", (fade, fade, fade)))
img = ImageChops.add(img, aur.point(lambda v: int(v * 0.95)))

# ---------------------------------------------------------------- stars
stars = Image.new("RGB", (W, H), (0, 0, 0))
sd2 = ImageDraw.Draw(stars)
for _ in range(430):
    x = random.randrange(W)
    y = random.randrange(int(H * 0.62))
    b = int(30 + 210 * random.random() ** 2.6)
    sd2.point((x, y), fill=(b, b, min(255, int(b * 1.15))))
stars = stars.filter(ImageFilter.GaussianBlur(0.55))
img = ImageChops.add(img, stars)

# ---------------------------------------------------------------- ridge
def ridge(y_base, amp1, f1, amp2, f2, phase, shade):
    mask = Image.new("L", (W, H), 0)
    md = ImageDraw.Draw(mask)
    pts = [(0, H), (W, H)]
    for px in range(W, -1, -6):
        xn = px / (W - 1)
        y = y_base + amp1 * math.sin(xn * f1 + phase) + amp2 * math.sin(xn * f2 + phase * 2.3)
        pts.append((px, y * H))
    md.polygon(pts, fill=int(255 * shade))
    return mask.filter(ImageFilter.GaussianBlur(1.1))

ridge_mask = ridge(0.795, 0.045, 6.1, 0.025, 13.0, 0.7, 1.0)
ridge_mask = ImageChops.lighter(
    ridge_mask, ridge(0.875, 0.035, 4.3, 0.018, 17.0, 3.4, 0.95)
)
img = ImageChops.subtract(img, ImageChops.multiply(
    Image.merge("RGB", (ridge_mask, ridge_mask, ridge_mask)),
    Image.new("RGB", (W, H), (230, 232, 240)),
))

# ---------------------------------------------------------------- vignette + grain
vig = Image.radial_gradient("L").resize((W, H), Image.BILINEAR)
vig = vig.point(lambda v: int(v * 0.42))
img = Image.composite(Image.new("RGB", (W, H), (0, 0, 0)), img, vig)

grain = Image.effect_noise((W, H), 7).convert("RGB")
img = Image.blend(img, grain, 0.035)

img = img.filter(ImageFilter.SMOOTH)
img.save("/config/Pictures/wallpapers/midnight-aurora.png", optimize=True)
print("saved", img.size)
