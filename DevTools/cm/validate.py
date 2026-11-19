"""Content checks that run instantly in Python (no Godot needed).

1. Schema checks, for every field of every entry: required keys, value types,
   number ranges, and that enum/reference values exist (e.g. a recipe
   ingredient is a real material, a class skill is a real skill).
2. Cross-file rules the schemas can't express (unique item ids, armor
   type/slot match their group, Blacksmith tables cover every rarity, ...).
3. Warnings for content nothing uses (orphan materials, unused skills).

Each problem is an Issue with a severity: "error" (the game will misbehave),
"warning" (probably a mistake) or "info".
"""
from __future__ import annotations

import json
import re
from dataclasses import dataclass, field as dc_field

from .project import EntryRef, Project
from .schema import Field

PLACEHOLDER = re.compile(r"^\{[a-z_]+\}$")


@dataclass
class Issue:
    severity: str              # error | warning | info
    tab: str
    ref: EntryRef | None
    field: str
    message: str
    source: str = "python"     # python | godot

    @property
    def where(self) -> str:
        return self.ref.label() if self.ref is not None else ""


@dataclass
class Report:
    issues: list = dc_field(default_factory=list)

    def add(self, severity, tab, ref, fieldname, message):
        self.issues.append(Issue(severity, tab, ref, fieldname, message))

    def count(self, severity) -> int:
        return sum(1 for i in self.issues if i.severity == severity)

    def summary(self) -> str:
        e, w, i = self.count("error"), self.count("warning"), self.count("info")
        if not (e or w or i):
            return "No problems found."
        return f"{e} error{'s' * (e != 1)}, {w} warning{'s' * (w != 1)}, {i} note{'s' * (i != 1)}"


def _is_number(v) -> bool:
    return isinstance(v, (int, float)) and not isinstance(v, bool)


