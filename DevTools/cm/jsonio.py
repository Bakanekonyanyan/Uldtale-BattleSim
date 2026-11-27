"""JSON load/save that keeps diffs small.

- Key order is preserved (Python dicts are ordered).
- The file's indentation unit (tab or N spaces) is detected and reused.
- Lists of plain values stay on one line: ["Paladin", "Cleric"].
- Backups go to DevTools/backups/ (git-ignored), never next to the data files,
  so Godot and git don't pick them up.
"""
from __future__ import annotations

import datetime
import json
import os
import re
import shutil

BACKUP_DIR = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "backups")
MAX_BACKUPS_PER_FILE = 20


def load(path: str):
    with open(path, "r", encoding="utf-8") as f:
        return json.load(f)


def detect_indent(text: str) -> str:
    """Indentation unit of a JSON file: '\\t' or some number of spaces."""
    for line in text.splitlines()[1:]:
        m = re.match(r"^([ \t]+)\S", line)
        if m:
            ws = m.group(1)
            return "\t" if ws.startswith("\t") else " " * len(ws)
    return "\t"


def _is_scalar(v) -> bool:
    return v is None or isinstance(v, (str, int, float, bool))


def _scalar(v) -> str:
    return json.dumps(v, ensure_ascii=False)


def dumps(obj, indent: str = "\t", level: int = 0) -> str:
    pad = indent * (level + 1)
    end = indent * level
    if isinstance(obj, dict):
        if not obj:
            return "{}"
        items = [f"{pad}{_scalar(str(k))}: {dumps(v, indent, level + 1)}" for k, v in obj.items()]
        return "{\n" + ",\n".join(items) + "\n" + end + "}"
    if isinstance(obj, list):
        if not obj:
            return "[]"
        if all(_is_scalar(v) for v in obj):
            return "[" + ", ".join(_scalar(v) for v in obj) + "]"
        items = [pad + dumps(v, indent, level + 1) for v in obj]
        return "[\n" + ",\n".join(items) + "\n" + end + "]"
    return _scalar(obj)


def save(path: str, data, indent: str | None = None, backup: bool = True) -> None:
    """Write `data` to `path` (atomic replace), backing up the old file first."""
    if indent is None:
        indent = "\t"
        if os.path.exists(path):
            with open(path, "r", encoding="utf-8") as f:
                indent = detect_indent(f.read())
    text = None
    if os.path.exists(path):
        from .splice import splice   # minimal-diff patch of the existing text
        with open(path, "r", encoding="utf-8") as f:
            text = splice(f.read(), data, indent)
        if backup:
            backup_file(path)
    if text is None:
        text = dumps(data, indent) + "\n"
    tmp = path + ".tmp-cm"
    with open(tmp, "w", encoding="utf-8", newline="\n") as f:
        f.write(text)
    os.replace(tmp, path)


def backup_file(path: str) -> str | None:
    os.makedirs(BACKUP_DIR, exist_ok=True)
    base = os.path.basename(path)
    stamp = datetime.datetime.now().strftime("%Y%m%d-%H%M%S")
    dest = os.path.join(BACKUP_DIR, f"{base}.{stamp}.bak")
    try:
        shutil.copy2(path, dest)
    except OSError:
        return None
    # keep only the newest MAX_BACKUPS_PER_FILE for this file
    old = sorted(f for f in os.listdir(BACKUP_DIR) if f.startswith(base + ".") and f.endswith(".bak"))
    for f in old[:-MAX_BACKUPS_PER_FILE]:
        try:
            os.remove(os.path.join(BACKUP_DIR, f))
        except OSError:
            pass
    return dest
