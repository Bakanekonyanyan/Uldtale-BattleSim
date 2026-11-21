# Source of data/talents.json and the talent skills/statuses/combos. Edit here or in the content manager.
# Re-running only ADDS missing skills/statuses/combos and rewrites data/talents.json.
"""Talent trees, new skills, statuses and combos for all 12 classes.
Run from the repo root:  python3 <this file>
Writes data/talents.json, adds skills to data/skills.json, statuses to
data/status_effects.json, combos to data/combos.json (minimal-diff), and
docs/design/TALENTS.md."""
import json, sys
sys.path.insert(0, "DevTools")
from cm import jsonio
from cm.splice import splice

# ---------------------------------------------------------------- helpers
def stats(**kw): return {"type": "stats", "stats": kw}
def dmg(mult, **c): return dict({"type": "damage", "mult": mult}, **c)
def dfn(reduce, **c): return dict({"type": "defense", "reduce": reduce}, **c)
def heal(mult): return {"type": "heal_bonus", "mult": mult}
def steal(f, **c): return dict({"type": "lifesteal", "fraction": f}, **c)
def smod(skill, **kw): return dict({"type": "skill", "skill": skill}, **kw)
def combo(cid, bonus): return {"type": "combo", "combo": cid, "bonus": bonus}
def schance(c): return {"type": "status_chance", "chance": c}
def regen(**kw): return dict({"type": "regen"}, **kw)

def P(id, name, tier, ranks, desc, *effects):
    return {"id": id, "name": name, "tier": tier, "max_rank": ranks, "description": desc, "effects": list(effects)}

def K(id, tier, skill, desc=""):
    """Node that unlocks an active skill (defined in SKILLS)."""
    return {"id": id, "name": skill["name"], "tier": tier, "max_rank": 1, "description": desc or skill["description"],
            "skill": skill["name"], "_skill_def": skill}

def S(name, desc, ability, typ, target, power, duration, mp, sp, cd, category, **extra):
    d = {"name": name, "description": desc, "ability_type": ability, "type": typ, "target": target, "category": category}
    d.update(extra)
    d.update({"power": power, "duration": duration, "mp_cost": mp, "sp_cost": sp, "cooldown": cd})
    return d

PH, MA = "PHYSICAL", "MAGICAL"
EXISTING = "__existing__"   # marker: node unlocks a skill that already exists in skills.json

def EK(id, tier, name, desc, patch=None):
    """Node that unlocks an existing (previously unused) skill, optionally retuned."""
    return {"id": id, "name": name, "tier": tier, "max_rank": 1, "description": desc, "skill": name,
            "_existing": True, "_patch": patch or {}}

# ---------------------------------------------------------------- classes
T = {}

# ======================= WARDENS =======================
T["Paladin"] = [
 ("bulwark", "Bulwark", "Sword and board: the shield of the party.", [
   P("shield_discipline", "Shield Discipline", 1, 3, "Drilled behind the shield in the Grand Cathedral.",
     stats(toughness=3), dfn(0.02, **{"with": "shield"})),
   K("shield_bash", 2, S("Shield Bash", "Slam your shield into the foe, knocking it off balance.", PH, "DEBUFF", "ENEMY", 25, 2, 0, 15, 2, "BASIC",
       damage_type="BLUNT", attribute_target="AGILITY", status_effect="STAGGERED", weapon_bonus={"shield": 1.3})),
   P("bastion", "Bastion", 3, 3, "Your guard becomes a wall.", dfn(0.04, **{"with": "shield"}), stats(fortitude=1)),
   P("unbreakable", "Unbreakable", 4, 2, "When the line is about to break, you hold.", dfn(0.10, user_hp_below=0.4)),
   K("aegis_of_dawn", 5, S("Aegis of Dawn", "Solara's light hardens into a radiant aegis that heals and turns blows back.", MA, "BUFF", "SELF", 60, 4, 40, 0, 8, "ULTIMATE",
       attribute_targets=["FORTITUDE", "ENDURANCE"], status_effects=["REFLECT", "REGENERATION"])),
 ]),
 ("crusader", "Crusader", "Holy offense; two-handers welcome.", [
   P("righteous_fury", "Righteous Fury", 1, 3, "Your strikes carry the Radiant Dawn.", dmg(0.04, element="HOLY")),
   K("radiant_cleave", 2, S("Radiant Cleave", "A sweeping blow trailing holy light that dazzles every foe.", PH, "DAMAGE", "ALL_ENEMIES", 30, 3, 10, 25, 3, "ADVANCED",
       elements=["HOLY"], status_effect="BLIND", weapon_bonus={"two_handed": 1.2})),
   P("zeal", "Zeal", 3, 3, "Fervor behind a great blade.", dmg(0.05, ability="PHYSICAL", **{"with": "two_handed"})),
   P("sanctified_blows", "Sanctified Blows", 4, 2, "Strike the reeling and the blinded with judgement.", combo("sanctified_strike", 0.15), combo("judgement", 0.1)),
   K("solaras_verdict", 5, S("Solara's Verdict", "Call down the full judgement of the Radiant Dawn on one foe.", MA, "DAMAGE", "ENEMY", 110, 3, 45, 0, 8, "ULTIMATE",
       elements=["HOLY"], status_effect="BLIND")),
 ]),
 ("devotion", "Devotion", "Faith that mends and protects.", [
   P("faithful", "Faithful", 1, 3, "Unwavering faith.", stats(faith=2)),
   K("lay_on_hands", 2, S("Lay on Hands", "Mend an ally's wounds with a touch of Solara's grace.", MA, "HEAL", "ALLY", 45, 0, 25, 0, 3, "BASIC")),
   P("dawns_mercy", "Dawn's Mercy", 3, 3, "Your healing burns brighter.", heal(0.06)),
   P("radiant_aura", "Radiant Aura", 4, 2, "Light lingers around you.", regen(hp=0.02)),
   K("dawns_embrace", 5, S("Dawn's Embrace", "Wrap an ally in the dawn itself: a great heal that keeps on mending.", MA, "HEAL", "ALLY", 120, 3, 50, 0, 8, "ULTIMATE",
       status_effect="REGENERATION")),
 ]),
]

