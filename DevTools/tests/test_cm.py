"""Tests for the content manager core (no UI). Run from the repo root:

    python -m unittest discover -s DevTools/tests -v
"""
import copy
import difflib
import json
import os
import shutil
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
DEVTOOLS = os.path.dirname(HERE)
ROOT = os.path.dirname(DEVTOOLS)
sys.path.insert(0, DEVTOOLS)

from cm import jsonio  # noqa: E402
from cm.enums import parse_gd_enums  # noqa: E402
from cm.project import EntryRef, Project  # noqa: E402
from cm.splice import splice  # noqa: E402
from cm.validate import validate  # noqa: E402


def changed_lines(a: str, b: str) -> int:
    return sum(1 for l in difflib.unified_diff(a.splitlines(), b.splitlines(), lineterm="", n=0)
               if l[:1] in "+-" and not l.startswith(("+++", "---")))


class TempProject(unittest.TestCase):
    """Each test gets a scratch copy of data/ + the GDScript files enums come from."""

    def setUp(self):
        self.tmp = tempfile.mkdtemp(prefix="cm-test-")
        shutil.copytree(os.path.join(ROOT, "data"), os.path.join(self.tmp, "data"))
        for rel in ["scenes/mechanics/Skill.gd", "scripts/resources/ElementalDamage.gd",
                    "scripts/resources/Item.gd", "scripts/resources/DamageTypes.gd"]:
            os.makedirs(os.path.dirname(os.path.join(self.tmp, rel)), exist_ok=True)
            shutil.copy(os.path.join(ROOT, rel), os.path.join(self.tmp, rel))
        open(os.path.join(self.tmp, "project.godot"), "w").close()
        jsonio.BACKUP_DIR = os.path.join(self.tmp, "_backups")
        self.p = Project(self.tmp)

    def tearDown(self):
        shutil.rmtree(self.tmp, ignore_errors=True)

    def read(self, tab):
        with open(self.p.path_of(tab), encoding="utf-8") as f:
            return f.read()


class TestModel(TempProject):
    def test_all_files_load_and_nothing_is_dirty(self):
        self.assertEqual(self.p.load_errors, {})
        self.assertEqual(self.p.dirty_tabs(), [])

    def test_every_schema_source_resolves(self):
        for s in self.p.schemas:
            for sec in s.sections:
                for f in sec.fields:
                    for sub in [f, f.key, f.value] + f.columns + f.fields:
                        if sub is not None and sub.source:
                            self.assertTrue(self.p.source(sub.source), f"{s.tab}.{f.name}: source {sub.source} is empty")

    def test_every_entry_found_and_described(self):
        expected_min = {"Skills": 40, "Classes": 10, "Races": 10, "Armors": 20, "Weapons": 10}
        for s in self.p.schemas:
            refs = [r for i in range(len(s.sections)) for r in self.p.entries(s.tab, i)]
            self.assertGreaterEqual(len(refs), expected_min.get(s.tab, 1), s.tab)
            for r in refs:
                unknown = [k for k in self.p.other_fields(r) if not k.startswith("_")]
                self.assertEqual(unknown, [], f"{r}: fields missing from the schema")

    def test_gd_enums(self):
        e = parse_gd_enums("enum A { X, Y = 3, # comment\n Z }\nenum B {Q}")
        self.assertEqual(e, {"A": ["X", "Y", "Z"], "B": ["Q"]})
        self.assertIn("DAMAGE", self.p.source("gd:SkillType"))
        self.assertIn("SLASH", self.p.source("gd:DamageType"))

    def test_untouched_save_writes_nothing(self):
        before = {s.tab: self.read(s.tab) for s in self.p.schemas}
        self.assertEqual(self.p.save_all(), [])
        for s in self.p.schemas:
            self.assertEqual(self.read(s.tab), before[s.tab])

    def test_add_rename_delete_entry(self):
        ref = self.p.add_entry("Materials", 0, (), "test_ore", {"name": "Test Ore", "description": "", "item_type": "MATERIAL", "value": 1, "stackable": True, "max_stack": 9})
        self.assertIn("test_ore", self.p.source("materials"))
        ref2 = self.p.rename_entry(ref, "test_ore_2")
        self.assertNotIn("test_ore", self.p.source("materials"))
        self.assertEqual(list(self.p.data["Materials"])[-1], "test_ore_2")
        self.p.delete_entry(ref2)
        self.assertFalse(self.p.is_dirty("Materials"))

    def test_grouped_new_entry_and_template(self):
        sec = self.p.by_tab["Armors"].sections[0]
        t = self.p.template_for(sec)
        self.assertIn("armor_value", t)
        ref = self.p.add_entry("Armors", 0, ("plate", "head"), "test_helm", t)
        self.assertIn("test_helm", self.p.source("armors"))
        self.assertEqual(self.p.get(ref)["armor_value"], 4)

    def test_key_rules(self):
        sec = self.p.by_tab["Materials"].sections[0]
        self.assertEqual(self.p.suggest_key(sec, "Frost Root Chunk!"), "frost_root_chunk")
        self.assertTrue(self.p.key_problem(sec, "Bad Key"))
        self.assertFalse(self.p.key_problem(sec, "good_key"))


