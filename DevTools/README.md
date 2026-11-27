# Uldtale content manager

A desktop editor for the game's data files (`data/**/*.json`): forms with dropdowns
instead of raw JSON, plus (Phase 2/3) validation and buttons that run the Godot tests.

```bash
python DevTools/content_manager.py
```

Needs Python 3.9+ with Tkinter (the python.org Windows installer includes it). It opens
the project it lives in; **Change...** points it at another checkout.

## Using it
- One tab per data file. Pick an entry on the left, edit on the right; edits apply
  immediately in memory and the tab gets a `*`.
- **Save all** (Ctrl+S) writes only the files you changed, and only the lines you
  changed (hand formatting is kept). The previous version goes to `DevTools/backups/`.
- **New** asks for the group (e.g. armor type and slot), a name and an id; the entry
  starts from the schema defaults. **Duplicate** starts from the selected entry.
- Dropdown values come from the game itself: GDScript enums (skill types, status
  effects, damage types...) and ids from the other files (skills, materials, classes...).
  A value that isn't known is kept and flagged, never silently dropped.
- Optional fields have a checkbox; unticking removes the key from the entry.
- Fields the schema doesn't know about are shown under "Other fields" and kept as-is.
- **Rename** changes only the id; other files that refer to it are not updated
  (Validate lists them).

## Validate
**Validate** checks every file at once and lists problems at the bottom; double-click
one to jump to the entry and field. It also runs automatically after each save.
- **Errors**: the game will misbehave. Unknown ids (a recipe ingredient that isn't a
  material, a class skill that doesn't exist), wrong types, out-of-range numbers,
  duplicate item ids, armor filed under the wrong slot, Blacksmith tables missing a
  rarity, and so on.
- **Warnings**: probably a mistake (missing keys the game defaults, a weapon with no
  damage type).
- **Notes** (hidden unless "Show notes" is ticked): content nothing uses yet.

`tests/validate_content.tscn` does the same from inside Godot: it builds every item,
skill, class, enemy group, recipe and bounty board through the real game code.
Run it from the Tests buttons, or `godot --headless res://tests/validate_content.tscn`.

## Running the game's tests
The toolbar buttons run headless Godot in the background. Output streams into the
**Godot output** tab and **Stop** cancels. Unsaved edits are saved first, so the tests
always see what's on screen.

| Button | Runs | Shows |
|---|---|---|
| Validate in Godot | `tests/validate_content.tscn` | errors added to Problems (marked "godot") |
| Smoke test | `tests/battle_smoke_test.tscn` | "N passed, M failed" and the failing checks |
| Balance sim... | `tests/balance_sim.tscn -- tool ...` | per-class floor clear rates in the **Balance sim** tab |

- **Finding Godot:** the first run looks for Godot 4 automatically: the `GODOT`
  environment variable, PATH, Program Files / AppData / Downloads / Desktop, Steam,
  Scoop (Windows); /Applications (macOS). If it can't find it, it asks once and
  remembers. **Godot...** changes it. On Windows pick the `*_console.exe` build if
  you have it.
- **Fresh checkout:** on a fresh checkout it first runs a one-time import
  (`--editor --quit`).
- **Balance sim options:** classes, location, play style (set-up, damage-only, or
  the best of both), potions carried, runs per class and floor. Each run is saved in
  `DevTools/sim_history/`, which stays on this computer and is git-ignored.
- **Comparing sim runs:** after a run, the tab selects it next to the previous run
  with the same options. Select any two runs to compare them. Changes smaller than
  the noise band are grey. The band is about 141/sqrt(runs) points: ±12 at 150 runs,
  ±6 at 500. Raise **Runs per class** to see smaller effects.
- **From the command line**, `tests/balance_sim.tscn -- tool` also takes
  `--archetype=Brute` (every regular enemy uses that archetype) and `--deaths=1`
  (prints `SIM DEATHS|class|style|{wave: count}`, where runs died), which help when
  tuning the **Enemy Archetypes** tab.

## Adding or changing fields
Each data file has a schema in `DevTools/schemas/<name>.json`; the format is documented at
the top of `DevTools/cm/schema.py`. A new data file only needs a new schema file. A new
GDScript enum used for dropdowns is registered in `GD_ENUMS` in `DevTools/cm/enums.py`.

## Tests
```bash
python -m unittest discover -s DevTools/tests -v
```
