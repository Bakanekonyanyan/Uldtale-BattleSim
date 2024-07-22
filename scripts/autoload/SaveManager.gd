# SaveManager.gd
extends Node

const SAVE_DIR = "user://saves/"
const SAVE_FILE_EXTENSION = ".tres"

func _ready():
	create_save_directory()

func create_save_directory():
	if not DirAccess.dir_exists_absolute(SAVE_DIR):
		DirAccess.make_dir_absolute(SAVE_DIR)

func get_save_file_path(character_name: String) -> String:
	return SAVE_DIR + character_name + ".json"

func save_exists(character_name: String) -> bool:
	return FileAccess.file_exists(get_save_file_path(character_name))

func save_game(player: CharacterData):
	var save_data = {
		"name": player.name,
		"race": player.race,
		"character_class": player.character_class,
		"level": player.level,
		"vitality": player.vitality,
		"strength": player.strength,
		"dexterity": player.dexterity,
		"intelligence": player.intelligence,
		"faith": player.faith,
		"mind": player.mind,
		"endurance": player.endurance,
		"arcane": player.arcane,
		"agility": player.agility,
		"fortitude": player.fortitude,
		"max_hp": player.max_hp,
		"current_hp": player.current_hp,
		"max_mp": player.max_mp,
		"current_mp": player.current_mp,
		"currency": player.currency.copper,
		"attack_power_type": player.attack_power_type,
		"spell_power_type": player.spell_power_type,
		"skills": player.skills,
		"inventory": {},
		"equipment": {}
	}
	
	# Save inventory
	for item_id in player.inventory.items:
		var item_data = player.inventory.items[item_id]
		save_data["inventory"][item_id] = {
			"quantity": item_data.quantity
		}
	
	var file = FileAccess.open(get_save_file_path(player.name), FileAccess.WRITE)
	file.store_string(JSON.stringify(save_data))
	file.close()

func load_game(character_name: String) -> CharacterData:
	var save_file = get_save_file_path(character_name)
	if not FileAccess.file_exists(save_file):
		print("Save file does not exist: ", save_file)
		return null

	var file = FileAccess.open(save_file, FileAccess.READ)
	if file == null:
		print("Error: Could not open file for reading: ", save_file)
		return null

	var json_string = file.get_as_text()
	file.close()

	var save_data = JSON.parse_string(json_string)
	if save_data == null:
		print("Error: Could not parse save data for character: ", character_name)
		return null

	var player = CharacterData.new()
	player.name = save_data.get("name", "")
	player.race = save_data.get("race", "")
	player.character_class = save_data.get("character_class", "")
	player.level = save_data.get("level", 1)
	player.vitality = save_data.get("vitality", 0)
	player.strength = save_data.get("strength", 0)
	player.dexterity = save_data.get("dexterity", 0)
	player.intelligence = save_data.get("intelligence", 0)
	player.faith = save_data.get("faith", 0)
	player.mind = save_data.get("mind", 0)
	player.endurance = save_data.get("endurance", 0)
	player.arcane = save_data.get("arcane", 0)
	player.agility = save_data.get("agility", 0)
	player.fortitude = save_data.get("fortitude", 0)
	player.max_hp = save_data.get("max_hp", 0)
	player.current_hp = save_data.get("current_hp", 0)
	player.max_mp = save_data.get("max_mp", 0)
	player.current_mp = save_data.get("current_mp", 0)
	player.currency.copper = save_data.get("currency", 0)
	player.attack_power_type = save_data.get("attack_power_type", "strength")
	player.spell_power_type = save_data.get("spell_power_type", "intelligence")
	
	# Handle skills separately
	if "skills" in save_data and save_data["skills"] is Array:
		player.add_skills(save_data["skills"])
	else:
		print("Warning: Skills data not found or invalid for character: ", character_name)

	# Load inventory
	if "inventory" in save_data:
		for item_id in save_data["inventory"]:
			var item_data = save_data["inventory"][item_id]
			var item = ItemManager.get_item(item_id)
			if item:
				player.inventory.add_item(item, item_data["quantity"])
			else:
				print("Warning: Item not found in ItemManager: ", item_id)
	print("Loaded inventory items: ", player.inventory.items)
	# Recalculate secondary attributes
	player.calculate_secondary_attributes()

	return player
	
func get_all_characters() -> Array:
	var characters = []
	var dir = DirAccess.open(SAVE_DIR)
	if dir:
		dir.list_dir_begin()
		var file_name = dir.get_next()
		while file_name != "":
			if not dir.current_is_dir() and file_name.ends_with(".json"):
				var character = load_game(file_name.get_basename())
				if character:
					characters.append(character)
			file_name = dir.get_next()
	return characters
	
func delete_character(character_name: String):
	var file_name = SAVE_DIR + character_name + SAVE_FILE_EXTENSION
	if FileAccess.file_exists(file_name):
		var dir = DirAccess.open(SAVE_DIR)
		if dir:
			dir.remove(file_name)
			print("Character deleted: ", character_name)
	else:
		print("Character file not found: ", character_name)
