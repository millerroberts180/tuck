"""Builds every Tuck logo SVG from one set of geometry.

Usage: python3 design/logo/generate.py        (writes design/logo/svg, design/logo/web/favicon.svg
                                                and the app-icon and web-icon masters in design/logo/source)
Then:  swift design/logo/render.swift          (PNGs, Support/AppIcon.icns, favicon.ico)

The mark: one rounded line, the top edge of the screen dipping down round the notch. It is a single
colour: Tuck Blue in the app. Pulse's mark is built the same way (one 24-unit line on a 256 grid), so the
two read as siblings. Sources/TuckApp/App/TuckLogo.swift draws the same line in the app
(the notch, the menu bar, About); keep the two in step.
"""
import glob
import math
import os

ROOT = os.path.dirname(os.path.abspath(__file__))
SVG_DIR = os.path.join(ROOT, "svg")
SRC_DIR = os.path.join(ROOT, "source")
WEB_DIR = os.path.join(ROOT, "web")

# ---------------------------------------------------------------- palette
INK = "#1D2430"      # wordmark: near-black with a trace of Tuck blue, like the notch
BLUE = "#7299C5"     # Tuck Blue: the line, and the app icon's tile
PAPER = "#F4F6F9"    # light background; the wordmark on dark backgrounds
NIGHT = "#111418"    # dark background
WHITE = "#FFFFFF"    # the app icon's line, as Pulse's and Hum's icons draw theirs
# The symbol comes in each of these too, for illustrations, one colour at a time.
COLOURS = {"blue": BLUE, "purple": "#A48BC7", "green": "#7FAB94", "orange": "#D9AA69", "rose": "#CD8E91",
           "teal": "#7DAAB2"}


def f(v):
    return f"{v:.2f}".rstrip("0").rstrip(".")


def arc(r, sweep, x, y, large=0):
    return f"A{f(r)} {f(r)} 0 {large} {sweep} {f(x)} {f(y)}"


def svg(body, title, w=256, h=256, extra=""):
    return (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {f(w)} {f(h)}" width="{f(w)}" height="{f(h)}" '
            f'role="img" aria-labelledby="title"><title id="title">{title}</title>{extra}{body}</svg>\n')


def write(folder, name, content):
    os.makedirs(folder, exist_ok=True)
    with open(os.path.join(folder, name), "w") as fh:
        fh.write(content)


def path(d, fill, cls=""):
    klass = f' class="{cls}"' if cls else ""
    return f'<path{klass} fill="{fill}" d="{d}"/>'


# ---------------------------------------------------------------- symbol geometry (256 grid)
class Line:
    """One cut of the notch line, symmetric about x 128: tails along the top edge from `tail` in to the
    walls at `wall`, the walls down to the floor, and round bottom corners of radius `r`. The shoulders
    are square, softened only by the line's round join, so they read as the screen's corner meeting the
    notch rather than a curl. The small cut is bolder, with shorter tails and a deeper dip, so the dip
    stays open at 16 px. `card_half` and `card_y` place the short card that rests in the dip on the notch
    while Tuck holds something: as wide as the line, 16 units clear of the floor. It is not part of the
    logo."""

    def __init__(self, tail, wall, top, floor, r, weight, card_half, card_y):
        self.tail, self.wall, self.top, self.floor, self.r, self.h = tail, wall, top, floor, r, weight / 2
        self.card_half, self.card_y = card_half, card_y
        self.left, self.right = tail - self.h, 256 - tail + self.h
        self.top_edge, self.bottom = top - self.h, floor + self.h

    @property
    def centreline(self):
        """The line itself, for stroking (the app draws it this way, and lights it along its length)."""
        L0, W, T, F, r = self.tail, self.wall, self.top, self.floor, self.r
        return (f"M{f(L0)} {f(T)} H{f(W)} V{f(F - r)} {arc(r, 0, W + r, F)} H{f(256 - W - r)} "
                f"{arc(r, 0, 256 - W, F - r)} V{f(T)} H{f(256 - L0)}")

    @property
    def outline(self):
        """The line as one filled contour (round ends, round outer shoulders), so every renderer and
        cutter draws exactly the same shape."""
        L0, W, T, F, r, h = self.tail, self.wall, self.top, self.floor, self.r, self.h
        L1, Wr = 256 - L0, 256 - W
        return (f"M{f(L0)} {f(T - h)} H{f(W)} {arc(h, 1, W + h, T)} V{f(F - r)} {arc(r - h, 0, W + r, F - h)} "
                f"H{f(Wr - r)} {arc(r - h, 0, Wr - h, F - r)} V{f(T)} {arc(h, 1, Wr, T - h)} H{f(L1)} "
                f"{arc(h, 1, L1, T + h)} H{f(Wr + h)} V{f(F - r)} {arc(r + h, 1, Wr - r, F + h)} H{f(W + r)} "
                f"{arc(r + h, 1, W - h, F - r)} V{f(T + h)} H{f(L0)} {arc(h, 1, L0, T - h)} Z")

    def body(self, colour=BLUE):
        return path(self.outline, colour, cls="line")

    def card(self, colour=BLUE):
        x0, x1, y, h = 128 - self.card_half, 128 + self.card_half, self.card_y, self.h
        d = f"M{f(x0)} {f(y - h)} H{f(x1)} {arc(h, 1, x1, y + h)} H{f(x0)} {arc(h, 1, x0, y - h)} Z"
        return path(d, colour, cls="card")


