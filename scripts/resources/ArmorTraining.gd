# res://scripts/resources/ArmorTraining.gd
# Armour training (data/armor_training.json; LIVING_WORLD.md J). A hero is
# trained up to an armour weight (and every lighter one) and maybe in shields,
# by class; each promotion gives a training point for one weight heavier or
# shields. Untrained armour and shields can still be worn, with penalties
# (accuracy, dodge, SP costs) per piece. Enemies are unaffected.
class_name ArmorTraining
extends RefCounted

static func cfg() -> Dictionary:
	var d = DataRegistry.get_data("armor_training")
	return d if d is Dictionary else {}

static func weights() -> Array:
	return cfg().get("weights", ["cloth", "leather", "mail", "plate"])

static func _start(cls: String) -> Dictionary:
	return cfg().get("start", {}).get(cls, cfg().get("default_start", {"weight": "leather"}))

static func _state(c: CharacterData) -> Dictionary:
	if not c.town_state.has("armor_training"):
		c.town_state["armor_training"] = {"extra": 0, "shield": false, "points": 0}
	return c.town_state["armor_training"]

## Index of the heaviest trained weight.
static func trained_tier(c: CharacterData) -> int:
	var base = weights().find(String(_start(c.character_class).get("weight", "leather")))
	var extra = int(_state(c).get("extra", 0)) if c.is_player else 0
	return clamp(max(0, base) + extra, 0, weights().size() - 1)

static func trained_weight(c: CharacterData) -> String:
	return String(weights()[trained_tier(c)])

static func shield_trained(c: CharacterData) -> bool:
	return bool(_start(c.character_class).get("shield", false)) or bool(_state(c).get("shield", false))

## Is this armour piece / shield within the hero's training?
static func is_trained(c: CharacterData, item: Equipment) -> bool:
	if item == null:
		return true
	if String(item.type) == "shield":
		return shield_trained(c)
	var t = weights().find(String(item.type))
	return t < 0 or t <= trained_tier(c)

## Untrained gear worn: {pieces, shield, accuracy, dodge, sp_cost}.
static func penalties(c: CharacterData) -> Dictionary:
	var out := {"pieces": 0, "shield": false, "accuracy": 0.0, "dodge": 0.0, "sp_cost": 0.0}
	if c == null or not c.is_player:
		return out
	var pp: Dictionary = cfg().get("penalty_per_piece", {})
	var sp: Dictionary = cfg().get("shield_penalty", {})
	for slot in c.equipment:
		var it = c.equipment[slot]
		if not (it is Equipment) or is_trained(c, it):
			continue
		var p = sp if String(it.type) == "shield" else pp
		if String(it.type) == "shield":
			out.shield = true
		else:
			out.pieces += 1
		for k in ["accuracy", "dodge", "sp_cost"]:
			out[k] = float(out[k]) + float(p.get(k, 0.0))
	return out

# ------------------------------------------------------------------ training points

static func points(c: CharacterData) -> int:
	return int(_state(c).get("points", 0))

static func grant_point(c: CharacterData, n: int = -1) -> void:
	_state(c).points = points(c) + (n if n >= 0 else int(cfg().get("points_per_promotion", 1)))

## Options right now: [{id: "heavier"/"shield", text}].
static func options(c: CharacterData) -> Array:
	var out: Array = []
	if trained_tier(c) < weights().size() - 1:
		out.append({"id": "heavier", "text": "%s armour" % String(weights()[trained_tier(c) + 1]).capitalize()})
	if not shield_trained(c):
		out.append({"id": "shield", "text": "Shields"})
	return out

## Spend a point. Returns a message, or "" if not possible.
static func train(c: CharacterData, id: String) -> String:
	if points(c) <= 0 or not options(c).any(func(o): return o.id == id):
		return ""
	var st = _state(c)
	st.points = points(c) - 1
	if id == "heavier":
		st.extra = int(st.get("extra", 0)) + 1
		c.calculate_secondary_attributes()
		return "You're now trained in %s armour." % trained_weight(c).capitalize()
	st.shield = true
	c.calculate_secondary_attributes()
	return "You're now trained with shields."
