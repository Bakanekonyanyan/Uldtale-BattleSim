# Content Tool Roadmap

The content tool (`DevTools/content_manager.py`) is the one place to add, edit,
check and test game content without opening Godot. This doc says where it is
today, where it is going, and in what order.

Decisions already made:
- The tool stays a **separate Python app** (Tkinter, no install beyond Python).
  It drives Godot headless for anything that needs the real game code.
- It must edit **everything data-driven**, including combo chains when they exist.
- Enemies stay on the race × class system for now. A hybrid `enemies.json`
  (hand-authored monsters such as the goblin boss, alongside generated ones)
  comes later, and the tool gets a tab for it then.
- Rule for all new systems: **whatever a player can do, an enemy can do**. The
  tool edits one shared format (skills, combos, statuses), not separate
  player and enemy copies.

---

## 1. Where it is today

About 790 lines, one generic editor for 14 JSON files:

| Tab | File |
|---|---|
| Classes, Races, Skills, Rarities, Status Effects | `data/*.json` |
| Armors, Weapons, Consumables, Materials | `data/items/*.json` |
| Recipes, Locations, Blacksmith, Bounties | `data/*.json` |
| Material Drops | `data/loot/material_tables.json` |

**What works:** tree view of any JSON, edit a leaf (type is guessed from the
old value), new / duplicate / delete, search, backup before save, dark mode.

**What's missing:**
- **No schema.** Every field is a free-text box. Nothing stops a typo in
  `"element": "Fier"` or a skill id that doesn't exist.
- **No cross-file checks.** A recipe can point at a material that was
  deleted; a bounty can name an enemy race no location spawns.
- **No link to the game.** You can't tell whether an edit breaks loading or
  balance without opening Godot.
- **Hard-coded root path.** `content_manager_config.json` is committed with
  a Windows path (`D:/Uldtale Battlsim/...`). It should be per-machine and
  git-ignored.
- **Clutter.** Stray `data/skills.json1333019251.tmp` and `data/oldskills.json`
  sit in `data/`.

---

## 2. Phases

Each phase is usable on its own. Order is by what saves the most time
soonest.

### Phase 1: Schemas and real forms

The tool stops being a JSON tree editor and becomes a form editor.

- **Schema per tab** in `DevTools/schemas/<tab>.json`: field name, type, default,
  help text, and allowed values. Small hand-written JSON, not a library.
- **Field widgets by type:**
  - enum → dropdown (element, rarity, slot, item type, stat, damage type)
  - reference → searchable dropdown of ids from another file (skill ids,
    material ids, status effect ids, location ids, enemy races)
  - number → spinbox with min/max
  - bool → checkbox
  - list of references → add/remove list
  - text → textbox; long text → multi-line
- **Enum sources** read from the data, not hard-coded:
  - elements from `ElementalDamage` (mirrored in a schema enum)
  - rarities from `rarities.json`
  - statuses from `status_effects.json`
- **Unknown fields are kept** and shown in an "Other fields" tree, so nothing
  the schema doesn't know about is lost on save.
- **New from template:** "New" fills every field from the schema defaults,
  or copies a chosen existing entry ("New like…").
- **Per-machine config:** `content_manager_config.json` moves to
  `content_manager_config.local.json`, git-ignored. The committed file only
  holds defaults. Add the Godot binary path here (needed in Phase 3).

Done when: every current tab edits through forms, and saving an untouched
file produces no diff.

### Phase 2: Validation

One "Validate" button, a results panel, click a problem to jump to it.

**Python-side checks** (instant, no Godot):
- References resolve, for example:
  - recipe ingredients and outputs exist
  - material drop ids exist
  - bounty targets exist in a location
  - class skills exist
  - skill status effects exist
- Ids are unique across item files (the game looks items up by id).
- Numbers are in range: chances 0–1, no negative costs, levels ≥ 1.
- Required fields are present.
- Blacksmith tables cover every rarity; the success table covers +1 to the
  highest max level.
- Warnings, not errors, for content nothing uses: orphan materials,
  unreferenced skills.

