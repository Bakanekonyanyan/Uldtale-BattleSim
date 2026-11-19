"""The loaded project: data files, reference lists for dropdowns, entry editing,
dirty tracking and saving. No UI code here, so it can be unit-tested."""
from __future__ import annotations

import copy
import json
import os
import re

from . import jsonio
from .enums import GdEnums
from .schema import Field, Schema, Section, load_schemas

# Data sources usable as "source" in schemas (besides "gd:<Enum>").
SOURCES = (
    "items", "materials", "consumables", "weapons", "armors", "equipment",
    "skills", "classes", "playable_classes", "enemy_classes", "races", "playable_races",
    "enemy_races", "locations", "status_effects", "rarities", "recipes", "armor_types",
    "item_stats",
)

# Lower-case stat keys equipment may put in attribute_target / effects
ITEM_STATS = ["vitality", "strength", "dexterity", "intelligence", "faith", "mind", "endurance",
              "arcane", "agility", "fortitude", "spell_ward", "toughness", "dodge", "accuracy",
              "critical_hit_rate", "armor_penetration", "spell_power", "attack_power",
              "status_effect_chance"]


def canonical(obj) -> str:
    return json.dumps(obj, sort_keys=False, ensure_ascii=False)


class EntryRef:
    """Address of one entry (or a settings section) inside a tab's data."""

    def __init__(self, tab: str, section: int, groups: tuple = (), key: str | None = None):
        self.tab = tab
        self.section = section
        self.groups = tuple(groups)
        self.key = key

    @property
    def path(self) -> tuple:
        return self.groups + ((self.key,) if self.key is not None else ())

    def __eq__(self, other):
        return isinstance(other, EntryRef) and (self.tab, self.section, self.path) == (other.tab, other.section, other.path)

    def __hash__(self):
        return hash((self.tab, self.section, self.path))

    def __repr__(self):
        return f"EntryRef({self.tab!r}, {self.section}, {'/'.join(map(str, self.path)) or '<settings>'})"

    def label(self) -> str:
        return " / ".join(str(p) for p in self.path) or "Settings"


