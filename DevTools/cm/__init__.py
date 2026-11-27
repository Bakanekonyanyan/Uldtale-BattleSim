"""Uldtale content manager: schema-driven editor for the game's data/*.json files.

Modules
  jsonio    load/save JSON keeping key order and the file's indentation style
  config    per-machine settings (git-ignored), Godot path, project root
  enums     reads enum declarations straight from the GDScript sources
  schema    loads DevTools/schemas/*.json (one per data file)
  project   the loaded data, reference lists for dropdowns, dirty tracking
  validate  cross-file checks (Phase 2)
  godot     runs headless Godot: validate, smoke test, balance sim (Phase 3)
  app       the Tkinter UI
"""