class TestMinimalDiffSave(TempProject):
    """Saving must only touch what changed, in every data file."""

    def edit_and_save(self, tab, mutate):
        before = self.read(tab)
        mutate(self.p.data[tab])
        expected = copy.deepcopy(self.p.data[tab])
        self.assertTrue(self.p.save(tab))
        after = self.read(tab)
        self.assertEqual(json.loads(after), expected, f"{tab}: saved data differs")
        return changed_lines(before, after)

    def test_scalar_change_is_one_line_in_every_file(self):
        for s in self.p.schemas:
            refs = [r for i in range(len(s.sections)) for r in self.p.entries(s.tab, i)]
            entry = self.p.get(refs[0])
            key = next((k for k, v in entry.items() if isinstance(v, (int, float)) and not isinstance(v, bool)), None)
            if key is None:
                continue
            n = self.edit_and_save(s.tab, lambda d: entry.__setitem__(key, entry[key] + 1))
            self.assertLessEqual(n, 2, f"{s.tab}: changing {key} rewrote {n} lines")

    def test_add_field_add_entry_remove_field(self):
        skills = self.p.data["Skills"]["skills"]
        first = next(iter(skills))
        n = self.edit_and_save("Skills", lambda d: d["skills"][first].__setitem__("damage_type", "SLASH"))
        self.assertLessEqual(n, 3)
        n = self.edit_and_save("Skills", lambda d: d["skills"][first].pop("damage_type"))
        self.assertLessEqual(n, 3)
        new_skill = dict(skills[first], name="Test Skill")
        n = self.edit_and_save("Skills", lambda d: d["skills"].__setitem__("Test Skill", new_skill))
        self.assertLessEqual(n, len(new_skill) + 4)

    def test_rename_and_delete_entries(self):
        ref = EntryRef("Consumables", 0, (), next(iter(self.p.data["Consumables"])))
        before = self.read("Consumables")
        self.p.rename_entry(ref, "renamed_potion")
        self.p.save("Consumables")
        self.assertLessEqual(changed_lines(before, self.read("Consumables")), 3)
        # delete the first and the last entry
        before = self.read("Consumables")
        keys = list(self.p.data["Consumables"])
        del self.p.data["Consumables"][keys[0]]
        del self.p.data["Consumables"][keys[-1]]
        self.assertTrue(self.p.save("Consumables"))
        self.assertEqual(json.loads(self.read("Consumables")), self.p.data["Consumables"])

    def test_inline_values_stay_inline(self):
        n = self.edit_and_save("Blacksmith", lambda d: d["max_level"].__setitem__("common", 4))
        self.assertEqual(n, 2)
        text = self.read("Blacksmith")
        self.assertIn('"max_level": { "common": 4,', text)
        n = self.edit_and_save("Classes", lambda d: d["playable"]["Paladin"]["skills"].append("Smite"))
        self.assertEqual(n, 2)

    def test_splice_falls_back_cleanly(self):
        self.assertIsNone(splice("{ not json", {"a": 1}))
        self.assertEqual(json.loads(splice('{\n\t"a": 1,\n\t"b": [1, 2]\n}\n', {"a": 1, "b": [1, 2, 3]})), {"a": 1, "b": [1, 2, 3]})


class TestValidate(TempProject):
    def errors(self):
        return [(i.tab, i.where, i.field, i.message) for i in validate(self.p).issues if i.severity == "error"]

    def assertCaught(self, needle):
        errs = self.errors()
        self.assertTrue(any(needle in " ".join(map(str, e)) for e in errs), f"expected an error mentioning {needle!r}, got {errs}")

    def test_real_data_has_no_errors(self):
        self.assertEqual(self.errors(), [])

    def test_broken_references(self):
        d = self.p.data
        del d["Materials"]["glowcap_mushroom"]                       # used by recipes and drop tables
        self.assertCaught("'glowcap_mushroom' is not in the materials")
        d["Classes"]["playable"]["Paladin"]["skills"].append("Holy Strik")
        self.assertCaught("'Holy Strik' is not in the skills")
        d["Skills"]["skills"]["Iaido"]["status_effect"] = "BLED"
        self.assertCaught("'BLED' is not in the StatusEffect values")

    def test_types_ranges_and_case_hint(self):
        d = self.p.data
        d["Skills"]["skills"]["Iaido"]["power"] = "lots"
        self.assertCaught("should be a number")
        d["Skills"]["skills"]["Iaido"]["power"] = 900
        self.assertCaught("above the maximum")
        d["Skills"]["skills"]["Iaido"]["type"] = "damage"
        self.assertCaught("did you mean 'DAMAGE'")

    def test_cross_file_rules(self):
        d = self.p.data
        d["Armors"]["plate"]["head"][next(iter(d["Armors"]["plate"]["head"]))]["slot"] = "feet"
        self.assertCaught("filed under 'head'")
        del d["Blacksmith"]["max_level"]["epic"]
        self.assertCaught("no max level for rarity 'epic'")
        d["Materials"]["dagger"] = dict(d["Materials"]["wood"])
        self.assertCaught("item ids must be unique")
        d["Skills"]["skills"]["Iaido"]["name"] = "Iaido Strike"
        self.assertCaught("differs from the id")
        d["Recipes"]["recipes"]["health_potion"]["unlock"] = {"type": "purchase"}
        self.assertCaught("purchase unlock needs a price")
        d["Damage Types"]["races"]["Gobbo"] = {"SLASH": 0.1}
        self.assertCaught("'Gobbo' is not a race")