T["Samurai"] = [
 ("iai", "Iai", "The art of the draw: one perfect cut.", [
   P("swift_draw", "Swift Draw", 1, 3, "The blade is out before the eye can follow.", stats(critical_hit_rate=0.03)),
   K("flash_draw", 2, S("Flash Draw", "A lightning-quick draw cut that opens a bleeding wound.", PH, "DAMAGE", "ENEMY", 25, 3, 0, 15, 1, "LINK",
       damage_type="SLASH", status_effect="BLEED", weapon_bonus={"katana": 1.2, "great_katana": 1.2})),
   P("iai_mastery", "Iai Mastery", 3, 3, "Years of drawing the same cut.", smod("Iaido", power=10)),
   P("killing_intent", "Killing Intent", 4, 2, "A wounded foe is a finished foe.", dmg(0.08, damage_type="SLASH", target_status="BLEED")),
   K("thousand_cuts", 5, S("Thousand Cuts", "A storm of draws too fast to see, cutting every foe.", PH, "DAMAGE", "ALL_ENEMIES", 90, 3, 0, 50, 8, "ULTIMATE",
       damage_type="SLASH", status_effect="BLEED", weapon_bonus={"katana": 1.2, "great_katana": 1.2})),
 ]),
 ("bushido", "Bushido", "Discipline and inner spirit.", [
   P("discipline", "Discipline", 1, 3, "Body and mind tempered alike.", stats(endurance=2, mind=2)),
   K("kiai", 2, S("Kiai", "A spirit shout that shakes the enemy's footing.", PH, "DEBUFF", "ALL_ENEMIES", 20, 2, 0, 20, 4, "BASIC",
       attribute_target="AGILITY", status_effect="STAGGERED")),
   P("unshaken", "Unshaken", 3, 3, "Composure in any storm.", stats(toughness=2, spell_ward=2)),
   P("code_of_honor", "Code of Honor", 4, 2, "The creed burns longer.", smod("Bushido", power=10, duration=1)),
   K("spirit_of_amakiri", 5, S("Spirit of Amakiri", "Channel the founder's spirit: speed, strength and a blade no one can touch.", PH, "BUFF", "SELF", 60, 4, 0, 50, 8, "ULTIMATE",
       attribute_targets=["DEXTERITY", "STRENGTH", "AGILITY"], status_effects=["ENRAGED", "EVASIVE"])),
 ]),
 ("kenjutsu", "Kenjutsu", "Reading the opponent; the great katana.", [
   P("blade_form", "Blade Form", 1, 3, "Clean, precise forms.", dmg(0.04, damage_type="SLASH")),
   K("read_the_opponent", 2, S("Read the Opponent", "Study the foe and find the opening for a decisive cut.", PH, "DEBUFF", "ENEMY", 20, 3, 0, 15, 3, "BASIC",
       attribute_target="DEXTERITY", status_effect="MARKED")),
   P("parry", "Parry", 3, 3, "Turn the blade aside.", stats(dodge=0.03)),
   P("decisive_strike", "Decisive Strike", 4, 2, "When the opening comes, end it.", combo("decisive_cut", 0.15)),
   K("heaven_splitter", 5, S("Heaven Splitter", "One overhead cut said to split the sky.", PH, "DAMAGE", "ENEMY", 130, 3, 0, 55, 8, "ULTIMATE",
       damage_type="SLASH", weapon_bonus={"great_katana": 1.25})),
 ]),
]

T["Berserker"] = [
 ("carnage", "Carnage", "Massive weapons, wide arcs.", [
   P("heavy_hands", "Heavy Hands", 1, 3, "The heavier the weapon, the better.", dmg(0.05, **{"with": "two_handed"})),
   K("whirlwind", 2, S("Whirlwind", "Spin with your weapon, battering everything around you.", PH, "DAMAGE", "ALL_ENEMIES", 30, 2, 0, 25, 3, "ADVANCED",
       status_effect="STAGGERED", weapon_bonus={"two_handed": 1.25})),
   P("sundering", "Sundering", 3, 3, "Armor means little to you.", stats(armor_penetration=0.05)),
   P("cleave_mastery", "Cleave Mastery", 4, 2, "Wider, deeper cleaves.", smod("Cleave", power=10)),
   EK("berserker_rage", 5, "Berserker Rage", "Give yourself fully to Arathorn's fury: huge Strength and Endurance and an Enraged frenzy.",
      {"category": "ULTIMATE", "cooldown": 8}),
 ]),
 ("bloodlust", "Bloodlust", "Fenrisulfr's hunger: lifesteal and frenzy.", [
   P("thirst", "Thirst", 1, 3, "Every wound you deal feeds you.", steal(0.03)),
   K("rampage", 2, S("Rampage", "A savage flurry against one foe; devastating on a bleeding target.", PH, "DAMAGE", "ENEMY", 45, 3, 0, 25, 2, "ADVANCED",
       status_effect="BLEED", weapon_bonus={"two_handed": 1.2})),
   P("frenzy", "Frenzy", 3, 3, "Pain makes you stronger.", dmg(0.04, user_hp_below=0.5)),
   P("feast_of_wolves", "Feast of Wolves", 4, 2, "Blood Feast tears deeper.", smod("Blood Feast", power=10)),
   K("fenrisulfrs_maw", 5, S("Fenrisulfr's Maw", "The Wild Father's jaws close on every foe and drink deep.", PH, "DRAIN", "ALL_ENEMIES", 70, 0, 0, 50, 8, "ULTIMATE",
       drain_source="HP", drain_restore="HP", drain_efficiency=0.5, weapon_bonus={"two_handed": 1.2})),
 ]),
 ("war_wolf", "War Wolf", "The tank that will not fall.", [
   P("thick_hide", "Thick Hide", 1, 3, "Scarred and hardened.", stats(max_hp_pct=0.04, toughness=2)),
   K("war_howl", 2, S("War Howl", "Howl like the war wolf; foes lose their nerve and footing.", PH, "DEBUFF", "ALL_ENEMIES", 25, 2, 0, 20, 4, "BASIC",
       attribute_target="STRENGTH", status_effect="STAGGERED")),
   P("iron_will", "Iron Will", 3, 3, "Shrug off blows.", dfn(0.04)),
   P("last_stand", "Last Stand", 4, 2, "Hardest to kill when nearly dead.", dfn(0.12, user_hp_below=0.3)),
   K("second_wind", 5, S("Second Wind", "Rise again from the brink with a roar.", PH, "HEAL", "SELF", 100, 3, 0, 40, 8, "ULTIMATE",
       status_effect="REGENERATION")),
 ]),
]

