"""Regenerate docs/design/TALENTS.md from data/talents.json, skills.json and combos.json.
Run from the repo root:  python3 tools/talent_doc.py"""
import json

T = json.load(open("data/talents.json"))
SK = json.load(open("data/skills.json"))["skills"]
CO = json.load(open("data/combos.json"))["combos"]
GROUPS = [("Wardens", ["Paladin", "Samurai", "Berserker"]), ("Martialists", ["Monk", "Shinobi", "Myrmidon"]),
          ("Menders", ["Druid", "Cleric", "Kannagi"]), ("Sorcerers", ["Elementalist", "Beastmaster", "Necromancer"])]
SIGNATURE = {"Paladin": "sanctified_strike", "Samurai": "decisive_cut", "Berserker": "bloodbath", "Monk": "pressure_break",
             "Myrmidon": "exploit_opening", "Shinobi": "assassinate", "Druid": "bramble_burst", "Cleric": "purge",
             "Kannagi": "exorcism", "Elementalist": "steam_burst", "Beastmaster": "manticores_venom", "Necromancer": "dread"}

def pct(v): return f"{round(v * 100):g}%"

def effect(e):
    c = []
    if "with" in e: c.append(f"with a {e['with'].replace('_', ' ')}")
    if "element" in e: c.append(f"{e['element'].title()}")
    if "elements" in e: c.append("/".join(x.title() for x in e["elements"]))
    if "damage_type" in e: c.append(f"{e['damage_type'].title()} hits")
    if "ability" in e: c.append(f"{e['ability'].lower()} attacks")
    if "target_status" in e: c.append(f"vs {e['target_status'].lower()}")
    if "user_hp_below" in e: c.append(f"below {pct(e['user_hp_below'])} HP")
    if "target_hp_below" in e: c.append(f"vs targets below {pct(e['target_hp_below'])} HP")
    if e.get("weak_spot"): c.append("on weak spots")
    cond = f" ({', '.join(c)})" if c else ""
    t = e["type"]
    if t == "stats":
        return ", ".join((f"+{pct(v)}" if abs(v) < 1 else f"+{v:g}") + " " + k.replace("_", " ").replace("max hp pct", "max HP") for k, v in e["stats"].items())
    if t == "damage": return f"+{pct(e['mult'])} damage{cond}"
    if t == "defense": return f"-{pct(e['reduce'])} damage taken{cond}"
    if t == "heal_bonus": return f"+{pct(e['mult'])} healing"
    if t == "lifesteal": return f"heal {pct(e['fraction'])} of damage dealt{cond}"
    if t == "skill":
        bits = [f"{e[k]:+d} {k.replace('_', ' ')}" for k in ("power", "cooldown", "duration", "mp_cost", "sp_cost") if k in e]
        return f"{e['skill']}: {', '.join(bits)}"
    if t == "combo": return f"{CO[e['combo']]['name']} +{e['bonus']:g}x"
    if t == "status_chance": return f"+{pct(e['chance'])} status chance"
    if t == "regen": return "regen " + ", ".join(f"{pct(e[k])} {k.upper()}" for k in ("hp", "mp", "sp") if e.get(k)) + " per turn"
    return t

def skill_line(name):
    s = SK[name]
    bits = [s.get("category", "").title() or "Skill", f"{s['type'].lower().replace('_', ' ')}", s["target"].lower().replace("_", " ")]
    if s.get("power"): bits.append(f"power {s['power']}")
    cost = s.get("mp_cost") if s["ability_type"] == "MAGICAL" else s.get("sp_cost")
    if cost: bits.append(f"{cost} {'MP' if s['ability_type'] == 'MAGICAL' else 'SP'}")
    if s.get("hp_cost"): bits.append(f"{pct(s['hp_cost'])} max HP")
    bits.append(f"cd {s.get('cooldown', 0)}")
    st = s.get("status_effect") or s.get("status_effects")
    if st and st != "NONE": bits.append("applies " + (", ".join(st) if isinstance(st, list) else st).lower())
    els = s.get("elements") or ([s["element"]] if isinstance(s.get("element"), str) and s["element"] not in ("NONE", "PHYSICAL") else [])
    if els: bits.append("/".join(x.title() for x in els))
    if s.get("damage_type"): bits.append(s["damage_type"].title())
    if s.get("weapon_bonus"): bits.append(", ".join(f"x{v:g} with {k.replace('_', ' ')}" for k, v in s["weapon_bonus"].items()))
    return "; ".join(bits)

s = T["settings"]
out = ["# Talent trees", "",
       "Generated from `data/talents.json` by `tools/talent_doc.py`. Edit the data (content manager **Talents** tab) and re-run.",
       "Engine: `scripts/resources/TalentManager.gd`. Lore: `docs/lore/CLASS_PHILOSOPHIES.md`, `docs/lore/ABILITY_TYPES.md`.", "",
       "## Rules",
       f"- **Points:** {s['points_per_level']} talent point per level from level {s['first_point_level']}.",
       "- **Branches:** each class has 3 branches of 5 tiers.",
       f"  - Points needed in a branch before each tier opens: {s['tier_points']}.",
       "  - Every branch follows the same pattern: tier 1 passive, tier 2 **skill**, tier 3 and 4 passives (one usually upgrades a skill or combo), tier 5 **ultimate**.",
       "- **Passives** have up to 3 ranks; the numbers below are per rank.",
       "- **Skill nodes** add the skill and put it in the loadout if there's room.",
       f"- **Loadout:** {s['loadout_size']} equipped skills are usable in battle. Choose them on the Talents screen (Town → Talents).",
       f"- **Respec:** costs {s['respec_gold_per_level']} copper × level and refunds everything.",
       "- **Players = enemies:** the same engine runs for enemies, which have no talents yet.", "",
       "## New set-up statuses and signature combos",
       "- **Staggered** (−3 Agility, −10% dodge): shield bashes, kicks, charges, war cries.",
       "- **Marked** (no penalty by itself): marks, pins, studying the foe.",
       "- **Sealed** (−3 Intelligence and Mind): Kannagi seals.", "",
       "| Class | Signature combo | Set-up | Payoff | x |", "|---|---|---|---|---|"]
for g, cls_list in GROUPS:
    for cls in cls_list:
        c = CO[SIGNATURE[cls]]
        pay = "; ".join(f"{k.replace('_', ' ')}: {', '.join(v)}" for k, v in c["payoff"].items())
        out.append(f"| {cls} | {c['name']} | {c['setup'].title()} | {pay} | {c['multiplier']} |")
out.append("")
for g, cls_list in GROUPS:
    out += [f"## {g}", ""]
    for cls in cls_list:
        out += [f"### {cls}", ""]
        branches = sorted(T["branches"][cls].items(), key=lambda kv: kv[1]["order"])
        for bid, b in branches:
            out += [f"**{b['name']}**: {b['description']}", "", "| Tier | Node | Ranks | Effect |", "|---|---|---|---|"]
            nodes = sorted(T["nodes"][cls][bid].items(), key=lambda kv: kv[1]["tier"])
            for nid, n in nodes:
                if n.get("skill"):
                    eff = f"**Skill: {n['skill']}** ({skill_line(n['skill'])}). {SK[n['skill']]['description']}"
                else:
                    eff = "; ".join(effect(e) for e in n.get("effects", [])) + f". *{n['description']}*"
                out.append(f"| {n['tier']} | {n['name']} | {n['max_rank']} | {eff} |")
            out.append("")
open("docs/design/TALENTS.md", "w").write("\n".join(out))
print("wrote docs/design/TALENTS.md")
