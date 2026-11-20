# res://scripts/resources/WaveChallenges.gd
# Optional per-wave goals (data/challenges.json). BattleRules.stats counts what
# happens in the battle; at victory the challenge is checked and its reward is
# banked with the wave's loot (MomentumSystem).
class_name WaveChallenges
extends RefCounted

static func cfg() -> Dictionary:
	var d = DataRegistry.get_data("challenges")
	return d if d is Dictionary else {}

static func all() -> Dictionary:
	var out: Dictionary = {}
	var c: Dictionary = cfg().get("challenges", {})
	for id in c:
		if not String(id).begins_with("_"):
			out[id] = c[id]
	return out

## A challenge for this wave, or {} (the roll can skip). Adds "id".
static func pick(is_boss: bool, enemies: int, party: int) -> Dictionary:
	var chance = float(cfg().get("boss_chance" if is_boss else "chance", 0.6))
	if RandomManager.randf() >= chance:
		return {}
	var pool: Dictionary = {}
	var cs = all()
	for id in cs:
		var c: Dictionary = cs[id]
		if enemies < int(c.get("min_enemies", 1)) or party < int(c.get("min_party", 1)):
			continue
		pool[id] = float(c.get("weight", 1.0))
	var total := 0.0
	for id in pool:
		total += pool[id]
	if total <= 0.0:
		return {}
	var roll = RandomManager.randf() * total
	for id in pool:
		roll -= pool[id]
		if roll <= 0.0:
			var out: Dictionary = cs[id].duplicate()
			out["id"] = id
			return out
	return {}

## Is the challenge met by these battle stats?
static func met(ch: Dictionary, stats: Dictionary) -> bool:
	if ch.is_empty():
		return false
	var v = int(stats.get(String(ch.get("stat", "")), 0))
	if ch.has("at_least") and v < int(ch.at_least):
		return false
	if ch.has("at_most") and v > int(ch.at_most):
		return false
	return true

## Progress text for the HUD: "Breaker: Break 2 enemies (1/2)".
static func progress(ch: Dictionary, stats: Dictionary) -> String:
	if ch.is_empty():
		return ""
	var v = int(stats.get(String(ch.get("stat", "")), 0))
	var tail = ""
	if ch.has("at_least"):
		tail = " (%d/%d)" % [min(v, int(ch.at_least)), int(ch.at_least)]
	elif String(ch.get("stat", "")) == "rounds":
		tail = " (round %d)" % v
	return "%s: %s%s" % [ch.get("name", ""), ch.get("description", ""), tail]

## The reward for meeting a challenge (a rewards dict MomentumSystem can bank).
static func roll_reward(floor: int, is_boss: bool, enemies: Array) -> Dictionary:
	var r: Dictionary = cfg().get("reward", {})
	var out: Dictionary = {"currency": int(round(float(r.get("gold_per_floor", 40)) * floor * (float(r.get("boss_mult", 2.0)) if is_boss else 1.0))), "equipment_instances": []}
	for i in range(int(r.get("material_rolls", 2))):
		var drops = RewardsManager.roll_material_drops({"current_floor": floor, "is_boss_fight": false, "enemies": enemies})
		for id in drops:
			out[id] = int(out.get(id, 0)) + int(drops[id])
	if RandomManager.randf() < float(r.get("gear_chance", 0.25)):
		var id = ItemManager.get_random_weapon() if RandomManager.randf() < 0.5 else ItemManager.get_random_armor()
		var g = ItemManager.create_equipment_for_floor(id, floor, 1)
		if g:
			out.equipment_instances.append(g)
	return out