# ======================= MARTIALISTS =======================
T["Monk"] = [
 ("tiger", "Tiger", "Power: the tiger's ferocity.", [
   P("tigers_strength", "Tiger's Strength", 1, 3, "Muscle like coiled springs.", stats(strength=2), dmg(0.03, ability="PHYSICAL")),
   K("ox_kick", 2, S("Ox Kick", "A low, heavy kick that takes the legs out from under the foe.", PH, "DEBUFF", "ENEMY", 25, 2, 0, 15, 2, "BASIC",
       damage_type="BLUNT", attribute_target="AGILITY", status_effect="STAGGERED")),
   P("ferocity", "Ferocity", 3, 3, "Strike where it hurts.", stats(critical_hit_rate=0.03)),
   P("rending_claws", "Rending Claws", 4, 2, "Tiger Claw tears deeper.", smod("Tiger Claw", power=10)),
   K("five_animal_fury", 5, S("Five Animal Fury", "Tiger, crane, mantis, ox and serpent in one devastating sequence.", PH, "DAMAGE", "ENEMY", 120, 3, 0, 50, 8, "ULTIMATE",
       damage_type="BLUNT", status_effect="BLEED")),
 ]),
 ("crane", "Crane", "Grace: balance, evasion and counters.", [
   P("cranes_grace", "Crane's Grace", 1, 3, "Light as a feather.", stats(agility=2, dodge=0.02)),
   K("crane_wing_sweep", 2, S("Crane Wing Sweep", "Sweeping wing strikes that spin every foe around.", PH, "DAMAGE", "ALL_ENEMIES", 25, 2, 0, 20, 3, "ADVANCED",
       damage_type="BLUNT", elements=["WIND"], status_effect="CONFUSED")),
   P("flowing_water", "Flowing Water", 3, 3, "Move like water around the blow.", stats(dodge=0.02, accuracy=0.02)),
   P("counterflow", "Counterflow", 4, 2, "Punish the off-balance.", dmg(0.10, target_status="CONFUSED")),
   K("heavenly_crane", 5, S("Heavenly Crane", "Become untouchable: soaring agility and a body that mends itself.", PH, "BUFF", "SELF", 60, 4, 0, 40, 8, "ULTIMATE",
       attribute_targets=["AGILITY", "DEXTERITY"], status_effects=["EVASIVE", "REGENERATION"])),
 ]),
 ("verdant_heart", "Verdant Heart", "Harmony with Elandria, Nimue and Fenrisulfr.", [
   P("inner_harmony", "Inner Harmony", 1, 3, "Breath and body in balance.", regen(hp=0.01, sp=0.02)),
   K("earth_mothers_palm", 2, S("Earth Mother's Palm", "A palm strike carrying Elandria's weight; it can shatter what is frozen.", PH, "DAMAGE", "ENEMY", 35, 3, 0, 20, 2, "BASIC",
       damage_type="BLUNT", elements=["EARTH"], status_effect="POISON")),
   P("spirit_weave", "Spirit Weave", 3, 3, "Nimue's flow guards the mind.", stats(mind=2, spell_ward=2)),
   P("balance", "Balance", 4, 2, "Mantis Strike lands truer.", smod("Mantis Strike", power=10)),
   K("nimues_tide", 5, S("Nimue's Tide", "Let the Spirit Weaver's tide wash through you, healing deep wounds.", MA, "HEAL", "SELF", 100, 3, 30, 0, 8, "ULTIMATE",
       elements=["WATER"], status_effect="REGENERATION")),
 ]),
]

T["Myrmidon"] = [
 ("arms_master", "Arms Master", "Every weapon, used well.", [
   P("weapon_training", "Weapon Training", 1, 3, "Iron Gauntlet drills.", dmg(0.04, ability="PHYSICAL")),
   K("disarming_strike", 2, S("Disarming Strike", "Knock the foe's weapon aside and leave it reeling.", PH, "DEBUFF", "ENEMY", 25, 2, 0, 15, 2, "BASIC",
       attribute_target="STRENGTH", status_effect="STAGGERED")),
   P("exploit_weakness", "Exploit Weakness", 3, 3, "Switch to whatever hurts most.", dmg(0.06, weak_spot=True)),
   P("opportunist", "Opportunist", 4, 2, "Never waste an opening.", combo("exploit_opening", 0.15)),
   K("blade_storm", 5, S("Blade Storm", "A whirlwind of steel that cuts through every foe.", PH, "DAMAGE", "ALL_ENEMIES", 80, 3, 0, 50, 8, "ULTIMATE",
       status_effect="BLEED")),
 ]),
 ("skirmisher", "Skirmisher", "Two blades and quick feet.", [
   P("light_feet", "Light Feet", 1, 3, "Never where they swing.", stats(agility=1, dodge=0.02)),
   K("twin_fangs", 2, S("Twin Fangs", "Two quick thrusts that link into your next move.", PH, "DAMAGE", "ENEMY", 30, 3, 0, 20, 1, "LINK",
       damage_type="PIERCE", status_effect="BLEED")),
   P("ambidextrous", "Ambidextrous", 3, 3, "Light weapons, fast hands.", dmg(0.04, **{"with": "one_handed"})),
   P("backstab_mastery", "Backstab Mastery", 4, 2, "From the shadows, deeper.", smod("Backstab", power=12)),
   K("hundred_blades", 5, S("Hundred Blades", "An unbroken torrent of strikes on one foe.", PH, "DAMAGE", "ENEMY", 120, 3, 0, 55, 8, "ULTIMATE",
       damage_type="PIERCE", status_effect="BLEED")),
 ]),
 ("mercenary", "Mercenary", "Professional grit and dirty tricks.", [
   P("battle_hardened", "Battle Hardened", 1, 3, "Countless contracts survived.", stats(vitality=2, endurance=2, max_hp_pct=0.02)),
   K("pinning_thrust", 2, S("Pinning Thrust", "Pin the target in place and mark it for the kill.", PH, "DEBUFF", "ENEMY", 20, 3, 0, 15, 3, "BASIC",
       damage_type="PIERCE", attribute_target="AGILITY", status_effect="MARKED")),
   P("toxic_expertise", "Toxic Expertise", 3, 3, "Your poisons, your rules.", dmg(0.05, target_status="POISON")),
   P("contract_killer", "Contract Killer", 4, 2, "The mark never escapes.", dmg(0.10, target_status="MARKED")),
   K("iron_gauntlet", 5, S("Iron Gauntlet", "The guild's creed made flesh: strength, precision and resolve.", PH, "BUFF", "SELF", 60, 4, 0, 40, 8, "ULTIMATE",
       attribute_targets=["STRENGTH", "DEXTERITY", "FORTITUDE"], status_effect="ENRAGED")),
 ]),
]

