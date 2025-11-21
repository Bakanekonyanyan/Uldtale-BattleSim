# res://scripts/autoload/RaceElementalData.gd
# Autoload singleton that loads race elemental data from races.json
# Provides lookup for resistances, weaknesses, and damage bonuses

extends Node

var race_data: Dictionary = {}

func _ready():
	load_data()

func load_data():
	var path = "res://data/races.json"
	
	if not FileAccess.file_exists(path):
		push_error("RaceElementalData: races.json not found at " + path)
		return
	
	var file = FileAccess.open(path, FileAccess.READ)
	if file:
		var result = JSON.parse_string(file.get_as_text())
		if typeof(result) == TYPE_DICTIONARY:
			race_data = result
			print(" Loaded race elemental data from races.json")
			print("   Playable races: ", race_data.get("playable", {}).keys())
			print("   NPC races: ", race_data.get("non_playable", {}).keys())
		else:
			push_error("RaceElementalData: Invalid JSON format in races.json")
		file.close()
	else:
		push_error("RaceElementalData: Could not open races.json")

func get_race_elemental_data(race_name: String, is_playable: bool = true) -> Dictionary:
	"""Get elemental data for a specific race"""
	var category = "playable" if is_playable else "non_playable"
	
	if not race_data.has(category):
		push_warning("RaceElementalData: Category '%s' not found" % category)
		return _get_default_data()
	
	if not race_data[category].has(race_name):
		push_warning("RaceElementalData: Race '%s' not found in %s" % [race_name, category])
		return _get_default_data()
	
	var race = race_data[category][race_name]
	
	# Extract elemental data from race entry
	return {
		"resistances": race.get("elemental_resistances", {}),
		"weaknesses": race.get("elemental_weaknesses", {}),
		"damage_bonuses": race.get("elemental_damage_bonuses", {})
	}

func apply_to_character(character: CharacterData, race_name: String, is_playable: bool = true):
	"""Apply racial elemental modifiers to a character"""
	if not character.elemental_resistances:
		push_error("RaceElementalData: Character missing elemental_resistances manager")
		return
	
	var data = get_race_elemental_data(race_name, is_playable)
	
	# Apply resistances
	if data.has("resistances"):
		for element_str in data.resistances.keys():
			if ElementalDamage.Element.has(element_str):
				var element = ElementalDamage.Element[element_str]
				var value = float(data.resistances[element_str])
				character.elemental_resistances.set_base_resistance(element, value)
	
	# Apply weaknesses
	if data.has("weaknesses"):
		for element_str in data.weaknesses.keys():
			if ElementalDamage.Element.has(element_str):
				var element = ElementalDamage.Element[element_str]
				var value = float(data.weaknesses[element_str])
				character.elemental_resistances.set_base_weakness(element, value)
	
	# Apply damage bonuses
	if data.has("damage_bonuses"):
		for element_str in data.damage_bonuses.keys():
			if ElementalDamage.Element.has(element_str):
				var element = ElementalDamage.Element[element_str]
				var value = float(data.damage_bonuses[element_str])
				character.elemental_resistances.set_damage_bonus(element, value)

func _get_default_data() -> Dictionary:
	"""Return empty elemental data"""
	return {
		"resistances": {},
		"weaknesses": {},
		"damage_bonuses": {}
	}
