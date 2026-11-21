"""Per-machine settings in DevTools/content_manager_config.local.json (git-ignored).

The project root defaults to the folder above DevTools/, so the tool works from
any checkout without setup. The old committed content_manager_config.json is
read once for its dark-mode setting and otherwise ignored.
"""
from __future__ import annotations

import json
import os

DEVTOOLS_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DEFAULT_ROOT = os.path.dirname(DEVTOOLS_DIR)
LOCAL_FILE = os.path.join(DEVTOOLS_DIR, "content_manager_config.local.json")
LEGACY_FILE = os.path.join(DEVTOOLS_DIR, "content_manager_config.json")

DEFAULTS = {
    "root_directory": "",      # "" = DEFAULT_ROOT
    "dark_mode": True,
    "godot_path": "",          # "" = auto-detect (see cm/godot.py)
    "imported_once": False,    # headless --editor --quit import has been done
    "sim": {"classes": [], "location": "the_dungeon", "set_up": True, "potions": 0, "runs": 150},
}


def is_project_root(path: str) -> bool:
    return bool(path) and os.path.isfile(os.path.join(path, "project.godot")) and os.path.isdir(os.path.join(path, "data"))


class Config:
    def __init__(self, path: str = LOCAL_FILE):
        self.path = path
        self.data = json.loads(json.dumps(DEFAULTS))
        loaded = self._read(path)
        if loaded is None:
            legacy = self._read(LEGACY_FILE) or {}
            if "dark_mode" in legacy:
                self.data["dark_mode"] = bool(legacy["dark_mode"])
        else:
            for k, v in loaded.items():
                if isinstance(v, dict) and isinstance(self.data.get(k), dict):
                    self.data[k].update(v)
                else:
                    self.data[k] = v

    @staticmethod
    def _read(path: str):
        try:
            with open(path, "r", encoding="utf-8") as f:
                data = json.load(f)
            return data if isinstance(data, dict) else None
        except (OSError, ValueError):
            return None

    def __getitem__(self, key):
        return self.data[key]

    def __setitem__(self, key, value):
        self.data[key] = value

    def get(self, key, default=None):
        return self.data.get(key, default)

    @property
    def root(self) -> str:
        r = self.data.get("root_directory") or ""
        return r if is_project_root(r) else DEFAULT_ROOT

    def save(self) -> None:
        try:
            with open(self.path, "w", encoding="utf-8") as f:
                json.dump(self.data, f, indent=2)
        except OSError as e:
            print("content manager: could not save config:", e)