T["Shinobi"] = [
 ("kage", "Kage", "Shadow arts and assassination.", [
   P("silent_steps", "Silent Steps", 1, 3, "Unheard, unseen.", stats(dodge=0.02, critical_hit_rate=0.02)),
   K("shadow_mark", 2, S("Shadow Mark", "Brand the target with Tsukuyomi's shadow; it cannot hide from you.", PH, "DEBUFF", "ENEMY", 20, 3, 0, 15, 3, "BASIC",
       elements=["DARK"], attribute_target="FORTITUDE", status_effect="MARKED")),
   P("lethality", "Lethality", 3, 3, "Every thrust finds a vital point.", dmg(0.05, damage_type="PIERCE")),
   P("assassin", "Assassin", 4, 2, "The marked die quickly.", combo("assassinate", 0.15)),
   K("moonless_night", 5, S("Moonless Night", "Vanish into darkness and strike once, perfectly.", PH, "DAMAGE", "ENEMY", 130, 3, 0, 50, 8, "ULTIMATE",
       damage_type="PIERCE", elements=["DARK"])),
 ]),
 ("ninjutsu", "Ninjutsu", "Fire, water and lightning techniques.", [
   P("chakra_flow", "Chakra Flow", 1, 3, "Energy guided through the seals.", stats(intelligence=2, spell_power=2)),
   K("phoenix_flower", 2, S("Phoenix Flower", "Fire release: a spray of burning flowers.", MA, "DAMAGE", "ALL_ENEMIES", 30, 3, 25, 0, 3, "ADVANCED",
       elements=["FIRE"], status_effect="BURN")),
   P("elemental_affinity", "Elemental Affinity", 3, 3, "Your elements answer faster.", dmg(0.05, elements=["FIRE", "WATER", "LIGHTNING"])),
   P("conductor", "Conductor", 4, 2, "Water and lightning, perfected.", combo("conduction", 0.15)),
   K("raijins_descent", 5, S("Raijin's Descent", "Lightning release: the storm god's strike falls on every foe.", MA, "DAMAGE", "ALL_ENEMIES", 85, 3, 50, 0, 8, "ULTIMATE",
       elements=["LIGHTNING"], status_effect="SHOCK")),
 ]),
 ("tools", "Shinobi Tools", "Kunai, shuriken and smoke.", [
   P("quick_hands", "Quick Hands", 1, 3, "Throw faster, tire less.", smod("Lightning Kunai", power=5, sp_cost=-2)),
   K("shuriken_storm", 2, S("Shuriken Storm", "A fan of shuriken across every foe.", PH, "DAMAGE", "ALL_ENEMIES", 20, 3, 0, 15, 2, "BASIC",
       damage_type="PIERCE", status_effect="BLEED")),
   P("vanishing", "Vanishing", 3, 3, "Gone before the blow lands.", stats(dodge=0.03)),
   P("poisoned_tools", "Poisoned Tools", 4, 2, "Everything you throw carries something nasty.", schance(0.10)),
   K("shadow_clone", 5, S("Shadow Clone", "Split into shadow clones; foes strike the wrong you.", PH, "BUFF", "SELF", 60, 4, 0, 40, 8, "ULTIMATE",
       attribute_targets=["AGILITY", "DEXTERITY"], status_effects=["EVASIVE", "REFLECT"])),
 ]),
]