class Project:
    def __init__(self, root: str, schemas: list[Schema] | None = None):
        self.root = root
        self.schemas = schemas if schemas is not None else load_schemas()
        self.by_tab = {s.tab: s for s in self.schemas}
        self.enums = GdEnums(root)
        self.data: dict = {}
        self.indent: dict = {}
        self._original: dict = {}
        self.load_errors: dict = {}
        self.load()

    # ---------------------------------------------------------------- files

    def path_of(self, tab: str) -> str:
        return os.path.join(self.root, self.by_tab[tab].file)

    def load(self) -> None:
        self.data.clear()
        self.load_errors.clear()
        self.enums = GdEnums(self.root)
        for s in self.schemas:
            p = self.path_of(s.tab)
            try:
                with open(p, "r", encoding="utf-8") as f:
                    text = f.read()
                self.data[s.tab] = json.loads(text)
                self.indent[s.tab] = jsonio.detect_indent(text)
            except (OSError, ValueError) as e:
                self.data[s.tab] = {}
                self.indent[s.tab] = "\t"
                self.load_errors[s.tab] = str(e)
            self._original[s.tab] = canonical(self.data[s.tab])

    def is_dirty(self, tab: str) -> bool:
        return canonical(self.data.get(tab)) != self._original.get(tab)

    def dirty_tabs(self) -> list[str]:
        return [s.tab for s in self.schemas if self.is_dirty(s.tab)]

    def save(self, tab: str) -> bool:
        """Write one tab's file if it changed. Returns True if written."""
        if tab in self.load_errors or not self.is_dirty(tab):
            return False
        jsonio.save(self.path_of(tab), self.data[tab], self.indent.get(tab, "\t"))
        self._original[tab] = canonical(self.data[tab])
        return True

    def save_all(self) -> list[str]:
        return [t for t in self.dirty_tabs() if self.save(t)]

    def revert(self, tab: str) -> None:
        self.data[tab] = json.loads(self._original[tab])

    # ---------------------------------------------------------- navigation

    def section(self, ref: EntryRef) -> Section:
        return self.by_tab[ref.tab].sections[ref.section]

    def section_root(self, tab: str, section: Section, create: bool = False):
        node = self.data.get(tab)
        for p in section.path:
            if not isinstance(node, dict):
                return None
            if p not in node:
                if not create:
                    return None
                node[p] = {}
            node = node[p]
        return node if isinstance(node, dict) else None

    def entries(self, tab: str, section_index: int) -> list[EntryRef]:
        section = self.by_tab[tab].sections[section_index]
        root = self.section_root(tab, section)
        if root is None:
            return []
        if section.kind == "settings":
            return [EntryRef(tab, section_index)]
        out: list[EntryRef] = []

        def walk(node, groups, depth):
            if depth == len(section.levels):
                for k, v in node.items():
                    if k in section.ignore or str(k).startswith("_") or not isinstance(v, dict):
                        continue
                    out.append(EntryRef(tab, section_index, groups, k))
                return
            for g, child in node.items():
                if str(g).startswith("_") or g in section.ignore or not isinstance(child, dict):
                    continue
                walk(child, groups + (g,), depth + 1)

        walk(root, (), 0)
        return out

    def get(self, ref: EntryRef):
        section = self.section(ref)
        node = self.section_root(ref.tab, section)
        for p in ref.path:
            if not isinstance(node, dict) or p not in node:
                return None
            node = node[p]
        return node

    def _parent(self, ref: EntryRef, create: bool = False) -> dict | None:
        section = self.section(ref)
        node = self.section_root(ref.tab, section, create)
        for g in ref.groups:
            if node is None:
                return None
            if g not in node:
                if not create:
                    return None
                node[g] = {}
            node = node[g]
        return node

    def other_fields(self, ref: EntryRef) -> list[str]:
        """Keys present in an entry that the schema doesn't describe."""
        entry = self.get(ref)
        if not isinstance(entry, dict):
            return []
        section = self.section(ref)
        known = set(section.field_map)
        if section.kind == "settings":
            # keys owned by other sections nested under this one (e.g. "races") aren't "other"
            for other in self.by_tab[ref.tab].sections:
                if other is not section and other.path[: len(section.path)] == section.path and len(other.path) > len(section.path):
                    known.add(other.path[len(section.path)])
        return [k for k in entry if k not in known]

    # -------------------------------------------------------------- editing

    def set_field(self, ref: EntryRef, name: str, value, remove: bool = False) -> None:
        entry = self.get(ref)
        if not isinstance(entry, dict):
            raise KeyError(f"{ref} not found")
        if remove:
            entry.pop(name, None)
        else:
            entry[name] = value

    def template_for(self, section: Section) -> dict:
        """A new entry: every non-optional field at its default."""
        return {f.name: f.default_value() for f in section.fields if not f.optional}

    def suggest_key(self, section: Section, display_name: str) -> str:
        s = display_name.strip()
        if section.key_style == "snake":
            return re.sub(r"[^a-z0-9]+", "_", s.lower()).strip("_")
        if section.key_style == "upper":
            return re.sub(r"[^A-Z0-9]+", "_", s.upper()).strip("_")
        return s

    def key_problem(self, section: Section, key: str) -> str:
        if not key:
            return "The id can't be empty."
        if key.startswith("_"):
            return "Ids starting with _ are reserved for comments."
        if section.key_style == "snake" and not re.fullmatch(r"[a-z0-9_]+", key):
            return "Use lower_case_with_underscores (like the other ids in this file)."
        if section.key_style == "upper" and not re.fullmatch(r"[A-Z0-9_]+", key):
            return "Use UPPER_CASE_WITH_UNDERSCORES (like the other ids in this file)."
        return ""

    def add_entry(self, tab: str, section_index: int, groups: tuple, key: str, entry: dict | None = None) -> EntryRef:
        section = self.by_tab[tab].sections[section_index]
        ref = EntryRef(tab, section_index, groups, key)
        parent = self._parent(ref, create=True)
        if key in parent:
            raise KeyError(f"'{key}' already exists")
        parent[key] = copy.deepcopy(entry) if entry is not None else self.template_for(section)
        return ref

    def delete_entry(self, ref: EntryRef) -> None:
        parent = self._parent(ref)
        if parent is not None:
            parent.pop(ref.key, None)

    def rename_entry(self, ref: EntryRef, new_key: str) -> EntryRef:
        parent = self._parent(ref)
        if parent is None or ref.key not in parent:
            raise KeyError(f"{ref} not found")
        if new_key in parent:
            raise KeyError(f"'{new_key}' already exists")
        # rebuild to keep the entry in the same position
        items = list(parent.items())
        parent.clear()
        for k, v in items:
            parent[new_key if k == ref.key else k] = v
        return EntryRef(ref.tab, ref.section, ref.groups, new_key)

    def group_options(self, tab: str, section_index: int, level: int, parent_groups: tuple) -> list[str]:
        section = self.by_tab[tab].sections[section_index]
        spec = section.levels[level]
        opts = list(spec.get("options", []))
        node = self.section_root(tab, section)
        for g in parent_groups:
            node = node.get(g, {}) if isinstance(node, dict) else {}
        if isinstance(node, dict):
            for k, v in node.items():
                if isinstance(v, dict) and not str(k).startswith("_") and k not in opts:
                    opts.append(k)
        return opts

    # ------------------------------------------------------- reference lists

    def choices(self, field: Field) -> list[str]:
        """Allowed values for an enum/ref field (before exclusions/case)."""
        vals: list = list(field.options)
        if field.source:
            vals += [v for v in self.source(field.source) if v not in vals]
        if field.exclude:
            vals = [v for v in vals if v not in field.exclude]
        if field.case == "lower":
            vals = [str(v).lower() for v in vals]
        elif field.case == "upper":
            vals = [str(v).upper() for v in vals]
        out = []
        for v in vals:
            if v not in out:
                out.append(v)
        return out

    def source(self, name: str) -> list[str]:
        if name.startswith("gd:"):
            return self.enums.get(name[3:])
        d = self.data
        if name == "materials":
            return list(_entries(d.get("Materials", {})))
        if name == "consumables":
            return list(_entries(d.get("Consumables", {})))
        if name == "weapons":
            return _leaf_keys(d.get("Weapons", {}), 3)
        if name == "armors":
            return _leaf_keys(d.get("Armors", {}), 3)
        if name == "equipment":
            return self.source("weapons") + self.source("armors")
        if name == "items":
            return self.source("consumables") + self.source("materials") + self.source("equipment")
        if name == "skills":
            return list(_entries(d.get("Skills", {}).get("skills", {})))
        if name in ("classes", "playable_classes", "enemy_classes"):
            groups = {"classes": None, "playable_classes": ["playable"], "enemy_classes": ["non_playable", "boss"]}[name]
            return _grouped(d.get("Classes", {}), groups)
        if name in ("races", "playable_races", "enemy_races"):
            groups = {"races": None, "playable_races": ["playable"], "enemy_races": ["non_playable"]}[name]
            return _grouped(d.get("Races", {}), groups)
        if name == "locations":
            return list(_entries(d.get("Locations", {}).get("locations", {})))
        if name == "status_effects":
            return list(_entries(d.get("Status Effects", {})))
        if name == "rarities":
            return list(_entries(d.get("Rarities", {})))
        if name == "recipes":
            return list(_entries(d.get("Recipes", {}).get("recipes", {})))
        if name == "armor_types":
            return list(_entries(d.get("Armors", {})))
        if name == "item_stats":
            return list(ITEM_STATS)
        raise KeyError(f"unknown source '{name}'")

    def display_name(self, ref: EntryRef) -> str:
        section = self.section(ref)
        entry = self.get(ref)
        if section.name_field and isinstance(entry, dict):
            n = entry.get(section.name_field)
            if n and str(n) != str(ref.key):
                return f"{ref.key}  ({n})"
        return str(ref.key) if ref.key is not None else section.label


def _entries(node) -> dict:
    if not isinstance(node, dict):
        return {}
    return {k: v for k, v in node.items() if isinstance(v, dict) and not str(k).startswith("_")}


def _leaf_keys(node, depth: int) -> list[str]:
    out: list[str] = []

    def walk(n, d):
        if not isinstance(n, dict):
            return
        if d == 1:
            out.extend(k for k, v in n.items() if isinstance(v, dict) and not str(k).startswith("_"))
            return
        for v in n.values():
            walk(v, d - 1)

    walk(node, depth)
    return out


def _grouped(node, groups) -> list[str]:
    out: list[str] = []
    if not isinstance(node, dict):
        return out
    for g, entries in node.items():
        if groups is not None and g not in groups:
            continue
        out.extend(_entries(entries))
    return out
