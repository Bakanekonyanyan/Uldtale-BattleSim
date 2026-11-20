# res://scripts/autoload/RunState.gd
# Modifiers for the current expedition: Omens (data/omens.json, picked when
# setting out) and boons (data/boons.json, picked after bosses). Both use the
# same effect keys; systems read them through mult() / add() / flag().
# Cleared when the expedition ends.
extends Node

var omens: Array = []   # omen ids
var boons: Array = []   # boon ids

func _ready() -> void:
	GameEvents.expedition_ended.connect(func(_loc, _cleared): clear())

func clear() -> void:
	omens.clear()
	boons.clear()

static func omen_data() -> Dictionary:
	var d = DataRegistry.get_data("omens")
	return d if d is Dictionary else {}

static func boon_data() -> Dictionary:
	var d = DataRegistry.get_data("boons")
	return d if d is Dictionary else {}

static func all_omens() -> Dictionary:
	return _entries(omen_data().get("omens", {}))

static func all_boons() -> Dictionary:
	return _entries(boon_data().get("boons", {}))

static func _entries(d: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for id in d:
		if not String(id).begins_with("_"):
			out[id] = d[id]
	return out

func set_omens(ids: Array) -> void:
	var cap = int(omen_data().get("max_omens", 3))
	omens = ids.filter(func(i): return all_omens().has(i)).slice(0, cap)

func add_boon(id: String) -> void:
	if all_boons().has(id):
		boons.append(id)

func _effects() -> Array:
	var out: Array = []
	var o = all_omens()
	for id in omens:
		out.append(o.get(id, {}).get("effects", {}))
	var b = all_boons()
	for id in boons:
		out.append(b.get(id, {}).get("effects", {}))
	return out

## Product of a multiplicative effect (1.0 when none).
func mult(key: String) -> float:
	var m := 1.0
	for e in _effects():
		if e.has(key):
			m *= float(e[key])
	return m

## Sum of an additive effect (0 when none).
func add(key: String) -> float:
	var s := 0.0
	for e in _effects():
		s += float(e.get(key, 0.0))
	return s

func flag(key: String) -> bool:
	return _effects().any(func(e): return bool(e.get(key, false)))

## Total Omen reward bonus (+0.35 = +35% gold and materials).
func reward_bonus() -> float:
	var s := 0.0
	var o = all_omens()
	for id in omens:
		s += float(o.get(id, {}).get("reward", 0.0))
	return s

func names(ids: Array, table: Dictionary) -> Array:
	return ids.map(func(i): return String(table.get(i, {}).get("name", i)))

## "Omens: Bloodmoon, Brittle (+30% loot)" or "".
func describe() -> String:
	var parts: Array = []
	if not omens.is_empty():
		parts.append("Omens: %s (+%d%% loot)" % [", ".join(names(omens, all_omens())), int(round(reward_bonus() * 100))])
	if not boons.is_empty():
		parts.append("Boons: %s" % ", ".join(names(boons, all_boons())))
	return "  ".join(parts)

## Omen effects on a fresh wave's enemies (once per enemy).
func apply_to_enemies(enemies: Array) -> void:
	if omens.is_empty() and boons.is_empty():
		return
	var dmg = mult("enemy_damage_mult")
	var hp = mult("enemy_hp_mult")
	var agi = mult("enemy_agility_mult")
	for e in enemies:
		if e == null or e.get_meta("run_mods_applied", false):
			continue
		e.set_meta("run_mods_applied", true)
		e.damage_multiplier *= dmg
		if hp != 1.0:
			e.hp_multiplier *= hp
		if agi != 1.0:
			e.agility = int(round(e.agility * agi))
		e.calculate_secondary_attributes()
		e.current_hp = e.max_hp
