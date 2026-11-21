"""Schemas: one JSON file per data file in DevTools/schemas/.

A schema has one or more sections:

  collection  a dict of entries at `path`, optionally grouped by `levels`
              (e.g. armors.json is type -> slot -> id, so levels = [type, slot])
  settings    a single dict at `path` edited as one form (e.g. blacksmith.json)

Each section lists its `fields`. Field types:

  str, text, int, float, bool
  enum         one value from `options` / `source`
  enum_list    list of values
  enum_multi   one value or a list; keeps whichever shape the data already has
  ref, ref_list   like enum / enum_list but the values are ids from other files
  map          dict: `key` spec -> `value` spec (e.g. ingredients: material -> count)
  table        list of dicts with `columns`
  object       nested dict with its own `fields`
  json         anything else, edited as raw JSON

Common field options: label, help, default, optional (key may be absent),
min, max, options, source ("gd:<Enum>" or a data source, see project.SOURCES),
case ("lower"/"upper"), exclude, allow_custom.
"""
from __future__ import annotations

import json
import os

SCHEMA_DIR = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "schemas")

FIELD_TYPES = {"str", "text", "int", "float", "bool", "enum", "enum_list", "enum_multi",
               "ref", "ref_list", "map", "table", "object", "json"}


class SchemaError(Exception):
    pass


class Field:
    def __init__(self, spec: dict, where: str = ""):
        if "name" not in spec and where != "sub":
            raise SchemaError(f"{where}: field without a name: {spec}")
        self.spec = spec
        self.name: str = spec.get("name", "")
        self.type: str = spec.get("type", "str")
        if self.type not in FIELD_TYPES:
            raise SchemaError(f"{where}: field '{self.name}' has unknown type '{self.type}'")
        self.label: str = spec.get("label", self.name.replace("_", " ").capitalize())
        self.help: str = spec.get("help", "")
        self.optional: bool = bool(spec.get("optional", False))
        self.min = spec.get("min")
        self.max = spec.get("max")
        self.options: list = list(spec.get("options", []))
        self.source: str = spec.get("source", "")
        self.case: str = spec.get("case", "")
        self.exclude: list = list(spec.get("exclude", []))
        self.allow_custom: bool = bool(spec.get("allow_custom", False))
        self.required: bool = bool(spec.get("required", not self.optional))
        self.key = Field(spec["key"], "sub") if "key" in spec else None
        self.value = Field(spec["value"], "sub") if "value" in spec else None
        self.columns = [Field(c, f"{where}.{self.name}") for c in spec.get("columns", [])]
        self.fields = [Field(c, f"{where}.{self.name}") for c in spec.get("fields", [])]
        if self.type == "map" and (self.key is None or self.value is None):
            raise SchemaError(f"{where}: map field '{self.name}' needs 'key' and 'value'")

    @property
    def has_choices(self) -> bool:
        return self.type in ("enum", "enum_list", "enum_multi", "ref", "ref_list")

    def default_value(self):
        if "default" in self.spec:
            return json.loads(json.dumps(self.spec["default"]))
        return {
            "str": "", "text": "", "int": 0, "float": 0.0, "bool": False, "enum": "",
            "enum_list": [], "enum_multi": "", "ref": "", "ref_list": [], "map": {},
            "table": [], "object": {}, "json": None,
        }[self.type]


class Section:
    def __init__(self, spec: dict, tab: str, index: int):
        self.spec = spec
        self.tab = tab
        self.index = index
        self.kind: str = spec.get("kind", "collection")
        if self.kind not in ("collection", "settings"):
            raise SchemaError(f"{tab}: section kind must be collection or settings")
        self.label: str = spec.get("label", tab)
        self.path: list = list(spec.get("path", []))
        self.levels: list[dict] = list(spec.get("levels", []))
        self.key_label: str = spec.get("key_label", "Id")
        self.key_help: str = spec.get("key_help", "")
        self.key_style: str = spec.get("key_style", "snake")   # snake | title | upper | any
        self.name_field: str = spec.get("name_field", "")      # shown next to the key in lists
        self.summary: str = spec.get("summary", "")            # format string for the summary line
        self.fields = [Field(f, f"{tab}/{self.label}") for f in spec.get("fields", [])]
        self.field_map = {f.name: f for f in self.fields}
        self.ignore: list = list(spec.get("ignore", []))       # keys that are not entries (e.g. _comment)


class Schema:
    def __init__(self, spec: dict, filename: str = ""):
        self.spec = spec
        self.filename = filename
        self.tab: str = spec["tab"]
        self.file: str = spec["file"]
        self.order: int = int(spec.get("order", 100))
        self.description: str = spec.get("description", "")
        self.sections = [Section(s, self.tab, i) for i, s in enumerate(spec.get("sections", []))]
        if not self.sections:
            raise SchemaError(f"{self.tab}: no sections")


def load_schemas(directory: str = SCHEMA_DIR) -> list[Schema]:
    out = []
    for name in sorted(os.listdir(directory)):
        if not name.endswith(".json"):
            continue
        with open(os.path.join(directory, name), "r", encoding="utf-8") as f:
            try:
                spec = json.load(f)
            except ValueError as e:
                raise SchemaError(f"{name}: invalid JSON: {e}") from e
        out.append(Schema(spec, name))
    out.sort(key=lambda s: (s.order, s.tab))
    return out
