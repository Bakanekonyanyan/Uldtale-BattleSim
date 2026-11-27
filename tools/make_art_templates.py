#!/usr/bin/env python3
"""Generate Krita-ready layered templates (OpenRaster .ora) for Uldtale art.

    python3 tools/make_art_templates.py        # writes art_templates/*.ora

Open a template in Krita, then File > Save As... > .kra to keep working in
Krita's own format. Layer names and order match docs/ART_PIPELINE.md.
GUIDE layers are drawing aids only - hide them before exporting.
"""
import io, os, zipfile
from PIL import Image, ImageDraw, ImageFont

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "art_templates")
GUIDE = (0, 200, 255, 200)      # cyan
GUIDE2 = (255, 60, 200, 190)    # magenta
HUD = (255, 170, 0, 90)         # orange fill for HUD overlays
HUD_LINE = (255, 140, 0, 220)


def font(size):
    try:
        return ImageFont.load_default(size=size)
    except TypeError:
        return ImageFont.load_default()


def blank(w, h, fill=(0, 0, 0, 0)):
    return Image.new("RGBA", (w, h), fill)


def label(d, xy, text, size=28, fill=GUIDE):
    d.text(xy, text, font=font(size), fill=fill)


# ---------------------------------------------------------------- layer model
# A stack is a list of entries, TOP first (OpenRaster order):
#   ("layer", name, image, {opacity, visible})   or   ("group", name, [entries], {visible})

def L(name, img, opacity=1.0, visible=True):
    return ("layer", name, img, {"opacity": opacity, "visible": visible})


def G(name, children, visible=True):
    return ("group", name, children, {"visible": visible})


def write_ora(path, w, h, stack):
    files = {}
    counter = [0]

    def xml_for(entries, indent):
        out = ""
        for e in entries:
            if e[0] == "group":
                vis = "visible" if e[3]["visible"] else "hidden"
                out += '%s<stack name="%s" visibility="%s">\n' % (indent, e[1], vis)
                out += xml_for(e[2], indent + "  ")
                out += "%s</stack>\n" % indent
            else:
                counter[0] += 1
                src = "data/layer%03d.png" % counter[0]
                buf = io.BytesIO()
                e[2].save(buf, "PNG", optimize=True)
                files[src] = buf.getvalue()
                vis = "visible" if e[3]["visible"] else "hidden"
                out += '%s<layer name="%s" src="%s" x="0" y="0" opacity="%.2f" visibility="%s"/>\n' % (
                    indent, e[1], src, e[3]["opacity"], vis)
        return out

    body = xml_for(stack, "    ")
    stack_xml = ('<?xml version="1.0" encoding="UTF-8"?>\n<image w="%d" h="%d" version="0.0.3">\n'
                 '  <stack>\n%s  </stack>\n</image>\n') % (w, h, body)

    # merged preview: composite visible layers bottom-up
    merged = blank(w, h, (255, 255, 255, 255))

    def comp(entries, parent_visible=True):
        for e in reversed(entries):
            vis = parent_visible and e[3]["visible"]
            if not vis:
                continue
            if e[0] == "group":
                comp(e[2], vis)
            else:
                img = e[2]
                if e[3]["opacity"] < 1.0:
                    a = img.getchannel("A").point(lambda v: int(v * e[3]["opacity"]))
                    img = img.copy()
                    img.putalpha(a)
                merged.alpha_composite(img)

    comp(stack)
    mbuf = io.BytesIO()
    merged.save(mbuf, "PNG", optimize=True)
    thumb = merged.copy()
    thumb.thumbnail((256, 256))
    tbuf = io.BytesIO()
    thumb.save(tbuf, "PNG")

    with zipfile.ZipFile(path, "w") as z:
        z.writestr(zipfile.ZipInfo("mimetype"), "image/openraster", compress_type=zipfile.ZIP_STORED)
        z.writestr("stack.xml", stack_xml, compress_type=zipfile.ZIP_DEFLATED)
        for src, data in files.items():
            z.writestr(src, data, compress_type=zipfile.ZIP_DEFLATED)
        z.writestr("mergedimage.png", mbuf.getvalue(), compress_type=zipfile.ZIP_DEFLATED)
        z.writestr("Thumbnails/thumbnail.png", tbuf.getvalue(), compress_type=zipfile.ZIP_DEFLATED)
    return merged


