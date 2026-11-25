#!/usr/bin/env python3
"""UI wireframe mockups for Uldtale, as Krita-ready layered OpenRaster (.ora).

    python3 tools/make_ui_mockups.py      # writes art_templates/ui_mockups/*.ora (+ .png previews)

Each file is 1920x1080 (the design resolution, docs/design/UI_UX.md) with layers:
    SKETCH      empty - draw here
    NOTES       magenta annotations (hide when you don't need them)
    SAFE AREA   cyan guides: what 16:10 (Steam Deck) and 21:9 add around the 16:9 core
    WIREFRAME   grey boxes and labels: the layout to react to
    BACKGROUND  dark fill
The wireframe is deliberately plain - the look is yours to sketch over.
"""
import os
from PIL import Image, ImageDraw, ImageFont
from make_art_templates import write_ora, L, blank

W, H = 1920, 1080
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "art_templates", "ui_mockups")
FONT = "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"
FONT_B = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"

LINE = (150, 150, 158, 255)
FILL = (52, 52, 60, 255)
FILL2 = (70, 70, 80, 255)
ART = (42, 42, 48, 255)
TEXT = (210, 210, 215, 255)
DIM = (140, 140, 148, 255)
ACCENT = (230, 200, 90, 255)
BADGE = (220, 70, 70, 255)
NOTE = (255, 60, 200, 255)
GUIDE = (0, 200, 255, 200)


def f(size, bold=False):
    try:
        return ImageFont.truetype(FONT_B if bold else FONT, size)
    except OSError:
        return ImageFont.load_default()


