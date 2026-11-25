# res://scripts/resources/Regions.gd
# Regions of Nyxarys (data/regions.json; docs/lore/ELEDORIA_ATLAS.md): the
# Guild's town (Nexus), the regions and their towns - your birthplace and
# every adventurer's - and race homelands.
class_name Regions
extends RefCounted

static func cfg() -> Dictionary:
	var d = DataRegistry.get_data("regions")
	return d if d is Dictionary else {}

static func town_name() -> String:
	return String(cfg().get("town", "Nexus"))

## [{town, region, region_name, god}] in map order.
static func towns() -> Array:
	var out: Array = []
	var regs: Dictionary = cfg().get("regions", {})
	for r in regs:
		for t in regs[r].get("towns", []):
			out.append({"town": String(t), "region": r, "region_name": String(regs[r].get("name", r)), "god": String(regs[r].get("god", ""))})
	return out

static func region_of(town: String) -> String:
	for t in towns():
		if t.town == town:
			return String(t.region)
	return ""

static func region_name(region: String) -> String:
	return String(cfg().get("regions", {}).get(region, {}).get("name", ""))

## "Fangclaw (The Wildwood Expanse)"
static func describe(town: String) -> String:
	var r = region_of(town)
	return town if r == "" else "%s (%s)" % [town, region_name(r)]

## A birthplace for an adventurer of `race`: usually their people's homeland.
static func roll_birthplace(race: String) -> String:
	var all = towns()
	if all.is_empty():
		return ""
	var home: Array = cfg().get("race_homelands", {}).get(race, [])
	if not home.is_empty() and RandomManager.randf() < float(cfg().get("homeland_chance", 0.7)):
		var mine = all.filter(func(t): return t.region in home)
		if not mine.is_empty():
			return String(mine[RandomManager.randi() % mine.size()].town)
	return String(all[RandomManager.randi() % all.size()].town)

static func player_birthplace(player: CharacterData) -> String:
	return String(player.town_state.get("birthplace", "")) if player else ""

static func same_region(player: CharacterData, npc: Dictionary) -> bool:
	var a = region_of(player_birthplace(player))
	return a != "" and a == region_of(String(npc.get("birthplace", "")))