# ======================= MENDERS =======================
T["Druid"] = [
 ("bear", "Bear Form", "Elandria's bear: raw strength and resilience.", [
   P("ursine_hide", "Ursine Hide", 1, 3, "Thick fur and thicker skin.", stats(max_hp_pct=0.03, toughness=3)),
   K("bear_form", 2, S("Bear Form", "Take the shape of a great bear: stronger, tougher, harder to kill.", PH, "BUFF", "SELF", 40, 5, 0, 20, 6, "ADVANCED",
       attribute_targets=["STRENGTH", "FORTITUDE", "VITALITY"])),
   P("maul", "Maul", 3, 3, "Claws and crushing paws.", dmg(0.05, ability="PHYSICAL")),
   P("thick_fur", "Thick Fur", 4, 2, "Blows sink into fur.", dfn(0.06)),
   K("elder_bear", 5, S("Elder Bear", "Become the elder bear and crash into every foe.", PH, "DAMAGE", "ALL_ENEMIES", 80, 2, 0, 45, 8, "ULTIMATE",
       damage_type="BLUNT", elements=["EARTH"], status_effect="STAGGERED")),
 ]),
 ("alraune", "Alraune", "The flower spirit: healing and control.", [
   P("verdant_bloom", "Verdant Bloom", 1, 3, "Growth answers your call.", heal(0.06)),
   K("alraunes_kiss", 2, S("Alraune's Kiss", "A blossom's kiss that heals and keeps healing.", MA, "HEAL", "ALLY", 40, 3, 25, 0, 3, "BASIC",
       status_effect="REGENERATION")),
   P("thorned_vines", "Thorned Vines", 3, 3, "The earth bites back.", dmg(0.05, element="EARTH")),
   P("strangling_roots", "Strangling Roots", 4, 2, "Poisoned prey wither faster.", dmg(0.10, target_status="POISON")),
   K("garden_of_elandria", 5, S("Garden of Elandria", "Raise a living garden that heals and shields.", MA, "HEAL", "ALLY", 110, 3, 50, 0, 8, "ULTIMATE",
       status_effects=["REGENERATION", "REFLECT"])),
 ]),
 ("wildcaller", "Wildcaller", "Storms, frost and thorns of the wild.", [
   P("storm_kin", "Storm Kin", 1, 3, "Wind and frost obey you.", dmg(0.04, elements=["ICE", "WIND"])),
   K("bramble_lash", 2, S("Bramble Lash", "Whip the foe with thorned brambles that leave it bleeding.", MA, "DAMAGE", "ENEMY", 35, 3, 20, 0, 2, "BASIC",
       elements=["EARTH"], status_effect="BLEED")),
   P("natures_grasp", "Nature's Grasp", 3, 3, "Your effects take hold more often.", schance(0.05)),
   P("arctic_mastery", "Arctic Mastery", 4, 2, "Arctic Blast bites harder.", smod("Arctic Blast", power=10)),
   K("wrath_of_the_wild", 5, S("Wrath of the Wild", "A howling blizzard sweeps the battlefield.", MA, "DAMAGE", "ALL_ENEMIES", 85, 3, 50, 0, 8, "ULTIMATE",
       elements=["WIND", "ICE"], status_effect="FREEZE")),
 ]),
]

T["Cleric"] = [
 ("battle_priest", "Battle Priest", "Mace, mail and divine wrath.", [
   P("holy_might", "Holy Might", 1, 3, "Faith in your arm.", stats(strength=2), dmg(0.03, ability="PHYSICAL")),
   K("hammer_of_dawn", 2, S("Hammer of Dawn", "A blessed blow that rocks the foe on its feet.", PH, "DAMAGE", "ENEMY", 35, 2, 10, 20, 2, "BASIC",
       damage_type="BLUNT", elements=["HOLY"], status_effect="STAGGERED", weapon_bonus={"mace": 1.2})),
   P("crushing_faith", "Crushing Faith", 3, 3, "The mace is a prayer.", dmg(0.05, damage_type="BLUNT")),
   P("smite_mastery", "Smite Mastery", 4, 2, "Smite strikes harder.", smod("Smite", power=10)),
   K("solaras_hammer", 5, S("Solara's Hammer", "Bring down the Radiant Dawn's hammer on one foe.", PH, "DAMAGE", "ENEMY", 120, 2, 20, 40, 8, "ULTIMATE",
       damage_type="BLUNT", elements=["HOLY"], status_effect="STAGGERED")),
 ]),
 ("restoration", "Restoration", "Healing that can mend the gravest wound.", [
   P("healing_hands", "Healing Hands", 1, 3, "Your prayers mend more.", heal(0.06)),
   EK("divine_blessing", 2, "Divine Blessing", "Bless an ally: Fortitude and Endurance up and steady regeneration."),
   P("devout", "Devout", 3, 3, "Deep, constant prayer.", stats(faith=2, mind=2)),
   P("blessed_light", "Blessed Light", 4, 2, "Healing Light shines brighter.", smod("Healing Light", power=10)),
   K("miracle", 5, S("Miracle", "A true miracle of the Dawn: an enormous heal.", MA, "HEAL", "ALLY", 150, 0, 50, 0, 8, "ULTIMATE")),
 ]),
 ("inquisitor", "Inquisitor", "Purging fire and judgement.", [
   P("zeal_of_dawn", "Zeal of the Dawn", 1, 3, "Holy wrath burns hotter.", dmg(0.04, element="HOLY")),
   K("purifying_flame", 2, S("Purifying Flame", "Holy fire that sears the unclean.", MA, "DAMAGE", "ENEMY", 35, 3, 25, 0, 3, "ADVANCED",
       elements=["HOLY", "FIRE"], status_effect="BURN")),
   P("judgement_mastery", "Judgement Mastery", 3, 3, "The blinded and burning are judged harder.", combo("judgement", 0.1), combo("purge", 0.1)),
   P("heretic_bane", "Heretic Bane", 4, 2, "The burning heretic falls.", dmg(0.10, target_status="BURN")),
   K("dawnfire", 5, S("Dawnfire", "The sky ignites with the first light: holy fire on every foe.", MA, "DAMAGE", "ALL_ENEMIES", 85, 3, 50, 0, 8, "ULTIMATE",
       elements=["HOLY", "FIRE"], status_effect="BLIND")),
 ]),
]

