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

## Adding or changing fields
Each data file has a schema in `DevTools/schemas/<name>.json`; the format is documented at
the top of `DevTools/cm/schema.py`. A new data file only needs a new schema file. A new
GDScript enum used for dropdowns is registered in `GD_ENUMS` in `DevTools/cm/enums.py`.

## Tests
```bash
python -m unittest discover -s DevTools/tests -v
```
