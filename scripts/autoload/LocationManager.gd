# res://scripts/autoload/LocationManager.gd
# Expedition locations (data/locations.json): where the player can go and which
# enemy races live there. "The Dungeon" mixes every race; the themed locations
# have a single race (and will become exploration areas later).
extends Node

const DEFAULT_LOCATION := "the_dungeon"

var locations: Dictionary = {}

func _ready():
	_load()

func _load() -> void:
	var data = DataRegistry.get_data("locations")
	locations = data.get("locations", {}) if data is Dictionary else {}

func has_location(location_id: String) -> bool:
	return locations.has(location_id)

func get_location(location_id: String) -> Dictionary:
	return locations.get(location_id, locations.get(DEFAULT_LOCATION, {}))

## All location ids in display order.
func get_ids() -> Array:
	var ids = locations.keys()
	ids.sort_custom(func(a, b): return int(locations[a].get("order", 99)) < int(locations[b].get("order", 99)))
	return ids

func get_display_name(location_id: String) -> String:
	return get_location(location_id).get("name", location_id)

func is_mixed(location_id: String) -> bool:
	return bool(get_location(location_id).get("mixed", false))

## Races that can spawn here. "all" = every non-playable race in races.json.
func get_races(location_id: String, all_races: Array) -> Array:
	var races = get_location(location_id).get("races", "all")
	if races is String and races == "all":
		return all_races
	return races if races is Array and not races.is_empty() else all_races

func get_reward_mult(location_id: String) -> float:
	return float(get_location(location_id).get("reward_mult", 1.0))
