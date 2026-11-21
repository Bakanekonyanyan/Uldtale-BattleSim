"""Enum values read straight from the GDScript sources, so dropdowns can't drift
from the game. Referenced in schemas as "gd:<Name>" (see GD_ENUMS)."""
from __future__ import annotations

import os
import re

# schema name -> (script path relative to the project root, enum name)
GD_ENUMS = {
    "SkillType": ("scenes/mechanics/Skill.gd", "SkillType"),
    "SkillTarget": ("scenes/mechanics/Skill.gd", "TargetType"),
    "AttributeTarget": ("scenes/mechanics/Skill.gd", "AttributeTarget"),
    "StatusEffect": ("scenes/mechanics/Skill.gd", "StatusEffect"),
    "AbilityType": ("scenes/mechanics/Skill.gd", "AbilityType"),
    "DrainTarget": ("scenes/mechanics/Skill.gd", "DrainTarget"),
    "SkillElement": ("scenes/mechanics/Skill.gd", "ElementType"),
    "Element": ("scripts/resources/ElementalDamage.gd", "Element"),
    "ItemType": ("scripts/resources/Item.gd", "ItemType"),
    "ConsumableType": ("scripts/resources/Item.gd", "ConsumableType"),
    "ItemTarget": ("scripts/resources/Item.gd", "TargetType"),
    "DamageType": ("scripts/resources/DamageTypes.gd", "Type"),
}

_ENUM_RE = re.compile(r"^\s*enum\s+(\w+)\s*\{([^}]*)\}", re.MULTILINE | re.DOTALL)


def parse_gd_enums(text: str) -> dict[str, list[str]]:
    """All `enum Name { A, B = 3, C }` declarations in a GDScript file."""
    out: dict[str, list[str]] = {}
    for m in _ENUM_RE.finditer(text):
        body = re.sub(r"#[^\n]*", "", m.group(2))
        values = []
        for part in body.split(","):
            name = part.split("=")[0].strip()
            if name:
                values.append(name)
        out[m.group(1)] = values
    return out


class GdEnums:
    def __init__(self, root: str):
        self.root = root
        self._cache: dict[str, dict[str, list[str]]] = {}

    def get(self, name: str) -> list[str]:
        if name not in GD_ENUMS:
            raise KeyError(f"unknown GDScript enum '{name}' (add it to cm/enums.py GD_ENUMS)")
        rel, enum_name = GD_ENUMS[name]
        if rel not in self._cache:
            path = os.path.join(self.root, rel)
            try:
                with open(path, "r", encoding="utf-8") as f:
                    self._cache[rel] = parse_gd_enums(f.read())
            except OSError:
                self._cache[rel] = {}
        return list(self._cache[rel].get(enum_name, []))
