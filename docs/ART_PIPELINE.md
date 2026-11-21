# Art pipeline

Style: hand-drawn illustration (Krita). The pixel-art enemies in the project
are placeholders.

## Focus order

1. Rough sketches for everything.
2. **Goblin Forest** first: exploration set pieces, goblin enemies, its boss.
3. Characters (classes, shopkeepers) once the layer conventions below are settled.

## Sizes

| Asset | Canvas | Notes |
|---|---|---|
| Full-screen backgrounds (town, battle, menus) | 2400 x 1440 | the game renders at 1200 x 720 (5:3) |
| Exploration layers (backdrop, ground per depth, side scenery per depth) | 2400 x 1440 each, transparent | same horizon and vanishing point on every piece; side scenery drawn for one side and mirrored |
| Exploration props (chest, skull, campfire, stairs, NPC) | drawn at the near size (~256 px tall) | scaled down for farther depths |
| Enemies | ~512 x 512 (regular), ~1024 x 1024 (bosses) | drawn whole - no layering needed |
| Characters (classes, shopkeepers, NPCs) | **1024 x 2048** per layer | shopkeepers behind a counter may use 2048 x 2048 |
| Item / status icons | 128 x 128 | |
| UI panels and buttons | 9-slice, ~96 x 96 with 32 px borders | |

Export each layer group from Krita as its own PNG **keeping the full canvas**,
so layers line up without manual placement.

## Characters: the layered ("paper doll") system

Goal: player characters, shopkeepers and **every generated NPC adventurer**
get an illustration built from shared parts - so a new world's Guild is full
of unique-looking people, feeding the living-world feel.

### Layer stack (back to front)

1. Back hair
2. Behind-body race parts (tails, wings)
3. **Body** - base pose per class / shopkeeper, per gender (skin)
4. Outfit or armor
5. Face (eyes)
6. Front race parts (ears, horns, scales, fangs)
7. Front hair
8. Weapon / held items
9. Line art for each part, on top, never recoloured

**Rule:** the head sits at the same position, size and angle in every pose.
Then hairstyles, ears, horns and eyes are drawn once and fit every class and
shopkeeper; only bodies and outfits are drawn per pose.

### Colour

- Recolourable parts (skin, hair, eyes, cloth) are painted in **greyscale with
  full shading**; the game applies a colour ramp (gradient map). Krita's
  Gradient Map filter previews this while drawing.
- Outfits with several colourable parts: one greyscale shading layer plus a
  **mask** in flat colours - red = main cloth, green = secondary
  (cloth/leather), blue = trim/metal. Parts that never change colour (gold,
  gems) go on an uncoloured detail layer.
- Palettes (skin tones, hair, eyes, cloth) live in a data file; more can be
  added without redrawing.

### What to draw

| Asset | Count |
|---|---|
| Class bodies + outfits | 12 classes x 2 genders = 24 (shade + mask + line art each) |
| Shopkeepers | 5 fixed designs (below) |
| Race parts | ~10 races x 1-3 parts (Hume needs none) |
| Hairstyles | 3-4 per gender, front + back |
| Eyes | 1-2 shapes |

**Body frames:** start with the standard frame; add a short frame (Durgar)
and a large frame (Ursari) later rather than drawing per race.

### Shopkeepers

| Role | Race |
|---|---|
| Shop | Kitsune (fox demihuman) |
| Blacksmith | Durgar (dwarf) |
| Enchanter | Dhampyr (vampire) |
| Alchemist | Elvarian (elf) |
| Guild staff | Hume (human) or Felis (cat demihuman) |

### File naming

```
assets/characters/poses/<class or shopkeeper>/<gender>/body.png | outfit_shade.png | outfit_mask.png | lines.png
assets/characters/races/<race>/ears_front.png | tail_back.png | ...
assets/characters/hair/<style>/<gender>/front.png | back.png
assets/characters/eyes/<shape>.png
```

## Later: the character compositor (not built yet)

A portrait component that stacks the layers, applies colour ramps and masks,
and reads an appearance record (gender, body frame, hairstyle, skin / hair /
eye / cloth colours). NPC adventurers would get a random appearance when
they're generated (race and class they already have), so every world's Guild
looks different. Placeholder shapes until the real PNGs land in the folders
above.
