# Krita templates

Layered templates for Uldtale art, in OpenRaster (`.ora`) format. Krita opens
them with every layer and group intact; then **File → Save As… → .kra** to keep
working in Krita's own format. Conventions: `docs/ART_PIPELINE.md`.

Regenerate (e.g. after changing a size): `python3 tools/make_art_templates.py`.

| Template | Canvas | For |
|---|---|---|
| `character_pose_1024x2048.ora` | 1024 × 2048 | a class base pose (one per class × gender) |
| `hair_and_race_parts_1024x2048.ora` | 1024 × 2048 | hairstyles and race parts (ears, horns, tails) - shared by every pose |
| `shopkeeper_2048x2048.ora` | 2048 × 2048 | shopkeepers behind a counter |
| `exploration_view_2400x1440.ora` | 2400 × 1440 | Goblin Forest (and later) exploration pieces |
| `background_2400x1440.ora` | 2400 × 1440 | battle / town / menu backgrounds |
| `enemy_512.ora`, `boss_1024.ora` | 512², 1024² | enemies and bosses (drawn whole, facing left) |
| `icon_128.ora` | 128 × 128 | item and status icons |
| `ui_9slice_96.ora` | 96 × 96 | panels and buttons (32 px 9-slice borders) |

## Guides

Every template has a **GUIDES** group (cyan / magenta / orange). Hide it before
exporting. Some guides start hidden - toggle them on as needed:
- **Character / hair:** the standard frame (7.5 heads) is on; the short
  (Durgar, 5 heads) and large (Ursari, 8 heads) frames are hidden. The head
  is always 256 px - keep it on the **head anchor** so hair, ears and eyes fit
  every pose.
- **Exploration:** horizon at y = 540, the vanishing point, path edges and the
  near / mid / far tile bands; hidden extras for side openings and the
  minimap area.
- **Background:** the battle HUD overlay (where panels cover the art, and
  where enemies stand); a hidden town HUD overlay.

## Layers

- Layers marked **SHARED** in the character template are only for preview -
  draw hair and race parts in their own template so they work for every pose.
- **Greyscale** layers (skin, hair, eyes, outfit_shade): paint values with full
  shading - the game colours them. Krita's *Filter → Map → Gradient Map*
  previews a colour.
- **outfit_mask:** flat RED = main cloth, GREEN = secondary, BLUE = trim/metal.
- **lines** and **outfit_detail** are never recoloured.
- **paper** layers are for drawing on; don't export them.

## Exporting

Export each layer (or group) to its own PNG **at full canvas size** -
*File → Export Layers…* in recent Krita versions, or hide all but one and
*File → Export*. Name the files as in `docs/ART_PIPELINE.md`.