class Canvas:
    def __init__(self):
        self.wire = blank(W, H)
        self.notes = blank(W, H)
        self.w = ImageDraw.Draw(self.wire)
        self.n = ImageDraw.Draw(self.notes)

    # -- wireframe primitives
    def box(self, x, y, w, h, label="", fill=FILL, size=26, bold=False, align="c", outline=LINE, width=2):
        self.w.rectangle([x, y, x + w, y + h], fill=fill, outline=outline, width=width)
        if label:
            self.text_in(x, y, w, h, label, size, bold, align)

    def art(self, x, y, w, h, label="ART"):
        self.w.rectangle([x, y, x + w, y + h], fill=ART, outline=LINE, width=2)
        self.w.line([x, y, x + w, y + h], fill=(70, 70, 78, 255), width=2)
        self.w.line([x + w, y, x, y + h], fill=(70, 70, 78, 255), width=2)
        self.text_in(x, y, w, h, label, 22, False, "c", DIM)

    def text_in(self, x, y, w, h, label, size=26, bold=False, align="c", color=TEXT):
        ft = f(size, bold)
        lines = label.split("\n")
        lh = size + 6
        ty = y + (h - lh * len(lines)) / 2 if align in ("c", "l") else y + 10
        for ln in lines:
            tw = self.w.textlength(ln, font=ft)
            tx = x + (w - tw) / 2 if align == "c" else x + 14
            self.w.text((tx, ty), ln, font=ft, fill=color)
            ty += lh

    def text(self, x, y, s, size=24, color=TEXT, bold=False):
        self.w.text((x, y), s, font=f(size, bold), fill=color)

    def bar(self, x, y, w, h, frac, color):
        self.w.rectangle([x, y, x + w, y + h], fill=(30, 30, 34, 255), outline=LINE)
        self.w.rectangle([x, y, x + int(w * frac), y + h], fill=color)

    def badge(self, x, y, n=""):
        self.w.ellipse([x - 16, y - 16, x + 16, y + 16], fill=BADGE, outline=(255, 255, 255, 255), width=2)
        if n:
            tw = self.w.textlength(str(n), font=f(20, True))
            self.w.text((x - tw / 2, y - 13), str(n), font=f(20, True), fill=(255, 255, 255, 255))

    def chip(self, x, y, label, color=FILL2):
        tw = self.w.textlength(label, font=f(20))
        self.w.rounded_rectangle([x, y, x + tw + 24, y + 34], 14, fill=color, outline=LINE)
        self.w.text((x + 12, y + 5), label, font=f(20), fill=TEXT)
        return x + tw + 34

    # -- notes
    def note(self, x, y, s, size=22, arrow_to=None):
        self.n.text((x, y), s, font=f(size), fill=NOTE)
        if arrow_to:
            self.n.line([x, y + size // 2, arrow_to[0], arrow_to[1]], fill=NOTE, width=3)
            self.n.ellipse([arrow_to[0] - 6, arrow_to[1] - 6, arrow_to[0] + 6, arrow_to[1] + 6], fill=NOTE)


def top_bar(c, title):
    c.box(0, 0, W, 96, fill=(36, 36, 42, 255))
    c.art(16, 8, 80, 80, "")
    c.text(112, 12, "Mira Ashvale", 24, TEXT, True)
    c.text(300, 17, "Lv 14 Kitsune Paladin · C-Rank", 18, DIM)
    c.bar(112, 50, 180, 14, 0.8, (180, 60, 60, 255)); c.bar(300, 50, 180, 14, 0.6, (70, 110, 200, 255)); c.bar(488, 50, 180, 14, 0.7, (200, 160, 60, 255))
    c.text(112, 68, "HP 812/1010   MP 230/380   SP 190/270", 16, DIM)
    size = 36
    while c.w.textlength(title, font=f(size, True)) > 210 and size > 18:
        size -= 2
    c.text(955, 48 - size // 2 - 4, title, size, ACCENT, True)
    x = 1180
    for name, key, b in [("Character", "C", "3"), ("Party", "P", ""), ("Book", "B", "1"), ("Menu", "Esc", "")]:
        c.box(x, 18, 168, 60, "%s  [%s]" % (name, key), FILL2, 22)
        if b:
            c.badge(x + 162, 22, b)
        x += 180
    c.text(700, 14, "Day 214 · Frostmere, Yr 2", 20, DIM)
    c.text(700, 50, "12g 40s 5c", 20, ACCENT)


def safe_area():
    img = blank(W, H)
    d = ImageDraw.Draw(img)
    d.rectangle([0, 0, W - 1, H - 1], outline=GUIDE, width=4)
    d.rectangle([60, 40, W - 60, H - 40], outline=(0, 200, 255, 110), width=2)
    d.text((70, H - 70), "16:9 core 1920x1080 - inner line: keep text and buttons inside (TV/handheld overscan)", font=f(18), fill=GUIDE)
    d.text((70, 44), "16:10 (Steam Deck): +60 px above and below via anchors · 21:9: wider sides - backgrounds bleed, panels anchor", font=f(18), fill=GUIDE)
    return img


def save(name, c, title):
    os.makedirs(OUT, exist_ok=True)
    bg = blank(W, H, (20, 20, 24, 255))
    stack = [L("SKETCH", blank(W, H)), L("NOTES", c.notes), L("SAFE AREA", safe_area(), 1.0, False),
             L("WIREFRAME", c.wire), L("BACKGROUND", bg)]
    merged = write_ora(os.path.join(OUT, name + ".ora"), W, H, stack)
    merged.convert("RGB").save(os.path.join(OUT, name + ".png"))
    print("wrote", name, "-", title)


# =========================================================== screens

def nexus_hub():
    c = Canvas()
    top_bar(c, "NEXUS")
    c.art(0, 96, W, 984, "BACKGROUND: Nexus over the wound of the Shattering (2400x1440 bg template)")
    # districts as illustrated cards, arranged like a place, not a menu
    cards = [
        (760, 130, 400, 560, "THE TOWER", "Floor 23 reached · 3 days rest"),
        (110, 160, 380, 300, "THE GATE", "Expeditions across Nyxarys"),
        (1430, 160, 380, 300, "GUILD HALL", "Trial ready! · 2 bounties"),
        (110, 520, 380, 300, "MARKET", "Shop · Smith · Alchemist · Enchanter"),
        (1430, 520, 380, 300, "TAVERN & INN", "Kara wants to talk"),
        (560, 740, 300, 220, "BANK", "Vault · coin"),
    ]
    for x, y, w, h, name, sub in cards:
        c.art(x, y, w, h - 90, "district art")
        c.box(x, y + h - 90, w, 90, "", (36, 36, 42, 255))
        c.text(x + 18, y + h - 82, name, 30, ACCENT, True)
        c.text(x + 18, y + h - 40, sub, 20, DIM)
    c.badge(1800, 170, "!"); c.badge(1800, 530, "1")
    # news feed + toasts
    c.box(1060, 740, 750, 260, "", (36, 36, 42, 255))
    c.text(1080, 752, "TOWN NEWS", 22, ACCENT, True)
    for i, s in enumerate(["Dao Vale fell in the Troll Caves (floor 9).", "The Thorn Hands formed a company.", "Rumour: a cache past floor 4 of Goblin Forest.", "Crowning in 18 days - you're #4."]):
        c.text(1080, 790 + i * 44, "• " + s, 20, TEXT)
    c.box(1180, 104, 440, 50, "TOAST: Commission complete! +90c", FILL2, 20)
    c.note(560, 990, "Districts are places, not buttons: art + name + one live status line + badge.", 22)
    c.note(560, 1020, "Tower = the Tower dungeon itself. Gate = expeditions to other locations (map).", 22)
    c.note(1180, 480, "Badge: something needs you here", 20, (1786, 528))
    c.note(1630, 112, "Toast: slides in,\nauto-dismisses", 18)
    c.note(120, 110, "Top bar on every screen: you at a glance + Character / Party / Book / Menu", 20)
    save("01_nexus_hub", c, "the hub")


def district_market():
    c = Canvas()
    top_bar(c, "MARKET")
    c.art(0, 96, W, 984, "BACKGROUND: the market street")
    for i, (name, sub) in enumerate([("SHOP", "Kitsune shopkeeper"), ("BLACKSMITH", "Durgar smith"), ("ALCHEMIST", "Elvarian alchemist"), ("ENCHANTER", "Dhampyr enchanter")]):
        x = 110 + i * 440
        c.art(x, 170, 400, 620, "shopkeeper\n(2048x2048 template)")
        c.box(x, 790, 400, 120, "", (36, 36, 42, 255))
        c.text(x + 18, 800, name, 30, ACCENT, True)
        c.text(x + 18, 846, sub + " · commission: 2/4 Wood", 18, DIM)
    c.badge(1690, 180, "✓")
    c.box(40, 980, 220, 70, "← Nexus  [Esc]", FILL2, 22)
    c.note(300, 1000, "Same pattern for every district: a scene with its people. Guild Hall = desk + board; Tavern = tables of adventurers.", 22)
    save("02_district_market", c, "a district")


def gate():
    c = Canvas()
    top_bar(c, "THE GATE")
    c.art(40, 120, 1180, 900, "MAP OF NYXARYS\n(docs/lore/eledoria_map.webp, inked)")
    for (x, y, n) in [(470, 400, "Nexus"), (700, 470, "Goblin Forest"), (520, 240, "Troll Caves"), (420, 650, "Orc Plains"), (700, 700, "Fairy Circles")]:
        c.w.ellipse([x - 14, y - 14, x + 14, y + 14], fill=ACCENT if n != "Nexus" else (255, 255, 255, 255))
        c.text(x + 20, y - 14, n, 20, TEXT, True)
    c.w.line([470, 400, 700, 470], fill=ACCENT, width=4)
    c.box(1250, 120, 630, 900, "", (36, 36, 42, 255))
    c.text(1274, 136, "GOBLIN FOREST", 34, ACCENT, True)
    c.text(1274, 186, "Near Bramblewood · The Wildwood Expanse (Fenrisulfr)", 20, DIM)
    c.art(1274, 226, 582, 260, "location art")
    rows = ["Travel: 1 day each way", "Floors: 1-7 unlocked · deepest 6", "Enemies: goblins (poison, bleed)", "Omen: Blood Moon (+loot, +danger)", "Rumour: cache past floor 4"]
    for i, s in enumerate(rows):
        c.text(1274, 510 + i * 40, "• " + s, 22, TEXT)
    c.text(1274, 720, "PARTY", 22, ACCENT, True)
    for i in range(3):
        c.art(1274 + i * 130, 756, 110, 110, "")
    c.box(1274, 920, 582, 80, "SET OUT  (2 days)", FILL2, 30, True)
    c.note(60, 1030, "Pins come from data/locations.json region/place; travel days from the map. Locked places shown greyed with why.", 22)
    save("03_gate_expeditions", c, "the gate")


def tower():
    c = Canvas()
    top_bar(c, "THE TOWER")
    c.art(560, 110, 800, 950, "THE TOWER rising from the wound\n(tall illustration)")
    for i in range(8):
        y = 900 - i * 105
        cur = i == 3
        c.box(1420, y, 440, 80, "Floor %d%s" % (20 + i, "  ← you are here" if cur else ("  (locked)" if i > 4 else "")), FILL2 if not cur else (90, 80, 40, 255), 22)
    c.box(60, 140, 460, 420, "", (36, 36, 42, 255))
    c.text(80, 156, "FLOOR 23", 34, ACCENT, True)
    for i, s in enumerate(["Waves: 6 · boss: The Hollow King", "Every kind of creature", "Best clear: 2 tries", "World First: unclaimed!"]):
        c.text(80, 210 + i * 40, "• " + s, 22, TEXT)
    c.box(80, 470, 420, 70, "CLIMB", FILL2, 30, True)
    c.note(60, 600, "Floors as a climb up the tower art.\nScroll the floor list; the art scrolls with it.", 22)
    save("04_tower", c, "the tower")


def character_sheet():
    c = Canvas()
    top_bar(c, "CHARACTER")
    for i, t in enumerate(["Status", "Equipment", "Inventory", "Talents"]):
        c.box(40 + i * 230, 116, 220, 60, t + ("  (3)" if t == "Talents" else ""), (90, 80, 40, 255) if t == "Equipment" else FILL2, 24, t == "Equipment")
    c.art(40, 200, 560, 840, "FULL-BODY CHARACTER\n(layered character template,\nyour race/hair/colours)")
    slots = [("Head", 640, 210), ("Chest", 640, 350), ("Hands", 640, 490), ("Legs", 640, 630), ("Feet", 640, 770), ("Main hand", 880, 210), ("Off hand", 880, 350), ("Accessory", 880, 490)]
    for n, x, y in slots:
        c.box(x, y, 220, 120, n, FILL2, 20)
    c.box(1140, 200, 740, 520, "", (36, 36, 42, 255))
    c.text(1160, 214, "PACK  24 / 30", 22, ACCENT, True)
    for r in range(4):
        for k in range(7):
            c.box(1160 + k * 100, 260 + r * 110, 90, 100, "", FILL2)
    c.box(1140, 740, 740, 300, "", (36, 36, 42, 255))
    c.text(1160, 754, "COMPARE: Ironhold Mail (Rare)  vs  equipped", 22, ACCENT, True)
    for i, (s, col) in enumerate([("Armour 38 → 52  (+14)", (120, 210, 120, 255)), ("Dodge 8% → 6%  (-2%)", (220, 110, 90, 255)), ("Untrained: Mail  (-2% acc, +5% SP)", (220, 110, 90, 255)), ("Suffix: of the Bulwark (+5% block)", TEXT)]):
        c.text(1160, 800 + i * 44, s, 22, col)
    c.note(884, 640, "One screen, four tabs:\nno trips through town.\nDrag pack -> slot;\nhover compares.", 20)
    save("05_character_equipment", c, "character sheet")


def party():
    c = Canvas()
    top_bar(c, "PARTY")
    c.box(40, 116, 360, 920, "", (36, 36, 42, 255))
    c.text(60, 130, "YOUR PARTY  2 / 2", 22, ACCENT, True)
    for i, (n, sub) in enumerate([("Kara Ashpelt", "Elvarian Cleric · Trusted"), ("Dao Vale", "Lycan Berserker · Bonded")]):
        c.art(60, 180 + i * 220, 120, 180, "")
        c.text(196, 200 + i * 220, n, 24, TEXT, True)
        c.text(196, 236 + i * 220, sub, 18, DIM)
        c.bar(196, 270 + i * 220, 180, 12, 0.7, (180, 60, 60, 255))
    c.art(430, 116, 480, 920, "KARA - full body")
    for i, n in enumerate(["Head", "Chest", "Hands", "Legs", "Feet", "Main", "Off"]):
        c.box(930, 130 + i * 128, 200, 110, n, FILL2, 20)
    c.box(1160, 116, 720, 440, "", (36, 36, 42, 255))
    c.text(1180, 130, "KARA'S PACK", 22, ACCENT, True)
    for r in range(3):
        for k in range(6):
            c.box(1180 + k * 112, 176 + r * 120, 100, 110, "", FILL2)
    c.box(1160, 580, 720, 456, "", (36, 36, 42, 255))
    c.text(1180, 594, "YOUR PACK  (drag to give)", 22, ACCENT, True)
    for r in range(3):
        for k in range(6):
            c.box(1180 + k * 112, 640 + r * 120, 100, 110, "", FILL2)
    c.note(430, 1040, "Give gear and items to companions; they wear their own gear. Loot share, Auto toggle and bond tier live here too.", 22)
    save("06_party", c, "party")


def bank():
    c = Canvas()
    top_bar(c, "BANK OF NEXUS")
    c.art(0, 96, W, 220, "BANK INTERIOR banner · banker portrait (shopkeeper template)")
    for side, x in [("YOU CARRY", 40), ("THE VAULT", 1000)]:
        c.box(x, 340, 880, 700, "", (36, 36, 42, 255))
        c.text(x + 20, 354, side, 26, ACCENT, True)
        for i, t in enumerate(["All", "Gear", "Consumables", "Materials"]):
            c.box(x + 20 + i * 170, 400, 160, 50, t, FILL2, 20)
        for r in range(3):
            for k in range(7):
                c.box(x + 20 + k * 120, 470 + r * 120, 110, 110, "", FILL2)
        c.box(x + 20, 850, 840, 70, "Coin: 12g 40s 5c" if x == 40 else "Coin: 85g 10s", FILL2, 24)
    c.box(900, 520, 100, 80, "»", FILL2, 40, True)
    c.box(900, 620, 100, 80, "«", FILL2, 40, True)
    c.box(1020, 940, 400, 80, "Deposit / Withdraw coin…", FILL2, 22)
    c.note(40, 1050, "Stash becomes the Bank: items, gear AND coin. Coin in the vault is safe from defeat fees (design hook).", 22)
    save("07_bank", c, "bank")


def book():
    c = Canvas()
    top_bar(c, "THE BOOK")
    c.art(160, 120, 1600, 920, "AN OPEN TOME (two pages)")
    for i, t in enumerate(["Journal", "Chronicle", "Compendium", "Bestiary", "Combos"]):
        c.box(1760, 160 + i * 150, 140, 130, t, (90, 80, 40, 255) if i == 0 else FILL2, 20)
    c.box(220, 180, 700, 800, "LEFT PAGE: list / index", FILL, 24)
    c.box(1000, 180, 700, 800, "RIGHT PAGE: the entry", FILL, 24)
    c.badge(1895, 165, "1")
    c.note(220, 1040, "Journal, Chronicle, Compendium, Bestiary and Combos become tabs (bookmarks) of one book [B].", 22)
    save("08_book", c, "book")


def tavern_npc():
    c = Canvas()
    top_bar(c, "TAVERN & INN")
    c.box(40, 116, 520, 920, "", (36, 36, 42, 255))
    for i in range(9):
        c.art(56, 130 + i * 100, 80, 84, "")
        c.text(150, 140 + i * 100, ["Kara Ashpelt", "Dao Vale", "Mira Quick", "Hilin Deepforge", "Joren Cole", "Urn Stonehide", "Peren Hollow", "Zessa Duskeye", "Garric Redfern"][i], 22, TEXT, True)
        c.text(150, 172 + i * 100, "C-Rank Cleric · in town", 18, DIM)
    c.badge(540, 150, "!")
    c.art(590, 116, 520, 760, "NPC PORTRAIT\n(character compositor later)")
    c.box(1140, 116, 740, 760, "", (36, 36, 42, 255))
    c.text(1160, 130, "KARA ASHPELT  the Unbroken", 30, ACCENT, True)
    c.text(1160, 176, "Elvarian Cleric · C-Rank · from Eldergrove", 20, DIM)
    c.text(1160, 220, "Rapport", 20, TEXT); c.bar(1300, 224, 400, 18, 0.62, (120, 200, 120, 255))
    c.text(1160, 260, "Mood: warm", 20, TEXT)
    x = 1160
    for t in ["Kind", "Loyal", "Tsundere: Slip"]:
        x = c.chip(x, 300, t)
    c.text(1160, 360, "BONDS", 20, ACCENT, True)
    x = 1160
    for t in ["♥ Dao (partner)", "⚔ Joren (feud)"]:
        x = c.chip(x, 396, t)
    c.text(1160, 460, "REMEMBERS", 20, ACCENT, True)
    c.text(1160, 496, "• You saved her on floor 9 (day 112)", 20, TEXT)
    c.text(1160, 530, "• You fought side by side (x4)", 20, TEXT)
    c.box(590, 900, 1290, 130, "", (36, 36, 42, 255))
    for i, a in enumerate(["Chat", "Buy a drink (1s 60c)", "Give a gift", "Invite to party", "Rumours", "The bard"]):
        c.box(610 + i * 210, 930, 196, 70, a, FILL2, 20)
    c.note(1160, 620, "Profile as a card: bars, chips and icons instead of paragraphs.\nPortrait slot ready for the compositor.", 22)
    save("09_tavern_npc", c, "tavern")


def kit_sheet():
    c = Canvas()
    c.box(0, 0, W, 90, "UI KIT TEST SHEET - one of each piece to design", (36, 36, 42, 255), 30, True)
    items = [
        (60, 130, 300, 80, "Button"), (380, 130, 300, 80, "Button: hover"), (700, 130, 300, 80, "Button: pressed"), (1020, 130, 300, 80, "Button: disabled"),
        (60, 250, 200, 60, "Tab"), (270, 250, 200, 60, "Tab: active"), (1020, 250, 300, 60, "Text field"),
        (60, 360, 600, 340, "Panel / card (9-slice)"), (700, 360, 600, 340, "Modal dialog\n(title, body, 2 buttons)"),
        (1360, 130, 500, 120, "Toast"), (1360, 280, 500, 420, "Tooltip (gear compare)"),
        (60, 740, 600, 60, "Stat bar: HP / MP / SP / Link / Break"), (700, 740, 300, 60, "Chip / tag"), (1020, 740, 120, 120, "Badge"),
        (60, 840, 600, 200, "List row (portrait + name + sub)"), (700, 840, 300, 200, "Item slot\n(empty / rarity frames)"), (1180, 740, 680, 300, "Icons: elements, statuses,\nstats, rarities (128 px)"),
    ]
    for x, y, w, h, n in items:
        c.box(x, y, w, h, n, FILL2, 22)
    c.badge(1080, 800, "3")
    c.note(60, 1050, "Sizes are at 1920x1080. Export pieces at 2x for crispness; 9-slice panels per ui_9slice_96.ora.", 22)
    save("10_ui_kit_sheet", c, "kit sheet")


if __name__ == "__main__":
    for fn in [nexus_hub, district_market, gate, tower, character_sheet, party, bank, book, tavern_npc, kit_sheet]:
        fn()