**Godot-side check** (button: *Validate in Godot*):
- Add `tests/validate_content.tscn` to the repo. It loads every data file
  through the real managers (ItemManager, AlchemyManager, BlacksmithManager,
  GuildManager, LocationManager), builds one of every item and enemy
  combination, and prints `VALIDATE: OK` or a list of errors.
- The tool runs:
  ```
  <godot> --headless --path <project> res://tests/validate_content.tscn
  ```
  and parses the output.

Done when: deleting a material that a recipe uses shows a clickable error.

### Phase 3: Run the game's tests from the tool

A **Tests** panel with three buttons. Each runs headless Godot in a
background thread, streams the output live, and shows a pass/fail summary.

| Button | Command | Shows |
|---|---|---|
| Validate | `res://tests/validate_content.tscn` | errors list |
| Smoke test | `res://tests/battle_smoke_test.tscn` | `SMOKE RESULT: N passed, M failed`, failing lines |
| Balance sim | `res://tests/balance_sim.tscn -- <label>` | the `balance_<label>.txt` report |

Details:
- The balance sim gets options in the UI: which classes, location, and
  whether to use set-up skills. They are passed as user args. Results are
  saved with a timestamp so two runs can be **compared side by side**, for
  example win rate per class before and after a skill change.
- First run does `--headless --editor --quit` once to import the project
  (needed on a fresh checkout).
- "Save all, then run" is the default, so tests always see the current edits.

Done when: you can change a skill's power, click Balance sim, and see the win
rate change without opening Godot.

### Phase 4: Previews and quality-of-life

- **Art previews** with Pillow: show the enemy sprite next to a race/class
  entry, and an item's icon. Enemy art is looked up by name, so the preview
  also flags missing art.
- **Readable summaries** next to each form, the same text the game shows.
  For example, a skill shows "Deals 120% ATK fire damage, 30% Burn for 3 turns".
- **Diff before save:** a small window listing what changed in each file.
- **Undo / redo** inside a session.
- **Bulk edit:** select several entries and set one field, such as the
  rarity or price of ten weapons.
- **Split the code:** `content_manager.py` becomes a small package
  (`app.py`, `schemas.py`, `forms.py`, `validate.py`, `godot_runner.py`,
  `tabs/`), so new tabs are a schema plus a few lines.

### Phase 5: New systems get tabs as they land

Each new game system ships with its schema and tab in the same PR. Planned:

| System | Data file | Tool support |
|---|---|---|
| Damage types (slash / pierce / blunt) and weaknesses / resistances | fields on weapons, skills, races, classes | dropdowns; a resistance grid view per race |
| Combos, phase 1: set-up / payoff | `data/combos.json` | pick a set-up status and a payoff skill, then set the bonus |
| Combos, phase 2: sequence chains | `data/combos.json` | ordered chain editor (add / reorder steps), with a check that every step is a real skill |
| Hybrid enemies | `data/enemies.json` | stats, skills, art, drops, and which locations spawn it; the goblin boss is the first entry |
| Adventurer ranks (F–S) | `data/guild_ranks.json` | rank thresholds, bounty pools per rank |
| Talent trees | `data/talents/<class>.json` | node list with prerequisites; a simple graph view comes later |
| Exploration / NPCs | `data/npcs.json`, location events | later |

Combos, talents and statuses use **one format for heroes and enemies**,
because of the players = enemies rule. The tool has no "enemy-only" fields.

---

## 3. Where this fits in the overall roadmap

1. **Content tool**, Phases 1–3 (this doc)
2. **Battle HUD redesign** (the mockups; punk style is shelved)
3. **Damage types and weaknesses**
4. **Combos**: set-up / payoff, then sequence chains
5. **Adventurer ranks** (Guild F–S)
6. **Talent trees**
7. **Exploration and NPCs** (relationships, alignment)

Content tool Phases 4–5 run alongside items 2–7.

## 4. Open questions

- **Godot path:** ask on first run (current plan), or look in the usual
  install locations first?
- **Balance comparisons:** keep a history file of past sim runs in the repo,
  or only locally?
- **Talent tree editor:** is a plain list with prerequisites enough, or is a
  drag-and-drop graph worth the extra work?