T["Kannagi"] = [
 ("barrier_arts", "Barrier Arts", "Seals and wards of the Ancient Ones.", [
   P("warding", "Warding", 1, 3, "Symbols of protection.", stats(spell_ward=3, toughness=2)),
   K("sacred_seal", 2, S("Sacred Seal", "Press an ofuda seal onto the foe, binding its spirit.", MA, "DEBUFF", "ENEMY", 20, 3, 20, 0, 3, "BASIC",
       attribute_target="INTELLIGENCE", status_effect="SEALED")),
   P("barrier_mastery", "Barrier Mastery", 3, 3, "Spirit Barrier grows stronger.", smod("Spirit Barrier", power=10)),
   P("sanctuary", "Sanctuary", 4, 2, "Sacred ground beneath you.", dfn(0.05)),
   K("torii_of_the_ancients", 5, S("Torii of the Ancients", "Raise a gate of the Ancient Ones over an ally: warded, healing, reflecting.", MA, "BUFF", "ALLY", 70, 4, 45, 0, 8, "ULTIMATE",
       attribute_targets=["FORTITUDE", "ENDURANCE", "MIND"], status_effects=["REFLECT", "REGENERATION"])),
 ]),
 ("ancestral_spirits", "Ancestral Spirits", "Healing, mana and stamina.", [
   P("spirit_well", "Spirit Well", 1, 3, "The spirits refill you.", regen(mp=0.03, sp=0.02)),
   EK("spirit_exchange", 2, "Stamina Conversion", "Draw the foe's stamina and turn it into your mana.", {"category": "LINK"}),
   P("ancestral_blessing", "Ancestral Blessing", 3, 3, "The ancestors mend through you.", heal(0.06)),
   P("mending_mastery", "Mending Mastery", 4, 2, "Ancestral Mending heals more.", smod("Ancestral Mending", power=10)),
   K("communion", 5, S("Communion", "Commune with the Ancient Ones; their power floods an ally with life.", MA, "HEAL", "ALLY", 120, 3, 50, 0, 8, "ULTIMATE",
       status_effect="REGENERATION")),
 ]),
 ("kotodama", "Kotodama", "Words of power older than the gods.", [
   P("primal_voice", "Primal Voice", 1, 3, "Your words carry weight.", stats(arcane=2), dmg(0.03, ability="MAGICAL")),
   K("spirit_lance", 2, S("Spirit Lance", "A spear of pure spirit, unbound by element.", MA, "DAMAGE", "ENEMY", 40, 0, 20, 0, 2, "BASIC")),
   P("exorcist", "Exorcist", 3, 3, "Sealed spirits break apart.", combo("exorcism", 0.1)),
   P("wrath_mastery", "Wrath Mastery", 4, 2, "Wrath of the Ancients grows.", smod("Wrath of the Ancients", power=10)),
   K("voice_of_nyxara", 5, S("Voice of Nyxara", "Speak a word from before creation; every foe reels.", MA, "DAMAGE", "ALL_ENEMIES", 95, 2, 50, 0, 8, "ULTIMATE",
       status_effect="CONFUSED")),
 ]),
]

# ======================= SORCERERS =======================
T["Elementalist"] = [
 ("conflux", "Conflux", "Fire and ice, the classic contradiction.", [
   P("searing_mind", "Searing Mind", 1, 3, "Heat and cold both answer.", dmg(0.04, elements=["FIRE", "ICE"])),
   K("glacial_prison", 2, S("Glacial Prison", "Encase the foe in ice.", MA, "DEBUFF", "ENEMY", 20, 2, 20, 0, 3, "BASIC",
       elements=["ICE"], attribute_target="AGILITY", status_effect="FREEZE")),
   P("thermodynamics", "Thermodynamics", 3, 3, "Exploit every temperature shock.", combo("thermal_shock", 0.1), combo("steam_burst", 0.1)),
   P("spear_mastery", "Spear Mastery", 4, 2, "Blazing Ice Spear grows.", smod("Blazing Ice Spear", power=10)),
   K("meteor", 5, S("Meteor", "Pull a burning star down on every foe.", MA, "DAMAGE", "ALL_ENEMIES", 95, 3, 55, 0, 8, "ULTIMATE",
       elements=["FIRE", "EARTH"], status_effect="BURN")),
 ]),
 ("stormcalling", "Stormcalling", "Water, wind and lightning.", [
   P("static_mind", "Static Mind", 1, 3, "The storm hums in you.", dmg(0.04, elements=["LIGHTNING", "WATER", "WIND"])),
   K("tidal_wave", 2, S("Tidal Wave", "A wave crashes over every foe and leaves them drenched.", MA, "DEBUFF", "ALL_ENEMIES", 20, 3, 25, 0, 4, "ADVANCED",
       elements=["WATER"], attribute_target="AGILITY", status_effect="SOAKED")),
   P("conduction_mastery", "Conduction Mastery", 3, 3, "Lightning through water.", combo("conduction", 0.1), combo("overload", 0.1)),
   P("storm_mastery", "Storm Mastery", 4, 2, "Volcanic Thunder Storm grows.", smod("Volcanic Thunder Storm", power=10)),
   K("tempest", 5, S("Tempest", "A living storm of wind and lightning.", MA, "DAMAGE", "ALL_ENEMIES", 95, 3, 55, 0, 8, "ULTIMATE",
       elements=["LIGHTNING", "WIND"], status_effect="SHOCK")),
 ]),
 ("fifth_element", "The Fifth Element", "Conversion of the four, toward Aether.", [
   P("arcane_study", "Arcane Study", 1, 3, "Endless study in the tower.", stats(intelligence=2, arcane=2)),
   K("elemental_convergence", 2, S("Elemental Convergence", "Fire, ice, lightning and earth fused in one bolt; it answers any combo.", MA, "DAMAGE", "ENEMY", 35, 0, 30, 0, 3, "ADVANCED",
       elements=["FIRE", "ICE", "LIGHTNING", "EARTH"])),
   P("overflowing_mana", "Overflowing Mana", 3, 3, "Mana wells up unbidden.", regen(mp=0.03)),
   P("eccentric_genius", "Eccentric Genius", 4, 2, "Brilliant, chaotic, effective.", stats(critical_hit_rate=0.05)),
   K("aether_nova", 5, S("Aether Nova", "A glimpse of the fifth element: pure Aether, beyond any resistance.", MA, "DAMAGE", "ALL_ENEMIES", 110, 0, 60, 0, 8, "ULTIMATE")),
 ]),
]

