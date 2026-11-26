# UI / UX plan (draft)

Mockups: `art_templates/ui_mockups/*.ora` (open in Krita), with `.png`
previews. Regenerate with `python3 tools/make_ui_mockups.py`. Each file has
the layers **SKETCH** (empty, for you), **NOTES** (magenta, hideable),
**SAFE AREA** (hidden guides), **WIREFRAME** and **BACKGROUND**.

The wireframes show layout only. The look comes from your sketches and the UI
kit.

---

## 1. Resolution and scaling

**Design at 1920×1080 (16:9) and let Godot scale it.**

- `display/window/size/viewport_width/height = 1920×1080` (today it is
  1200×720).
- `stretch/mode = canvas_items`: UI and text are rendered at the real
  resolution, so they stay sharp at 4K.
- `stretch/aspect = expand`: other aspect ratios show *more* screen instead
  of black bars. On 16:10 (Steam Deck 1280×800) the screen is taller; on
  21:9 it is wider.
- Screens are built from **anchors and containers**
  (HBox/VBox/Grid/Margin), not fixed positions. Panels pin to edges and
  corners; backgrounds bleed past the 16:9 core.
- **Safe area:** keep text and buttons about 60 px in from the sides and
  40 px in from the top and bottom (the inner cyan line in the mockups).
- **UI scale option** (80–150%) in Settings for handhelds and TVs. It changes
  `content_scale_factor`.
- Minimum text size is 18 px at 1080p, so text stays readable on a 7" Deck.
- Art is drawn at 2× where it is cheap (icons 128 px, 9-slices), so it stays
  crisp at 4K.

So one resolution does the job: 1080p is the canvas, and `expand` plus
anchors handles the platforms.

## 2. Screen map

```
Main Menu ─ Character Select ─ Character Creation
                     │
                  NEXUS (hub) ── top bar on every screen: Character [C] · Party [P] · Book [B] · Menu [Esc]
   ┌──────────┬──────────┬──────────┬──────────┬──────────┐
 The Tower  The Gate  Guild Hall  Market    Tavern & Inn   Bank
 (tower     (map of   (desk,      Shop      (people,      (vault:
  dungeon)   Nyxarys,  Ledger,    Smith     chat, invite,  items,
             expedi-   Training,  Alchemist rumours,       gear,
             tions)    trials,    Enchanter bard)          coin)
                       bounties,
                       Retire)
```

| Screen | Replaces / merges |
|---|---|
| **Nexus hub** | Town screen. Districts are illustrated places, each with one live status line and a badge. There is also a news feed. |
| **The Tower** | "Tower" dungeon entry. Floors are shown as a climb up the tower art. |
| **The Gate** | Expedition picker. Uses a map of Nyxarys with pins from `locations.json` and travel days from the map. |
| **Guild Hall** | Guild, Ledger, Training, Commissions board, Retire. |
| **Market** | A street with four shopkeepers (Shop, Blacksmith, Alchemist, Enchanter). |
| **Tavern & Inn** | Tavern. The NPC profile becomes a card. Rest/Inn lives here. |
| **Bank** | Stash. Holds items, gear **and coin**. A possible hook: coin in the vault is safe from defeat fees. |
| **Character** [C] | Status, Equipment, Inventory, Talents as tabs on one screen. |
| **Party** [P] | (Future) Give gear and items to companions. Also holds loot share, auto toggle and bond tier. |
| **The Book** [B] | Journal, Chronicle, Compendium, Bestiary, Combos as bookmarks of one tome. |

## 3. Interaction rules

- **Two clicks to anything** from the hub. Top-bar screens open as overlays,
  so you never travel through town to change gear.
- **Badges** mark something that needs you (talent points, a trial ready, a
  commission done, an NPC who wants to talk). **Toasts** report things that
  happened. They slide in under the top bar and dismiss on their own.
- **Information as shapes:** bars, chips and icons first, sentences second.
  Gear compare shows green/red deltas, including untrained-armour penalties.
- **Shortcuts:** C, P, B, Esc, and 1–6 for districts. Every action can be
  reached by keyboard or controller (focus neighbours set in containers).
- **Consistency:** every district uses the same frame: scene art, its people,
  an action bar, and "← Nexus [Esc]".
- **Tooltips** on everything with a number.

## 4. Art direction (your words)

> Gritty, dark fantasy anime style that blends Tim Burton-esque weirdness
> with the sharp angles of Gachiakuta and the messy line art of Dorohedoro.

Ideas for the UI (yours to keep or throw out):
- Frames that are a little crooked: hand-cut, stitched, nailed. Not clean
  bevels.
- Ink-heavy line work with visible wobble. Shadows done with hatching, not
  gradients.
- A small palette: bone, soot, rust and dried-blood red. One sickly accent
  for magic, and gold for rewards.
- Badges like wax seals or pins. Toasts like torn paper notes.

## 5. UI kit (next)

`10_ui_kit_sheet.ora` lists one of each piece to design:
- buttons (normal, hover, pressed, disabled);
- tabs and text fields;
- panels and cards (9-slice, using `ui_9slice_96.ora`);
- modal dialogs, toasts and tooltips;
- stat bars, chips and badges;
- list rows and item slots (rarity frames);
- icons.

Make test pieces. I'll build them into a Godot **Theme** (`ui/theme.tres`)
so every screen picks them up at once.

## 6. Order of work

1. You sketch over the mockups and the kit sheet.
2. Move to 1920×1080 and the stretch settings; build the Theme from the test
   pieces.
3. The Nexus hub and the top bar, then the Character screen (merging four
   screens).
4. The Gate map, the Bank (from Stash), the Book.
5. Restyle the districts; build the Party screen when party equipment exists.

---

## Built: simplified hub (current theme, 1200×720)

A first pass using the current default theme, before the art and the
1080p move.
- **Nexus hub** (`scenes/TownScene.gd`):
  - Six district cards (The Tower, The Gate, Guild Hall, Market, Tavern &
    Inn, Bank), each with a live status line. Keys 1–6 open them.
  - Districts with several places (Guild Hall, Market, Tavern & Inn) open a
    list in the same panel. "<- Nexus" or Esc returns.
  - Footer: Character [C], with a count when there are points to spend;
    Book [B] (Journal, Chronicle, Compendium, Bestiary, Combos); Menu
    (Character Selection, Save and Quit). Esc on the hub opens the Menu.
  - The news panel is now full height.
- **The Tower** opens its floor picker directly. **The Gate** lists every
  other location. The location `the_dungeon` is now named "The Tower".
- **Character tabs** (`ui/CharacterTabs.gd`):
  - Status, Equipment, Inventory and Talents share a tab row in the header.
  - Tabs swap screens in place (`SceneManager.swap_to`), and Back returns to
    wherever you came from (`SceneManager.leave_screen`).
  - Talents is hidden during an expedition. Tabs show "(n)" when points are
    waiting.
- **Bank**: the Stash screen, renamed. Coin deposits come later.