class Validator:
    def __init__(self, project: Project):
        self.p = project
        self.r = Report()
        self._choice_cache: dict = {}

    def _choices(self, f: Field) -> list:
        key = id(f)
        if key not in self._choice_cache:
            self._choice_cache[key] = self.p.choices(f)
        return self._choice_cache[key]

    # ------------------------------------------------------------ schema checks

    def check_value(self, tab, ref, label, f: Field, v):
        add = lambda sev, msg: self.r.add(sev, tab, ref, label, msg)  # noqa: E731
        t = f.type
        if t in ("str", "text"):
            if not isinstance(v, str):
                add("error", f"should be text, is {type(v).__name__}")
            elif f.options or f.source:
                self._check_choice(tab, ref, label, f, v)
        elif t in ("int", "float"):
            if not _is_number(v):
                add("error", f"should be a number, is {json.dumps(v)}")
                return
            if t == "int" and isinstance(v, float) and not v.is_integer():
                add("error", f"should be a whole number, is {v}")
            if f.min is not None and v < f.min:
                add("error", f"{v} is below the minimum {f.min}")
            if f.max is not None and v > f.max:
                add("error", f"{v} is above the maximum {f.max}")
        elif t == "bool":
            if not isinstance(v, bool):
                add("error", f"should be true/false, is {json.dumps(v)}")
        elif t in ("enum", "ref"):
            if not isinstance(v, str):
                add("error", f"should be one value, is {json.dumps(v)}")
            else:
                self._check_choice(tab, ref, label, f, v)
        elif t in ("enum_list", "ref_list"):
            if not isinstance(v, list):
                add("error", f"should be a list, is {json.dumps(v)}")
                return
            for x in v:
                self._check_choice(tab, ref, label, f, x)
            if len(set(map(str, v))) != len(v):
                add("warning", "lists the same value twice")
        elif t == "enum_multi":
            for x in (v if isinstance(v, list) else [v]):
                if x not in ("", "NONE"):
                    self._check_choice(tab, ref, label, f, x)
        elif t == "map":
            if not isinstance(v, dict):
                add("error", f"should be a key -> value map, is {json.dumps(v)}")
                return
            for k, x in v.items():
                self.check_value(tab, ref, f"{label}[{k}]", f.key, k)
                self.check_value(tab, ref, f"{label}[{k}]", f.value, x)
        elif t == "table":
            if not isinstance(v, list):
                add("error", "should be a list of rows")
                return
            for i, row in enumerate(v):
                if not isinstance(row, dict):
                    add("error", f"row {i + 1} is not an object")
                    continue
                for c in f.columns:
                    if c.name not in row:
                        if not c.optional:
                            add("error", f"row {i + 1} has no '{c.name}'")
                        continue
                    self.check_value(tab, ref, f"{label}[{i + 1}].{c.name}", c, row[c.name])
        elif t == "object":
            if not isinstance(v, dict):
                add("error", "should be an object")
                return
            for sub in f.fields:
                if sub.name in v:
                    self.check_value(tab, ref, f"{label}.{sub.name}", sub, v[sub.name])
                elif not sub.optional:
                    add("error", f"missing '{sub.name}'")

    def _check_choice(self, tab, ref, label, f: Field, v):
        if f.allow_custom:
            return
        choices = self._choices(f)
        if v in choices or (v == "" and "" in f.options):
            return
        if isinstance(v, str) and PLACEHOLDER.match(v):
            return
        if f.source.startswith("gd:"):
            what = f"the {f.source[3:]} values (GDScript enum)"
        elif f.source:
            what = f"the {f.source.replace('_', ' ')}"
        else:
            what = "the allowed values"
        hint = ""
        close = [c for c in choices if isinstance(c, str) and isinstance(v, str) and c.lower() == v.lower()]
        if close:
            hint = f" (did you mean '{close[0]}'?)"
        self.r.add("error", tab, ref, label, f"'{v}' is not in {what}{hint}")

    def schema_checks(self):
        for s in self.p.schemas:
            if s.tab in self.p.load_errors:
                self.r.add("error", s.tab, None, "", f"file could not be read: {self.p.load_errors[s.tab]}")
                continue
            for si, sec in enumerate(s.sections):
                for ref in self.p.entries(s.tab, si):
                    entry = self.p.get(ref)
                    for f in sec.fields:
                        if f.name not in entry:
                            if f.required:
                                self.r.add("warning", s.tab, ref, f.name, "missing (the game will use its default)")
                            continue
                        self.check_value(s.tab, ref, f.name, f, entry[f.name])

    # ------------------------------------------------------------ cross checks

    def refs(self, tab, si=0):
        return self.p.entries(tab, si)

    def cross_checks(self):
        p, add = self.p, self.r.add
        # unique item ids across item files (ItemManager looks items up by id)
        seen: dict = {}
        for tab, src in [("Consumables", "consumables"), ("Materials", "materials"), ("Weapons", "weapons"), ("Armors", "armors")]:
            for ref in self.refs(tab):
                if ref.key in seen:
                    add("error", tab, ref, "", f"id '{ref.key}' is also used in {seen[ref.key]} - item ids must be unique")
                seen.setdefault(ref.key, tab)
        # skills: id must match name (classes list skills by name)
        for ref in self.refs("Skills"):
            e = p.get(ref)
            if e.get("name") != ref.key:
                add("error", "Skills", ref, "name", f"name '{e.get('name')}' differs from the id '{ref.key}'; classes look skills up by id")
            if e.get("damage_type") and e.get("ability_type") == "MAGICAL":
                add("warning", "Skills", ref, "damage_type", "damage types only apply to PHYSICAL skills")
            if e.get("type") == "DRAIN" and "drain_source" not in e:
                add("warning", "Skills", ref, "drain_source", "DRAIN skill without drain_source (defaults to HP)")
        # armor/weapon fields agree with their group
        for ref in self.refs("Armors"):
            e = p.get(ref)
            if e.get("type") != ref.groups[0]:
                add("error", "Armors", ref, "type", f"type '{e.get('type')}' but it is filed under '{ref.groups[0]}'")
            if e.get("slot") != ref.groups[1]:
                add("error", "Armors", ref, "slot", f"slot '{e.get('slot')}' but it is filed under '{ref.groups[1]}'")
        for ref in self.refs("Weapons"):
            e = p.get(ref)
            if e.get("slot") != ref.groups[0]:
                add("error", "Weapons", ref, "slot", f"slot '{e.get('slot')}' but it is filed under '{ref.groups[0]}'")
            if e.get("type") != ref.groups[1]:
                add("warning", "Weapons", ref, "type", f"type '{e.get('type')}' but it is filed under '{ref.groups[1]}'")
            tgt, inc = e.get("attribute_target"), e.get("attribute_increase")
            if isinstance(tgt, list) != isinstance(inc, list) or (isinstance(tgt, list) and len(tgt) != len(inc)):
                add("error", "Weapons", ref, "attribute_increase", "must be a list the same length as attribute_target")
        # every playable class has skills
        for ref in self.refs("Classes"):
            if ref.groups[0] == "playable" and not p.get(ref).get("skills"):
                add("warning", "Classes", ref, "skills", "playable class with no skills")
        # status effect entries must be real enum values
        statuses = set(p.source("gd:StatusEffect"))
        for ref in self.refs("Status Effects"):
            if ref.key not in statuses:
                add("error", "Status Effects", ref, "", f"'{ref.key}' is not in the StatusEffect enum (Skill.gd), so it is never used")
        # recipes: output exists and only one recipe per output
        outputs: dict = {}
        for ref in self.refs("Recipes"):
            e = p.get(ref)
            out = e.get("output")
            if out in outputs:
                add("warning", "Recipes", ref, "output", f"'{out}' is also made by recipe '{outputs[out]}'")
            outputs.setdefault(out, ref.key)
            u = e.get("unlock", {})
            if isinstance(u, dict):
                if u.get("type") == "purchase" and not u.get("price"):
                    add("error", "Recipes", ref, "unlock", "purchase unlock needs a price")
                if u.get("type") == "floor_reached" and not u.get("floor"):
                    add("error", "Recipes", ref, "unlock", "floor_reached unlock needs a floor")
                if u.get("type") == "adventurer_rank" and u.get("rank") not in p.source("ranks"):
                    add("error", "Recipes", ref, "unlock", f"adventurer_rank unlock needs a rank (got '{u.get('rank')}')")
            if not e.get("ingredients"):
                add("warning", "Recipes", ref, "ingredients", "no ingredients")
        self._combos()
        self._talents()
        self._blacksmith()
        self._material_drops()
        self._damage_types()
        self._bounties()
        self._archetypes()
        self._ranks()
        self._orphans()

    def _combos(self):
        p, add = self.p, self.r.add
        # which set-up statuses can anything actually inflict? (skill or consumable)
        inflicted = set()
        for ref in self.refs("Skills"):
            e = p.get(ref)
            for k in ("status_effect", "status_effects"):
                v = e.get(k)
                inflicted.update(v if isinstance(v, list) else [v])
        for ref in self.refs("Consumables"):
            inflicted.add(p.get(ref).get("status_effect"))
        seen = {}
        for ref in self.refs("Combos"):
            e = p.get(ref)
            payoff = e.get("payoff") or {}
            if not any(payoff.get(k) for k in ("damage_types", "elements", "ability_types", "skills")):
                add("error", "Combos", ref, "payoff", "no payoff - nothing can trigger this combo")
            if e.get("setup") and e.get("setup") not in inflicted:
                add("warning", "Combos", ref, "setup", f"no skill or item inflicts {e.get('setup')}, so this combo can't happen")
            key = (e.get("setup"), json.dumps(payoff, sort_keys=True))
            if key in seen:
                add("warning", "Combos", ref, "payoff", f"same set-up and payoff as '{seen[key]}' - only the stronger one ever applies")
            seen.setdefault(key, ref.key)

    EFFECT_TYPES = {"stats", "damage", "defense", "heal_bonus", "lifesteal", "skill", "combo", "status_chance", "regen"}
    CONDITIONS = {"with", "element", "elements", "damage_type", "ability", "skill", "category", "target_status",
                  "user_hp_below", "target_hp_below", "weak_spot"}

    def _talents(self):
        p, add = self.p, self.r.add
        if "Talents" not in p.data:
            return
        skills = set(p.source("skills"))
        combos = set(p.source("combos"))
        statuses = set(p.source("gd:StatusEffect"))
        classes = set(p.source("playable_classes"))
        branches = p.data["Talents"].get("branches", {})
        for cls in classes:
            if len(branches.get(cls, {})) != 3:
                add("warning", "Talents", None, "", f"{cls} has {len(branches.get(cls, {}))} talent branches (expected 3)")
        for ref in self.refs("Talents", 2):
            n = p.get(ref)
            cls, branch = ref.groups
            if cls not in classes:
                add("error", "Talents", ref, "", f"'{cls}' is not a playable class")
            if branch not in branches.get(cls, {}):
                add("error", "Talents", ref, "", f"branch '{branch}' is not listed under Branches for {cls}")
            if n.get("skill") and n["skill"] not in skills:
                add("error", "Talents", ref, "skill", f"skill '{n['skill']}' does not exist")
            for i, e in enumerate(n.get("effects", []) or []):
                t = e.get("type") if isinstance(e, dict) else None
                where = f"effects[{i + 1}]"
                if t not in self.EFFECT_TYPES:
                    add("error", "Talents", ref, where, f"unknown effect type '{t}'")
                    continue
                if t == "skill" and e.get("skill") not in skills:
                    add("error", "Talents", ref, where, f"upgrades unknown skill '{e.get('skill')}'")
                if t == "combo" and e.get("combo") not in combos:
                    add("error", "Talents", ref, where, f"unknown combo '{e.get('combo')}'")
                if e.get("target_status") and e["target_status"] not in statuses:
                    add("error", "Talents", ref, where, f"unknown status '{e['target_status']}'")
                if t in ("damage", "defense", "lifesteal"):
                    extra = set(e) - self.CONDITIONS - {"type", "mult", "reduce", "fraction"}
                    if extra:
                        add("warning", "Talents", ref, where, f"unknown condition(s): {', '.join(sorted(extra))}")
        for cls, bs in (p.data["Talents"].get("nodes") or {}).items():
            for b, nodes in bs.items():
                tiers = sorted(int(v.get("tier", 0)) for k, v in nodes.items() if isinstance(v, dict))
                if tiers != [1, 2, 3, 4, 5]:
                    add("warning", "Talents", None, "", f"{cls}/{b}: tiers are {tiers} (expected one node per tier 1-5)")

    def _blacksmith(self):
        p, add = self.p, self.r.add
        refs = self.refs("Blacksmith")
        if not refs:
            return
        ref = refs[0]
        cfg = p.get(ref)
        rarities = p.source("rarities")
        max_level = cfg.get("max_level", {})
        for r in rarities:
            if r not in max_level:
                add("error", "Blacksmith", ref, "max_level", f"no max level for rarity '{r}' (defaults to +3)")
        top = max([v for v in max_level.values() if _is_number(v)] or [0])
        sc = cfg.get("success_chance", {})
        missing = [str(l) for l in range(4, int(top) + 1) if str(l) not in sc]
        if missing:
            add("warning", "Blacksmith", ref, "success_chance", f"no entry for +{', +'.join(missing)} (those upgrades always succeed)")
        for k in sc:
            if not str(k).isdigit():
                add("error", "Blacksmith", ref, "success_chance", f"key '{k}' should be a level number")
        tiers = cfg.get("ore_by_target_level", [])
        if tiers and max(t.get("max_level", 0) for t in tiers) < top:
            add("error", "Blacksmith", ref, "ore_by_target_level", f"no ore tier reaches +{top}")
        salvage = cfg.get("salvage", {})
        for r in rarities:
            s = salvage.get(r) if isinstance(salvage, dict) else None
            if not isinstance(s, dict):
                add("warning", "Blacksmith", ref, "salvage", f"no salvage table for '{r}' (yields 1 ore)")
            elif not (isinstance(s.get("ore"), list) and len(s["ore"]) == 2 and s["ore"][0] <= s["ore"][1]):
                add("error", "Blacksmith", ref, "salvage", f"'{r}': ore must be [min, max]")

    def _material_drops(self):
        p, add = self.p, self.r.add
        races = set(p.source("races"))
        enemy_races = set(p.source("enemy_races"))
        have = set()
        for ref in self.refs("Material Drops", 1):
            have.add(ref.key)
            if ref.key not in races:
                add("error", "Material Drops", ref, "", f"'{ref.key}' is not a race")
        for r in sorted(enemy_races - have):
            add("warning", "Material Drops", None, "", f"enemy race '{r}' has no material table (drops nothing)")
        s = self.refs("Material Drops", 0)
        if s:
            cfg = p.get(s[0])
            if _is_number(cfg.get("per_wave_min")) and _is_number(cfg.get("per_wave_max")) and cfg["per_wave_min"] > cfg["per_wave_max"]:
                add("error", "Material Drops", s[0], "per_wave_min", "per_wave_min is larger than per_wave_max")

    def _damage_types(self):
        p, add = self.p, self.r.add
        s = self.refs("Damage Types", 0)
        if not s:
            return
        cfg = p.get(s[0])
        typed = cfg.get("weapons", {})
        for ref in self.refs("Weapons"):
            if ref.groups[0] == "main_hand" and ref.key not in typed:
                add("warning", "Damage Types", s[0], "weapons", f"weapon '{ref.key}' has no damage type (its hits are untyped)")
        if _is_number(cfg.get("min_multiplier")) and _is_number(cfg.get("max_multiplier")) and cfg["min_multiplier"] > cfg["max_multiplier"]:
            add("error", "Damage Types", s[0], "min_multiplier", "min_multiplier is larger than max_multiplier")
        armor_types = set(p.source("armor_types"))
        for ref in self.refs("Damage Types", 1):
            if ref.key not in armor_types:
                add("error", "Damage Types", ref, "", f"'{ref.key}' is not an armor type")
        races = set(p.source("races"))
        for ref in self.refs("Damage Types", 2):
            if ref.key not in races:
                add("error", "Damage Types", ref, "", f"'{ref.key}' is not a race")

    def _bounties(self):
        p, add = self.p, self.r.add
        materials = set(p.source("materials"))
        items = set(p.source("items"))
        recipes = set(p.source("recipes"))
        for ref in self.refs("Bounties", 1):
            e = p.get(ref)
            obj = e.get("objective", {})
            if not isinstance(obj, dict) or obj.get("type") not in ("KILL", "KILL_BOSS", "CLEAR_FLOOR", "WIN_STREAK", "DELIVER"):
                add("error", "Bounties", ref, "objective", "type must be KILL, KILL_BOSS, CLEAR_FLOOR, WIN_STREAK or DELIVER")
            rw = e.get("rewards", {})
            if not isinstance(rw, dict):
                add("error", "Bounties", ref, "rewards", "should be an object")
                continue
            for k in (rw.get("materials") or {}):
                if not PLACEHOLDER.match(k) and k not in materials:
                    add("error", "Bounties", ref, "rewards", f"material '{k}' does not exist")
            for k in (rw.get("chance") or {}):
                if not PLACEHOLDER.match(k) and k not in items:
                    add("error", "Bounties", ref, "rewards", f"item '{k}' does not exist")
            rec = rw.get("recipe")
            if isinstance(rec, str) and rec and not PLACEHOLDER.match(rec) and rec not in recipes:
                add("error", "Bounties", ref, "rewards", f"recipe '{rec}' does not exist")

    def _archetypes(self):
        p, add = self.p, self.r.add
        tab = "Enemy Archetypes"
        if tab not in p.data:
            return
        d = p.data[tab]
        skills = set(p.source("skills"))
        playable = set(p.source("playable_classes"))
        archetypes = d.get("archetypes", {})
        roles = {k for k in d.get("ai_roles", {}) if not k.startswith("_")}
        talents = p.data.get("Talents", {}).get("branches", {})
        for ref in self.refs(tab, 1):
            a = p.get(ref)
            if a.get("ai_role") and a["ai_role"] not in roles:
                add("error", tab, ref, "ai_role", f"unknown AI role '{a['ai_role']}'")
            for pool, names in (a.get("skill_pools") or {}).items():
                if pool != "monster" and pool not in playable:
                    add("error", tab, ref, "skill_pools", f"pool '{pool}' is not a playable class or 'monster'")
            t = a.get("talents") or {}
            if t.get("class") and t.get("branch") and t["branch"] not in talents.get(t["class"], {}):
                add("error", tab, ref, "talents", f"{t['class']} has no talent branch '{t['branch']}'")
            pool_count = sum(len(v) for v in (a.get("skill_pools") or {}).values())
            if pool_count < int(a.get("skills_per_enemy", 3)):
                add("warning", tab, ref, "skill_pools", f"only {pool_count} skills in the pools for {a.get('skills_per_enemy', 3)} picks")
        for ref in self.refs(tab, 2):
            for k in (p.get(ref).get("archetype_weights") or {}):
                if k not in archetypes:
                    add("error", tab, ref, "archetype_weights", f"unknown archetype '{k}'")
        for ref in self.refs(tab, 5):
            n = p.get(ref)
            if n.get("archetype") and n["archetype"] not in archetypes:
                add("error", tab, ref, "archetype", f"unknown archetype '{n['archetype']}'")
        for i, ph in enumerate((d.get("boss") or {}).get("phases", []) or []):
            if not isinstance(ph, dict) or ph.get("use") not in ("signature", "ultimate"):
                add("error", tab, None, "phases", f"phase {i + 1}: 'use' must be 'signature' or 'ultimate'")

    def _ranks(self):
        p, add = self.p, self.r.add
        if "Ranks" not in p.data:
            return
        ranks = sorted(self.refs("Ranks", 1), key=lambda r: int(p.get(r).get("order", 0)))
        prev_points, prev_cap = -1, -1
        for i, ref in enumerate(ranks):
            r = p.get(ref)
            if int(r.get("points", 0)) <= prev_points:
                add("warning", "Ranks", ref, "points", "needs no more Guild Points than the rank below")
            cap = int(r.get("floor_cap", 0))
            if prev_cap == 0 and cap > 0:
                add("warning", "Ranks", ref, "floor_cap", "caps floors although a lower rank has no cap")
            elif cap and prev_cap > 0 and cap < prev_cap:
                add("warning", "Ranks", ref, "floor_cap", "lower than the rank below")
            t = r.get("trial")
            if i > 0 and not t:
                add("error", "Ranks", ref, "trial", "every rank above the first needs a promotion trial")
            if t and prev_cap > 0 and int(t.get("min_floor", 1)) > prev_cap:
                add("error", "Ranks", ref, "trial", f"trial needs floor {t.get('min_floor')} but the rank below is capped at {prev_cap}")
            prev_points, prev_cap = int(r.get("points", 0)), cap

    def _orphans(self):
        p, add = self.p, self.r.add
        used = set()
        for ref in self.refs("Recipes"):
            used.update((p.get(ref).get("ingredients") or {}).keys())
        for ref in self.refs("Material Drops", 1):
            e = p.get(ref)
            used.update(e.get("common", []) + e.get("uncommon", []))
        md = self.refs("Material Drops", 0)
        if md:
            cfg = p.get(md[0])
            used.update(r.get("id") for r in cfg.get("floor_materials", []))
            used.update((cfg.get("boss_drops") or {}).keys())
        bs = self.refs("Blacksmith")
        if bs:
            text = json.dumps(p.get(bs[0]))
            used.update(m for m in p.source("materials") if f'"{m}"' in text)
        text = json.dumps(p.data.get("Bounties", {}))
        used.update(m for m in p.source("materials") if f'"{m}"' in text)
        for ref in self.refs("Materials"):
            if ref.key not in used:
                add("info", "Materials", ref, "", "not used by any recipe, drop table, bounty or the Blacksmith")
        skill_users = set()
        for ref in self.refs("Classes"):
            skill_users.update(p.get(ref).get("skills", []))
        if "Talents" in p.data:
            for ref in self.refs("Talents", 2):
                if p.get(ref).get("skill"):
                    skill_users.add(p.get(ref)["skill"])
        if "Enemy Archetypes" in p.data:
            text = json.dumps(p.data["Enemy Archetypes"])
            skill_users.update(s for s in p.source("skills") if f'"{s}"' in text)
        for ref in self.refs("Skills"):
            if ref.key not in skill_users:
                add("info", "Skills", ref, "", "no class or talent grants this skill")

    def run(self) -> Report:
        self.schema_checks()
        self.cross_checks()
        order = {"error": 0, "warning": 1, "info": 2}
        self.r.issues.sort(key=lambda i: (order.get(i.severity, 3), i.tab, i.where))
        return self.r


def validate(project: Project) -> Report:
    return Validator(project).run()