# Both cuts sit 2 units above the canvas centre (bounds 80-172 and 66-186), the same optical lift as Pulse.
REGULAR = Line(tail=28, wall=68, top=92, floor=160, r=36, weight=24, card_half=22, card_y=120)
SMALL = Line(tail=36, wall=72, top=82, floor=170, r=36, weight=32, card_half=12, card_y=122)


# ---------------------------------------------------------------- wordmark "tuck" (outlined strokes)
SW = 24          # stem weight on the 256-tall lockup grid
HW = SW / 2
WORD_L, WORD_R = 14, 390   # outer edges of the drawn word (t crossbar, k leg)


def seg(x1, y1, x2, y2, round_end=True):
    """A straight stroke with a round start, as a filled outline. A flat end hides inside the stroke it
    joins, so no round cap pokes out past a junction."""
    L = math.hypot(x2 - x1, y2 - y1)
    nx, ny = -(y2 - y1) / L * HW, (x2 - x1) / L * HW
    end = arc(HW, 0, x2 - nx, y2 - ny) if round_end else f"L{f(x2 - nx)} {f(y2 - ny)}"
    return (f"M{f(x1 + nx)} {f(y1 + ny)} L{f(x2 + nx)} {f(y2 + ny)} {end} "
            f"L{f(x1 - nx)} {f(y1 - ny)} {arc(HW, 0, x1 + nx, y1 + ny)} Z")


def arc_stroke(cx, cy, r, a1, a2, sweep, large=0):
    """A circular stroke from angle a1 to a2 (degrees, screen coordinates) with round ends."""
    def at(rad, a):
        t = math.radians(a)
        return cx + rad * math.cos(t), cy + rad * math.sin(t)
    ro, ri = r + HW, r - HW
    o1, o2, i2, i1 = at(ro, a1), at(ro, a2), at(ri, a2), at(ri, a1)
    return (f"M{f(o1[0])} {f(o1[1])} {arc(ro, sweep, *o2, large)} {arc(HW, sweep, *i2)} "
            f"{arc(ri, 1 - sweep, *i1, large)} {arc(HW, sweep, *o1)} Z")


# Joined strokes are single contours, so there is no seam or cap bump where they meet. TuckLogo.swift's
# wordmarkPath strokes the same centre lines; keep the two in step.
T_STEM = "M32 58 V136 A40 40 0 0 0 72 176 H80 A12 12 0 0 0 80 152 H72 A16 16 0 0 1 56 136 V58 A12 12 0 0 0 32 58 Z"
# The bowl stops 8° short of the right stem's edge, inside the stem, so the two never share an edge.
U_BOWL = ("M100 100 V128 A48 48 0 0 0 195.53 134.68 L171.77 131.34 A24 24 0 0 1 124 128 V100 "
          "A12 12 0 0 0 100 100 Z")

WORD_PARTS = [
    T_STEM, seg(26, 100, 74, 100),                                    # t: stem with hook, crossbar
    U_BOWL, seg(184, 100, 184, 164),                                  # u: left stem and bowl, right stem
    arc_stroke(252, 132, 33, -45, 45, 0, large=1),                    # c
    seg(328, 50, 328, 164),                                           # k stem
    seg(372, 100, 328, 144, round_end=False),                         # k arm, ending inside the stem
    seg(378, 164, 340, 126, round_end=False),                         # k leg, ending inside the arm
]


def wordmark(ink=INK):
    return "".join(path(d, ink) for d in WORD_PARTS)


# ---------------------------------------------------------------- lockups
def placed(body, sc, tx, ty):
    return f'<g transform="translate({f(tx)} {f(ty)}) scale({f(sc)})">{body}</g>'


def horizontal(colour, word_ink):
    """The line at full size, so it and the letters share one 24-unit weight: its top edge on the x-height
    (y 100, the t's crossbar), its round floor a little below the baseline as round letters overshoot,
    then a 40-unit gap and the wordmark."""
    m = REGULAR
    dx, dy = 16 - m.left, 100 - m.top
    body = placed(m.body(colour), 1, dx, dy)
    wx = 16 + (m.right - m.left) + 40 - WORD_L
    body += f'<g transform="translate({f(wx)} 0)">{wordmark(word_ink)}</g>'
    top, bottom = 38 - 16, m.bottom + dy + 16
    return f'<g transform="translate(0 {f(-top)})">{body}</g>', wx + WORD_R + 16, bottom - top