T["Beastmaster"] = [
 ("predator", "Predator", "Pacts with Fenrisulfr and the Manticore.", [
   P("feral_strength", "Feral Strength", 1, 3, "Borrowed claws, borrowed fury.", dmg(0.04, ability="PHYSICAL"), stats(arcane=1)),
   K("hunters_mark", 2, S("Hunter's Mark", "Mark your prey; the pack will not lose it.", PH, "DEBUFF", "ENEMY", 20, 3, 0, 15, 3, "BASIC",
       attribute_target="AGILITY", status_effect="MARKED")),
   P("venom_glands", "Venom Glands", 3, 3, "Poisoned prey weakens fast.", dmg(0.05, target_status="POISON")),
   P("manticore_fury", "Manticore Fury", 4, 2, "Manticore Sting, deeper.", smod("Manticore Sting", power=10), combo("manticores_venom", 0.1)),
   K("call_of_fenrisulfr", 5, S("Call of Fenrisulfr", "The Wild Father answers: spectral wolves tear through every foe.", PH, "DAMAGE", "ALL_ENEMIES", 90, 3, 0, 50, 8, "ULTIMATE",
       damage_type="SLASH", status_effect="BLEED")),
 ]),
 ("behemoth", "Behemoth", "The Behemoth's endurance.", [
   P("behemoth_blood", "Behemoth Blood", 1, 3, "Its blood in your veins.", stats(vitality=2, fortitude=2, max_hp_pct=0.02)),
   K("behemoth_charge", 2, S("Behemoth Charge", "Charge with the Behemoth's weight and bowl the foe over.", PH, "DEBUFF", "ENEMY", 25, 2, 0, 20, 3, "BASIC",
       damage_type="BLUNT", attribute_target="STRENGTH", status_effect="STAGGERED")),
   P("stone_skin", "Stone Skin", 3, 3, "Hide like rock.", dfn(0.04)),
   P("hide_mastery", "Hide Mastery", 4, 2, "Behemoth Hide grows thicker.", smod("Behemoth Hide", power=10)),
   K("earthshaker", 5, S("Earthshaker", "The Behemoth stamps; the ground breaks under every foe.", PH, "DAMAGE", "ALL_ENEMIES", 85, 2, 0, 50, 8, "ULTIMATE",
       damage_type="BLUNT", elements=["EARTH"], status_effect="STAGGERED")),
 ]),
 ("roc", "Roc", "The Roc's speed and the open sky.", [
   P("rocs_wings", "Roc's Wings", 1, 3, "Lighter than air.", stats(agility=2, dodge=0.02)),
   K("roc_dive", 2, S("Roc Dive", "Plunge from above with talons first.", PH, "DAMAGE", "ENEMY", 35, 3, 0, 20, 2, "BASIC",
       damage_type="PIERCE", elements=["WIND"])),
   P("tailwind", "Tailwind", 3, 3, "Strike first, strike true.", stats(critical_hit_rate=0.03)),
   P("sky_hunter", "Sky Hunter", 4, 2, "Marked prey can't escape the sky.", dmg(0.10, target_status="MARKED")),
   K("storm_of_feathers", 5, S("Storm of Feathers", "The Roc's wings whip up a storm of razor feathers.", PH, "DAMAGE", "ALL_ENEMIES", 85, 2, 0, 50, 8, "ULTIMATE",
       damage_type="PIERCE", elements=["WIND"], status_effect="CONFUSED")),
 ]),
]

T["Necromancer"] = [
 ("curses", "Curses", "Hel's maledictions.", [
   P("malediction", "Malediction", 1, 3, "Darkness answers you.", dmg(0.04, element="DARK")),
   EK("crippling_hex", 2, "Crippling Hex", "Wither Strength, Agility and Fortitude and blind the foe.", {"category": "ADVANCED"}),
   P("lingering_curse", "Lingering Curse", 3, 3, "Curse of Weakness bites deeper.", smod("Curse of Weakness", power=8)),
   P("blight_mastery", "Blight Mastery", 4, 2, "Poison and shadow, perfected.", combo("blight", 0.15), combo("dread", 0.1)),
   K("hels_decree", 5, S("Hel's Decree", "The Shadow Keeper's decree: every foe weakens and rots.", MA, "DEBUFF", "ALL_ENEMIES", 60, 4, 50, 0, 8, "ULTIMATE",
       elements=["DARK"], attribute_targets=["STRENGTH", "INTELLIGENCE", "AGILITY"], status_effect="POISON")),
 ]),
 ("life_drinker", "Life Drinker", "Your own life, and others', as fuel.", [
   P("dark_pact", "Dark Pact", 1, 3, "Stolen life sustains you.", steal(0.03)),
   K("blood_rite", 2, S("Blood Rite", "Pay with your own blood for a devastating bolt of shadow.", MA, "DAMAGE", "ENEMY", 55, 0, 5, 0, 2, "ADVANCED",
       elements=["DARK"], hp_cost=0.08)),
   P("sanguine", "Sanguine", 3, 3, "Life Tap drinks deeper.", smod("Life Tap", power=8)),
   P("undying", "Undying", 4, 2, "Death keeps letting you go.", dfn(0.10, user_hp_below=0.3)),
   EK("perfect_drain", 5, "Perfect Drain", "Tear the life from a foe and take all of it for yourself.", {"category": "ULTIMATE", "power": 100, "cooldown": 8}),
 ]),
 ("gravecaller", "Gravecaller", "Bone and the cold of the grave.", [
   P("deaths_embrace", "Death's Embrace", 1, 3, "The grave's patience.", stats(intelligence=2, mind=2)),
   K("bone_spear", 2, S("Bone Spear", "A lance of bone that tears and bleeds.", MA, "DAMAGE", "ENEMY", 40, 3, 20, 0, 2, "BASIC",
       elements=["DARK"], status_effect="BLEED")),
   P("grave_chill", "Grave Chill", 3, 3, "The cold of the grave.", dmg(0.04, elements=["ICE", "DARK"])),
   P("reaper", "Reaper", 4, 2, "Finish the dying.", dmg(0.12, target_hp_below=0.3)),
   K("danse_macabre", 5, S("Danse Macabre", "The dead rise and dance through the enemy ranks.", MA, "DAMAGE", "ALL_ENEMIES", 95, 2, 55, 0, 8, "ULTIMATE",
       elements=["DARK"], status_effect="CONFUSED")),
 ]),
]

