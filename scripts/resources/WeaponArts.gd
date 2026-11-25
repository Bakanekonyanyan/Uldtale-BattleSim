# res://scripts/resources/WeaponArts.gd
# Weapon arts (data/weapon_arts.json; LIVING_WORLD.md J). Using a weapon builds
# proficiency in its family (summed over the family's items); family levels
# unlock the family's two arts, and a class's signature art for its specialty
# family (the Myrmidon has one per family). Arts are skills (category ART) that
# need a weapon of their family in hand (Skill.weapon_family).
class_name WeaponArts
extends RefCounted

static func cfg() -> Dictionary:
	var d = DataRegistry.get_data("weapon_arts")
	return d if d is Dictionary else {}

## Family of an item id ("short_sword" -> "sword"), or "".
static func family_of(item_key: String) -> String:
	var fams: Dictionary = cfg().get("families", {})
	for f in fams:
		if item_key in fams[f].get("items", []):
			return f
	return ""

## Families of what `c` holds right now (main and off hand).
static func held_families(c: CharacterData) -> Array:
	var out: Array = []
	if c == null:
		return out
	for slot in ["main_hand", "off_hand"]:
		var it = c.equipment.get(slot)
		if it is Equipment:
			var f = family_of(String(it.key))
			if f != "" and not f in out:
				out.append(f)
	return out

## Family proficiency: uses summed over its items, as a level (1-6).
static func family_uses(c: CharacterData, fam: String) -> int:
	if c == null or c.proficiency_manager == null:
		return 0
	var u := 0
	for k in cfg().get("families", {}).get(fam, {}).get("items", []):
		u += c.proficiency_manager.get_weapon_proficiency_uses(String(k))
	return u

static func level_for_uses(uses: int) -> int:
	var lv := 1
	for t in ProficiencyManager.LEVEL_THRESHOLDS:
		if uses >= int(t):
			lv += 1
	return min(lv, ProficiencyManager.MAX_LEVEL)

static func family_level(c: CharacterData, fam: String) -> int:
	return level_for_uses(family_uses(c, fam))

## Arts `c` qualifies for: [{skill, family, kind, level}].
static func available(c: CharacterData) -> Array:
	var out: Array = []
	var u: Dictionary = cfg().get("unlock", {})
	var sig: Dictionary = cfg().get("signatures", {}).get(c.character_class, {})
	for fam in cfg().get("families", {}):
		var lv = family_level(c, fam)
		var arts: Array = cfg().get("arts", {}).get(fam, [])
		if sig.has(fam) and lv >= int(u.get("signature", 2)):
			out.append({"skill": String(sig[fam]), "family": fam, "kind": "signature"})
		if arts.size() > 0 and lv >= int(u.get("first", 3)):
			out.append({"skill": String(arts[0]), "family": fam, "kind": "art"})
		if arts.size() > 1 and lv >= int(u.get("second", 4)):
			out.append({"skill": String(arts[1]), "family": fam, "kind": "art"})
	return out

## Learn any newly earned arts. Returns log lines ("You learned Moonlit Draw!").
static func check_unlocks(c: CharacterData) -> Array:
	var lines: Array = []
	if c == null or not c.is_player:
		return lines
	for a in available(c):
		if not c.skills.has(a.skill):
			c.add_skills([a.skill])
			if c.equipped_skills.size() > 0 and c.equipped_skills.size() < TalentManager.loadout_size():
				c.equipped_skills.append(a.skill)
			lines.append("%s learned the %s art %s!" % [c.name, ("signature" if a.kind == "signature" else String(cfg().families[a.family].name).to_lower()), a.skill])
	return lines

## Arts for a generated NPC: by level, for the families of what they hold.
static func grant_npc(c: CharacterData) -> void:
	var nl: Dictionary = cfg().get("npc_levels", {})
	var sig: Dictionary = cfg().get("signatures", {}).get(c.character_class, {})
	for fam in held_families(c):
		if sig.has(fam) and c.level >= int(nl.get("signature", 5)):
			c.add_skills([String(sig[fam])])
		var arts: Array = cfg().get("arts", {}).get(fam, [])
		if arts.size() > 0 and c.level >= int(nl.get("first", 15)):
			c.add_skills([String(arts[0])])
		if arts.size() > 1 and c.level >= int(nl.get("second", 30)):
			c.add_skills([String(arts[1])])

## The signature families of a class (Myrmidon: several).
static func signature_families(cls: String) -> Array:
	return cfg().get("signatures", {}).get(cls, {}).keys()