def stacked(colour, word_ink):
    """The line centred above the wordmark, at full size, 36 units clear of the k's ascender."""
    m = REGULAR
    W = WORD_R - WORD_L + 56
    body = placed(m.body(colour), 1, W / 2 - 128, 24 - m.top_edge)
    word_y = 24 + (m.bottom - m.top_edge) + 36 - 38
    body += f'<g transform="translate({f(28 - WORD_L)} {f(word_y)})">{wordmark(word_ink)}</g>'
    return body, W, word_y + 176 + 24


def word_only(ink):
    return f'<g transform="translate(0 -26)">{wordmark(ink)}</g>', WORD_R + WORD_L, 176 - 38 + 24


# ---------------------------------------------------------------- variants
# Regenerated from scratch each time, so a renamed or dropped variant never lingers.
for old in glob.glob(os.path.join(SVG_DIR, "tuck-*.svg")):
    os.remove(old)

VARIANTS = {            # name: (line, wordmark)
    "": (BLUE, INK),
    "-reversed": (BLUE, PAPER),
    "-black": ("#000000", "#000000"),
    "-white": ("#FFFFFF", "#FFFFFF"),
}
NOTES = {"": "", "-reversed": ", for dark backgrounds", "-black": ", one colour", "-white": ", white"}

for suffix, (colour, word_ink) in VARIANTS.items():
    note = NOTES[suffix]
    if suffix != "-reversed":   # the line is one colour, so the symbol needs no reversed version
        write(SVG_DIR, f"tuck-symbol{suffix}.svg", svg(REGULAR.body(colour), f"Tuck{note}"))
        write(SVG_DIR, f"tuck-symbol-small{suffix}.svg", svg(SMALL.body(colour), f"Tuck, small sizes{note}"))
    body, w, h = horizontal(colour, word_ink)
    write(SVG_DIR, f"tuck-logo-horizontal{suffix}.svg", svg(body, f"Tuck{note}", w, h))
    body, w, h = stacked(colour, word_ink)
    write(SVG_DIR, f"tuck-logo-stacked{suffix}.svg", svg(body, f"Tuck{note}", w, h))
    body, w, h = word_only(word_ink)
    write(SVG_DIR, f"tuck-wordmark{suffix}.svg", svg(body, f"Tuck{note}", w, h))

for name, hexv in COLOURS.items():
    if name != "blue":
        write(SVG_DIR, f"tuck-symbol-{name}.svg", svg(REGULAR.body(hexv), f"Tuck, {name}"))

# How the notch shows that Tuck holds something (the small cut, as the notch draws it): for docs and
# the board, not a logo.
write(SVG_DIR, "tuck-notch-holding.svg", svg(SMALL.body() + SMALL.card(), "Tuck on the notch, holding"))


# ---------------------------------------------------------------- app icon and web icon masters (1024)
def centred(line, scale, colour=BLUE):
    """The line at `scale` of the 1024 canvas per 256 units, centred 2 % high, as Pulse's icon places its mark."""
    sc = 1024 * scale / 256
    return placed(line.body(colour), sc, 512 - 128 * sc, 496 - 126 * sc)


def app_icon(line):
    """macOS tile: 824 square with 186 corners on the 1024 grid, in Tuck Blue, with the line in white at
    62 %, as Pulse's and Hum's icons are built. A blue tile stands out in a dark Dock or menu."""
    return f'<rect x="100" y="100" width="824" height="824" rx="186" fill="{BLUE}"/>' + centred(line, 0.62, WHITE)


def full_bleed(line, scale):
    """Square Tuck Blue background for touch and PWA icons (the platform rounds or masks it)."""
    return f'<rect width="1024" height="1024" fill="{BLUE}"/>' + centred(line, scale, WHITE)


write(SRC_DIR, "appicon.svg", svg(app_icon(REGULAR), "Tuck app icon", 1024, 1024))
write(SRC_DIR, "appicon-small.svg", svg(app_icon(SMALL), "Tuck app icon, small sizes", 1024, 1024))
write(SRC_DIR, "web-touch.svg", svg(full_bleed(REGULAR, 0.7), "Tuck touch icon", 1024, 1024))
write(SRC_DIR, "web-maskable.svg", svg(full_bleed(REGULAR, 0.58), "Tuck maskable icon", 1024, 1024))

# Favicon: the small cut. Tuck Blue reads on light and dark tabs alike, so it needs no dark-mode switch.
write(WEB_DIR, "favicon.svg", svg(SMALL.body(), "Tuck"))
print("wrote", len(os.listdir(SVG_DIR)), "SVGs")