# ---------------------------------------------------------------- statuses & combos
STATUSES = {
 "STAGGERED": {"damage_type": "none", "stat_modifiers": {"agility": -3}, "dodge_reduction": 0.1, "message": "{name} is staggered and off balance"},
 "MARKED": {"damage_type": "none", "message": "{name} is marked"},
 "SEALED": {"damage_type": "none", "stat_modifiers": {"intelligence": -3, "mind": -3}, "message": "{name}'s spirit is sealed"},
}
COMBOS = {
 "sanctified_strike": ("Sanctified Strike", "Holy light strikes a staggered foe.", "STAGGERED", {"elements": ["HOLY"]}, 1.35),
 "pressure_break": ("Pressure Break", "A heavy blow on a staggered foe breaks its stance.", "STAGGERED", {"damage_types": ["BLUNT"]}, 1.35),
 "exploit_opening": ("Exploit Opening", "A blade through the opening a staggered foe leaves.", "STAGGERED", {"damage_types": ["SLASH", "PIERCE"]}, 1.3),
 "decisive_cut": ("Decisive Cut", "The cut you have been waiting for.", "MARKED", {"damage_types": ["SLASH"]}, 1.4),
 "assassinate": ("Assassinate", "A blade to the vital point of a marked target.", "MARKED", {"damage_types": ["PIERCE"]}, 1.45),
 "bloodbath": ("Bloodbath", "Rampage tears a bleeding foe apart.", "BLEED", {"skills": ["Rampage", "Fenrisulfr's Maw"]}, 1.5),
 "bramble_burst": ("Bramble Burst", "Thorns burst through open wounds.", "BLEED", {"elements": ["EARTH"]}, 1.3),
 "purge": ("Purge", "Holy light purifies the burning.", "BURN", {"elements": ["HOLY"]}, 1.3),
 "exorcism": ("Exorcism", "Magic tears a sealed spirit apart.", "SEALED", {"ability_types": ["MAGICAL"]}, 1.35),
 "steam_burst": ("Steam Burst", "Fire flashes the water on a soaked foe into scalding steam.", "SOAKED", {"elements": ["FIRE"]}, 1.35),
 "manticores_venom": ("Manticore's Venom", "Claws rake through venom-weakened flesh.", "POISON", {"damage_types": ["SLASH"]}, 1.35),
 "dread": ("Dread", "Shadow takes the blinded.", "BLIND", {"elements": ["DARK"]}, 1.3),
}
SIGNATURE = {  # class -> its signature combo(s), for the doc
 "Paladin": ["sanctified_strike"], "Samurai": ["decisive_cut"], "Berserker": ["bloodbath"], "Monk": ["pressure_break"],
 "Myrmidon": ["exploit_opening"], "Shinobi": ["assassinate"], "Druid": ["bramble_burst"], "Cleric": ["purge"],
 "Kannagi": ["exorcism"], "Elementalist": ["steam_burst"], "Beastmaster": ["manticores_venom"], "Necromancer": ["dread"],
}

# ---------------------------------------------------------------- write
def update(path, fn):
    t = open(path, encoding="utf-8").read()
    d = json.loads(t)
    fn(d)
    o = splice(t, d, jsonio.detect_indent(t))
    assert o is not None, path
    open(path, "w", encoding="utf-8").write(o)

def main():
    new_skills, patches = {}, {}
    talents = {
        "_doc": "Talent trees (TalentManager.gd, docs/design/TALENTS.md). 1 point per level from first_point_level; a tier-T node needs tier_points[T-1] points spent in its branch; nodes with 'skill' unlock that skill; effects are per rank.",
        "settings": {"points_per_level": 1, "first_point_level": 2, "tier_points": [0, 2, 4, 6, 8], "respec_gold_per_level": 100, "loadout_size": 6},
        "branches": {}, "nodes": {},
    }
    for cls, branches in T.items():
        assert len(branches) == 3, cls
        talents["branches"][cls] = {}
        talents["nodes"][cls] = {}
        for order, (bid, bname, bdesc, nodes) in enumerate(branches):
            talents["branches"][cls][bid] = {"name": bname, "description": bdesc, "order": order}
            talents["nodes"][cls][bid] = {}
            assert sorted(n["tier"] for n in nodes) == [1, 2, 3, 4, 5], (cls, bid)
            for n in nodes:
                n = dict(n)
                if "_skill_def" in n:
                    sd = n.pop("_skill_def")
                    new_skills[sd["name"]] = sd
                if n.pop("_existing", False):
                    patches[n["skill"]] = n.pop("_patch")
                nid = n.pop("id")
                if not n.get("effects"):
                    n.pop("effects", None)
                talents["nodes"][cls][bid][nid] = n
    with open("data/talents.json", "w", encoding="utf-8") as f:
        f.write(jsonio.dumps(talents, "\t") + "\n")

    def add_skills(d):
        for name, s in new_skills.items():
            assert name not in d["skills"], name
            d["skills"][name] = s
        for name, p in patches.items():
            assert name in d["skills"], name
            d["skills"][name].update(p)
    update("data/skills.json", add_skills)

    def add_status(d):
        for k, v in STATUSES.items():
            d.setdefault(k, v)
    update("data/status_effects.json", add_status)

    def add_combos(d):
        for cid, (name, desc, setup, payoff, mult) in COMBOS.items():
            d["combos"].setdefault(cid, {"name": name, "description": desc, "setup": setup, "payoff": payoff, "multiplier": mult, "consume": True})
    update("data/combos.json", add_combos)
    print(f"{len(T)} classes, {sum(len(n) for b in T.values() for _, _, _, n in b)} nodes, {len(new_skills)} new skills, {len(patches)} reused skills")

if __name__ == "__main__":
    main()
