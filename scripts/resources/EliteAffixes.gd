# res://scripts/resources/EliteAffixes.gd
# Elite enemies (data/elites.json): one enemy of a regular wave may become an
# Elite with an affix. The affix is stored as meta "elite_affix" and read by
# BattleFormulas (vampiric), CharacterData.take_damage (shielded barrier,
# thorns) and BattleRules (raging, splitting).
class_name EliteAffixes
extends RefCounted

static func data() -> Dictionary:
	var d = DataRegistry.get_data("elites")
	return d if d is Dictionary else {}

static func affix(id: String) -> Dictionary:
	return data().get("affixes", {}).get(id, {})

## Chance that a wave on `floor_num` has an elite.
static func chance(floor_num: int) -> float:
	var s: Dictionary = data().get("settings", {})
	if floor_num < int(s.get("min_floor", 2)):
		return 0.0
	return min(float(s.get("chance_max", 0.3)), float(s.get("chance_base", 0.06)) + float(s.get("chance_per_floor", 0.01)) * floor_num)

static func roll_affix() -> String:
	var affs: Dictionary = data().get("affixes", {})
	var total := 0.0
	for id in affs:
		total += float(affs[id].get("weight", 1))
	var r = RandomManager.randf() * total
	for id in affs:
		r -= float(affs[id].get("weight", 1))
		if r <= 0.0:
			return id
	return affs.keys()[0] if not affs.is_empty() else ""

## Turn `e` into an elite with affix `id`.
static func apply(e: CharacterData, id: String) -> void:
	var a = affix(id)
	if a.is_empty():
		return
	var s: Dictionary = data().get("settings", {})
	e.set_meta("elite_affix", id)
	e.name = "%s %s" % [a.get("name", id.capitalize()), e.name]
	e.level += int(s.get("level_bonus", 2))
	e.hp_multiplier *= float(s.get("hp_mult", 1.5))
	match id:
		"swift":
			e.agility = int(e.agility * float(a.get("agility_mult", 1.6)))
	e.calculate_secondary_attributes()
	e.current_hp = e.max_hp
	if id == "shielded":
		e.set_meta("barrier", int(e.max_hp * float(a.get("barrier", 0.3))))

## A smaller copy of a Splitting elite (no affix of its own).
static func make_fragment(parent: CharacterData, hp_frac: float, n: int, floor_num: int) -> CharacterData:
	var arch = String(parent.get_meta("archetype", ""))
	var saved = EnemyFactory.force_archetype
	EnemyFactory.force_archetype = arch
	var c = EnemyFactory.create_enemy(1, floor_num, 1, 0)
	EnemyFactory.force_archetype = saved
	c.name = "%s Fragment %d" % [String(parent.name).get_slice(" ", 1), n]
	c.hp_multiplier *= hp_frac
	c.calculate_secondary_attributes()
	c.current_hp = c.max_hp
	c.set_meta("fragment", true)
	return c

## One-line description for UI tooltips.
static func describe(e: CharacterData) -> String:
	var id = String(e.get_meta("elite_affix", ""))
	return "" if id == "" else "%s: %s" % [affix(id).get("name", id), affix(id).get("description", "")]