# ---------------------------------------------------------------- characters

CW, CH = 1024, 2048
HEAD = 256            # head height in px - the same for every pose and frame
GROUND = 1980         # feet line


def frame_guide(heads, head_w_scale=1.0, shoulders=1.0, name="standard"):
    """Proportion guide: head box, centre line, ground, head-height ticks."""
    img = blank(CW, CH)
    d = ImageDraw.Draw(img)
    top = GROUND - heads * HEAD
    cx = CW // 2
    hw = int(HEAD * 0.78 * head_w_scale)
    d.line([(cx, 0), (cx, CH)], fill=GUIDE, width=2)
    d.line([(0, GROUND), (CW, GROUND)], fill=GUIDE, width=4)
    label(d, (20, GROUND + 10), "GROUND - feet here", 26)
    for i in range(int(heads) + 1):
        y = int(GROUND - i * HEAD)
        d.line([(cx - 60, y), (cx + 60, y)], fill=GUIDE, width=2)
        label(d, (cx + 70, y - 14), "%d" % i, 22)
    # head box (the shared anchor for hair, ears, horns, eyes)
    d.ellipse([cx - hw // 2, top, cx + hw // 2, top + HEAD], outline=GUIDE2, width=4)
    eye_y = top + int(HEAD * 0.52)
    d.line([(cx - hw // 2 - 40, eye_y), (cx + hw // 2 + 40, eye_y)], fill=GUIDE2, width=2)
    label(d, (cx + hw // 2 + 50, eye_y - 14), "eye line", 22, GUIDE2)
    label(d, (cx + hw // 2 + 50, top + 10), "HEAD ANCHOR (%s frame)" % name, 24, GUIDE2)
    label(d, (cx + hw // 2 + 50, top + 40), "keep identical in every pose", 22, GUIDE2)
    sh = int(HEAD * 1.9 * shoulders)
    sy = top + int(HEAD * 1.35)
    d.line([(cx - sh // 2, sy), (cx + sh // 2, sy)], fill=GUIDE, width=2)
    label(d, (cx - sh // 2, sy - 32), "shoulders", 22)
    label(d, (20, 20), "%s frame: %.1f heads tall, head %dpx" % (name.upper(), heads, HEAD), 30)
    return img


def character_stack(extra_guides=None, note=""):
    w, h = CW, CH
    guides = [L("standard frame (Hume, Elvarian, most races)", frame_guide(7.5), 0.8),
              L("short frame (Durgar)", frame_guide(5.0, 1.05, 1.15, "short"), 0.8, False),
              L("large frame (Ursari)", frame_guide(8.0, 1.1, 1.35, "large"), 0.8, False)]
    if extra_guides:
        guides = extra_guides + guides
    paper = blank(w, h, (255, 255, 255, 255))
    return [
        G("GUIDES - hide before export", guides),
        L("09 lines (never recoloured)", blank(w, h)),
        G("08 weapon / held item", [L("weapon_lines", blank(w, h)), L("weapon", blank(w, h))]),
        L("07 hair_front - SHARED, draw in hair template", blank(w, h), 0.5),
        L("06 race_front (ears, horns) - SHARED, draw in race template", blank(w, h), 0.5),
        L("05 eyes (greyscale)", blank(w, h)),
        G("04 outfit", [
            L("outfit_detail (gold, gems: never recoloured)", blank(w, h)),
            L("outfit_mask (flat RED main, GREEN secondary, BLUE trim)", blank(w, h), 0.6),
            L("outfit_shade (greyscale, full shading)", blank(w, h)),
        ]),
        L("03 body_skin (greyscale, full shading)", blank(w, h)),
        L("02 race_back (tails, wings) - SHARED", blank(w, h), 0.5),
        L("01 hair_back - SHARED", blank(w, h), 0.5),
        L("00 paper (not exported)", paper),
    ]


def hair_race_stack():
    w, h = CW, CH
    paper = blank(w, h, (255, 255, 255, 255))
    return [
        G("GUIDES - hide before export", [
            L("standard frame head", frame_guide(7.5), 0.8),
            L("short frame head (Durgar)", frame_guide(5.0, 1.05, 1.15, "short"), 0.8, False),
            L("large frame head (Ursari)", frame_guide(8.0, 1.1, 1.35, "large"), 0.8, False),
        ]),
        G("hair style (one file per style + gender)", [
            L("hair_lines", blank(w, h)),
            L("hair_front (greyscale)", blank(w, h)),
            L("hair_back (greyscale)", blank(w, h)),
        ]),
        G("race parts (one file per race)", [
            L("race_lines", blank(w, h)),
            L("ears_front / horns (greyscale)", blank(w, h)),
            L("tail_back / wings (greyscale)", blank(w, h)),
        ], False),
        L("reference body (sketch any pose, not exported)", blank(w, h), 0.35),
        L("00 paper (not exported)", paper),
    ]


def shopkeeper_stack():
    w, h = 2048, 2048
    g = blank(w, h)
    d = ImageDraw.Draw(g)
    counter_y = 1380
    d.line([(0, counter_y), (w, counter_y)], fill=GUIDE, width=4)
    label(d, (24, counter_y + 10), "COUNTER TOP - everything below is hidden by the counter art", 28)
    cx = w // 2
    top = counter_y - int(3.4 * HEAD)
    hw = int(HEAD * 0.78)
    d.ellipse([cx - hw // 2, top, cx + hw // 2, top + HEAD], outline=GUIDE2, width=4)
    label(d, (cx + hw // 2 + 40, top + 10), "HEAD ANCHOR - same head size (256px) as class poses", 26, GUIDE2)
    d.line([(cx, 0), (cx, h)], fill=GUIDE, width=2)
    label(d, (24, 24), "SHOPKEEPER 2048x2048 - Kitsune shop / Durgar smith / Dhampyr enchanter / Elvarian alchemist / Hume or Felis guild", 26)
    paper = blank(w, h, (255, 255, 255, 255))
    return [
        G("GUIDES - hide before export", [L("counter + head anchor", g, 0.8)]),
        L("10 counter / props in front", blank(w, h)),
        L("09 lines", blank(w, h)),
        L("07 hair_front", blank(w, h)),
        L("06 race_front (ears, horns)", blank(w, h)),
        L("05 eyes (greyscale)", blank(w, h)),
        G("04 outfit", [
            L("outfit_detail (never recoloured)", blank(w, h)),
            L("outfit_mask (RED main, GREEN secondary, BLUE trim)", blank(w, h), 0.6),
            L("outfit_shade (greyscale)", blank(w, h)),
        ]),
        L("03 body_skin (greyscale)", blank(w, h)),
        L("02 race_back (tails)", blank(w, h)),
        L("01 hair_back", blank(w, h)),
        L("00 shop background (separate export)", blank(w, h)),
        L("paper (not exported)", paper),
    ], (w, h)


# ---------------------------------------------------------------- exploration

EW, EH = 2400, 1440
HORIZON = 540
VPX = 1200
DEPTH_Y = {"near": 1060, "mid": 800, "far": 660}   # far edge of each tile band
PATH_BOTTOM = (700, 1700)                          # path edges at the bottom


def path_x(y, side):
    """Where the path edge meets row y (straight lines to the vanishing point)."""
    t = (y - HORIZON) / (EH - HORIZON)
    x0 = PATH_BOTTOM[0] if side == "left" else PATH_BOTTOM[1]
    return VPX + (x0 - VPX) * t


def exploration_guides():
    img = blank(EW, EH)
    d = ImageDraw.Draw(img)
    d.line([(0, HORIZON), (EW, HORIZON)], fill=GUIDE2, width=4)
    label(d, (20, HORIZON - 40), "HORIZON (y=%d) - every exploration piece shares it" % HORIZON, 30, GUIDE2)
    d.ellipse([VPX - 12, HORIZON - 12, VPX + 12, HORIZON + 12], outline=GUIDE2, width=4)
    label(d, (VPX + 20, HORIZON + 8), "vanishing point", 26, GUIDE2)
    for side in ("left", "right"):
        d.line([(path_x(EH, side), EH), (VPX, HORIZON)], fill=GUIDE, width=3)
        # outer corridor lines (where side scenery stands)
        x0 = -500 if side == "left" else EW + 500
        d.line([(x0, EH), (VPX, HORIZON)], fill=GUIDE, width=2)
    prev = EH
    for name in ("near", "mid", "far"):
        y = DEPTH_Y[name]
        d.line([(0, y), (EW, y)], fill=GUIDE, width=3)
        label(d, (20, (y + prev) // 2 - 16), "%s tile (y %d-%d)" % (name.upper(), y, prev), 30)
        prev = y
    label(d, (20, 20), "EXPLORATION VIEW 2400x1440 - one file per piece, full canvas, transparent", 30)
    return img


def opening_guides():
    img = blank(EW, EH)
    d = ImageDraw.Draw(img)
    prev = EH
    for name in ("near", "mid", "far"):
        y = DEPTH_Y[name]
        for side in ("left", "right"):
            xa, xb = path_x(prev, side), path_x(y, side)
            outer = 0 if side == "left" else EW
            d.polygon([(xa, prev), (xb, y), (outer, y), (outer, prev)], outline=GUIDE2)
        label(d, (path_x(prev, "left") - 420, prev - 50), "side opening (%s)" % name, 24, GUIDE2)
        prev = y
    return img


def minimap_guide():
    img = blank(EW, EH)
    d = ImageDraw.Draw(img)
    box = (1736, 29, 2357, 648)
    d.rectangle(box, fill=HUD, outline=HUD_LINE, width=4)
    label(d, (box[0] + 20, box[1] + 20), "MINIMAP covers this area", 30, HUD_LINE)
    return img


def exploration_stack():
    w, h = EW, EH
    paper = blank(w, h, (255, 255, 255, 255))
    return [
        G("GUIDES - hide before export", [
            L("perspective + depth bands", exploration_guides(), 0.8),
            L("side openings (for opening-left/right ground pieces)", opening_guides(), 0.8, False),
            L("minimap area (HUD)", minimap_guide(), 1.0, False),
        ]),
        L("props - draw at NEAR size; one file per prop", blank(w, h)),
        G("side scenery LEFT (mirrored in game for the right side)", [
            L("left_near", blank(w, h)),
            L("left_mid", blank(w, h)),
            L("left_far", blank(w, h)),
        ]),
        G("ground (export each shape: straight / opening_left / opening_right / dead_end)", [
            L("ground_near", blank(w, h)),
            L("ground_mid", blank(w, h)),
            L("ground_far", blank(w, h)),
        ]),
        L("backdrop (sky + horizon band: trees, mountains)", blank(w, h)),
        L("paper (not exported)", paper),
    ]


# ---------------------------------------------------------------- backgrounds

def hud_overlay(rects, title):
    img = blank(EW, EH)
    d = ImageDraw.Draw(img)
    for (x0, y0, x1, y1, name) in rects:
        d.rectangle([x0, y0, x1, y1], fill=HUD, outline=HUD_LINE, width=4)
        label(d, (x0 + 14, y0 + 10), name, 26, HUD_LINE)
    label(d, (20, EH - 50), title + " - keep important detail out of the orange areas", 28, HUD_LINE)
    return img


BATTLE_HUD = [   # the 1200x720 battle UI, doubled
    (384, 0, 1920, 248, "dungeon banner + turn order + challenge"),
    (128, 192, 736, 560, "player panel + Link bar"),
    (128, 560, 736, 830, "party rows"),
    (144, 830, 624, 1440, "action buttons"),
    (752, 1060, 1680, 1440, "combat log"),
    (1736, 290, 2336, 1340, "enemy panels"),
]
ENEMY_AREA = (1440, 250, 1820, 660)
TOWN_HUD = [
    (80, 144, 1304, 1176, "town buttons"),
    (1400, 144, 2320, 848, "town news"),
    (1904, 896, 2264, 1272, "character / quit"),
    (0, 0, 2400, 108, "title bar"),
]


def background_stack():
    w, h = EW, EH
    battle = hud_overlay(BATTLE_HUD, "BATTLE HUD")
    d = ImageDraw.Draw(battle)
    d.rectangle(ENEMY_AREA, outline=GUIDE2, width=4)
    label(d, (ENEMY_AREA[0] + 10, ENEMY_AREA[3] + 8), "enemy sprites stand here", 26, GUIDE2)
    paper = blank(w, h, (255, 255, 255, 255))
    return [
        G("GUIDES - hide before export", [
            L("battle HUD overlay", battle, 1.0),
            L("town HUD overlay", hud_overlay(TOWN_HUD, "TOWN HUD"), 1.0, False),
        ]),
        L("foreground (optional, in front of characters)", blank(w, h)),
        L("midground", blank(w, h)),
        L("background", blank(w, h)),
        L("sky", blank(w, h)),
        L("paper (not exported)", paper),
    ]


# ---------------------------------------------------------------- enemies, icons, UI

def creature_stack(size, kind):
    g = blank(size, size)
    d = ImageDraw.Draw(g)
    ground = int(size * 0.93)
    d.line([(0, ground), (size, ground)], fill=GUIDE, width=3)
    d.line([(size // 2, 0), (size // 2, size)], fill=GUIDE, width=2)
    m = int(size * 0.04)
    d.rectangle([m, m, size - m, size - m], outline=GUIDE2, width=2)
    label(d, (m + 6, m + 6), "%s %dx%d - faces LEFT (toward the heroes)" % (kind, size, size), max(14, size // 30), GUIDE2)
    label(d, (m + 6, ground + 4), "ground", max(12, size // 36))
    paper = blank(size, size, (255, 255, 255, 255))
    return [
        G("GUIDES - hide before export", [L("ground + safe margin", g, 0.8)]),
        L("lines", blank(size, size)),
        L("colour", blank(size, size)),
        L("ground shadow (soft, low opacity)", blank(size, size)),
        L("paper (not exported)", paper),
    ]


def icon_stack():
    s = 128
    g = blank(s, s)
    d = ImageDraw.Draw(g)
    d.rectangle([8, 8, s - 9, s - 9], outline=GUIDE2, width=1)
    paper = blank(s, s, (255, 255, 255, 255))
    return [
        G("GUIDES - hide before export", [L("8px safe margin", g, 0.8)]),
        L("lines", blank(s, s)),
        L("icon", blank(s, s)),
        L("paper (not exported)", paper),
    ]


def ui_stack():
    s = 96
    b = 32
    g = blank(s, s)
    d = ImageDraw.Draw(g)
    for v in (b, s - b):
        d.line([(v, 0), (v, s)], fill=GUIDE2, width=1)
        d.line([(0, v), (s, v)], fill=GUIDE2, width=1)
    paper = blank(s, s, (200, 200, 200, 255))
    return [
        G("GUIDES - hide before export", [L("9-slice borders (32px)", g, 0.9)]),
        L("panel / button", blank(s, s)),
        L("paper (not exported)", paper),
    ]


# ---------------------------------------------------------------- main

def main():
    os.makedirs(OUT, exist_ok=True)
    made = []
    def out(name, w, h, stack):
        write_ora(os.path.join(OUT, name), w, h, stack)
        made.append(name)
    out("character_pose_1024x2048.ora", CW, CH, character_stack())
    out("hair_and_race_parts_1024x2048.ora", CW, CH, hair_race_stack())
    st, (sw, sh) = shopkeeper_stack()
    out("shopkeeper_2048x2048.ora", sw, sh, st)
    out("exploration_view_2400x1440.ora", EW, EH, exploration_stack())
    out("background_2400x1440.ora", EW, EH, background_stack())
    out("enemy_512.ora", 512, 512, creature_stack(512, "ENEMY"))
    out("boss_1024.ora", 1024, 1024, creature_stack(1024, "BOSS"))
    out("icon_128.ora", 128, 128, icon_stack())
    out("ui_9slice_96.ora", 96, 96, ui_stack())
    open(os.path.join(OUT, ".gdignore"), "w").close()   # keep Godot from importing these
    print("wrote", ", ".join(made))


if __name__ == "__main__":
    main()