class TestGodotHelpers(unittest.TestCase):
    def test_parsers(self):
        from cm import godot
        out = ["noise", "VALIDATE ERROR|Skills|Iaido|Skill.create_from_dict failed", "SCRIPT ERROR: Invalid access to 'DAMAG'",
               "   at: create_from_dict (res://scenes/mechanics/Skill.gd:89)",
               "ERROR: 20 resources still in use at exit (run with --verbose for details).", "VALIDATE RESULT: 1 errors, 600 checks"]
        issues, summary = godot.parse_validate(out, lambda tab, entry: EntryRef(tab, 0, (), entry) if entry == "Iaido" else None)
        self.assertEqual(summary, "Godot: 1 errors, 600 checks")
        self.assertEqual(len(issues), 2)                       # the VALIDATE line + the SCRIPT ERROR, not the noise
        self.assertEqual(issues[0].ref.key, "Iaido")
        self.assertIn("Skill.gd:89", issues[1].message)
        smoke = godot.parse_smoke(["PASS: a", "FAIL: b went wrong", "SMOKE RESULT: 9 passed, 1 failed"])
        self.assertEqual((smoke["passed"], smoke["failed"], smoke["failures"], smoke["finished"]), (9, 1, ["b went wrong"], True))
        sim = godot.parse_sim(["SIM PROGRESS|1|2", "SIM ROW|Monk|20|40|40|set-up", "SIM DONE"])
        self.assertEqual(sim["rows"][0], {"class": "Monk", "damage_only": 20, "set_up": 40, "best": 40, "style": "set-up"})
        self.assertTrue(sim["finished"])

    def test_sim_args_history_and_compare(self):
        from cm import godot
        args = godot.sim_args({"classes": ["Monk"], "location": "troll_caves", "set_up": "both", "potions": 5, "runs": 60, "floor": 2})
        self.assertEqual(args[:3], ["res://tests/balance_sim.tscn", "--", "tool"])
        self.assertIn("--classes=Monk", args)
        self.assertIn("--setup=both", args)
        self.assertIn("--runs=60", args)
        tmp = tempfile.mkdtemp()
        try:
            h = godot.SimHistory(tmp)
            h.save({"runs": 60}, [{"class": "Monk", "best": 30}], "before")
            import time
            time.sleep(1.1)
            h.save({"runs": 60}, [{"class": "Monk", "best": 45}, {"class": "Druid", "best": 10}], "after")
            recs = h.load_all()
            self.assertEqual([r["label"] for r in recs], ["after", "before"])
            rows = godot.compare(recs[1], recs[0])
            self.assertEqual(rows[0], {"class": "Monk", "a": 30, "b": 45, "change": 15})
            self.assertEqual(rows[1]["change"], None)
        finally:
            shutil.rmtree(tmp, ignore_errors=True)

    def test_noise_band(self):
        band = lambda runs: max(3, round(141 / max(1, runs) ** 0.5))  # mirrors testpanel.noise_band
        self.assertEqual(band(150), 12)
        self.assertEqual(band(30), 26)
        self.assertEqual(band(2000), 3)

    def test_godot_candidates_prefer_console_build(self):
        from cm import godot
        tmp = tempfile.mkdtemp()
        try:
            d = os.path.join(tmp, "Godot_v4.4.1-stable_win64")
            os.makedirs(d)
            for n in ("Godot_v4.4.1-stable_win64.exe", "Godot_v4.4.1-stable_win64_console.exe"):
                open(os.path.join(d, n), "w").close()
            env = {"LOCALAPPDATA": tmp, "PATH": ""}
            c = godot._candidates(env=env, platform="win32")
            self.assertTrue(c and c[0].endswith("_console.exe"), c)
        finally:
            shutil.rmtree(tmp, ignore_errors=True)


if __name__ == "__main__":
    unittest.main()
