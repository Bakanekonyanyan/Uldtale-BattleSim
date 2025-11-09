# SaveManager.gd
extends Node

const SAVE_DIR = "user://saves/"
const SAVE_FILE_EXTENSION = ".json"

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
		"skill_levels": player.skill_levels,  # ADD THIS LINE
		"inventory": {},
		"stash": {},
		"equipment": {},
		"xp": player.xp,
		"attribute_points": player.attribute_points
	}
	
	# Save inventory - now including equipment data
	for item_key in player.inventory.items:
		var item_data = player.inventory.items[item_key]
		var item = item_data.item
		
		if item is Equipment:
			# Save full equipment data for equipment items
			var equip_save_data = {
				"quantity": item_data.quantity,
				"is_equipment": true,
				"base_id": item.id,
				"name": item.name,  # CRITICAL: Save the actual name
				"rarity": item.rarity,
				"rarity_applied": item.rarity_applied,
				"damage": item.damage,
				"armor_value": item.armor_value
			}
			# Add new rarity system properties
			if  "stat_modifiers" in item:
				equip_save_data["stat_modifiers"] = item.stat_modifiers
			if  "status_effect_chance" in item:
				equip_save_data["status_effect_chance"] = item.status_effect_chance
			if  "status_effect_type" in item:
				equip_save_data["status_effect_type"] = item.status_effect_type
			if  "bonus_damage" in item:
				equip_save_data["bonus_damage"] = item.bonus_damage
			if  "item_prefix" in item:
				equip_save_data["item_prefix"] = item.item_prefix
			if  "item_suffix" in item:
				equip_save_data["item_suffix"] = item.item_suffix
			if  "flavor_text" in item:
				equip_save_data["flavor_text"] = item.flavor_text
			save_data["inventory"][item_key] = equip_save_data
		else:
			# Regular items just need the ID
			save_data["inventory"][item_key] = {
				"quantity": item_data.quantity,
				"is_equipment": false
			}
	
	# Save stash - same approach
	for item_key in player.stash.items:
		var item_data = player.stash.items[item_key]
		var item = item_data.item
		
		if item is Equipment:
			var equip_save_data = {
				"quantity": item_data.quantity,
				"is_equipment": true,
				"base_id": item.id,
				"name": item.name,  # CRITICAL: Save the actual name
				"rarity": item.rarity,
				"rarity_applied": item.rarity_applied,
				"damage": item.damage,
				"armor_value": item.armor_value
			}
			# Add new rarity system properties
			if "stat_modifiers" in item:
				equip_save_data["stat_modifiers"] = item.stat_modifiers
			if "status_effect_chance" in item:
				equip_save_data["status_effect_chance"] = item.status_effect_chance
			if "status_effect_type" in item:
				equip_save_data["status_effect_type"] = item.status_effect_type
			if "bonus_damage" in item:
				equip_save_data["bonus_damage"] = item.bonus_damage
			if "item_prefix" in item:
				equip_save_data["item_prefix"] = item.item_prefix
			if "item_suffix" in item:
				equip_save_data["item_suffix"] = item.item_suffix
			if "flavor_text" in item:
				equip_save_data["flavor_text"] = item.flavor_text
			save_data["stash"][item_key] = equip_save_data
		else:
			save_data["stash"][item_key] = {
				"quantity": item_data.quantity,
				"is_equipment": false
			}
	
	# Save equipment
	save_data["equipment"] = {}
	for slot in player.equipment:
		if player.equipment[slot]:
			var equipped_item = player.equipment[slot]
			var equip_data = {
				"id": equipped_item.id,
				"name": equipped_item.name,  # CRITICAL: Save the actual name
				"rarity": equipped_item.rarity,
				"rarity_applied": equipped_item.rarity_applied,
				"damage": equipped_item.damage,
				"armor_value": equipped_item.armor_value
			}
			# Add new rarity system properties
			if "stat_modifiers" in equipped_item:
				equip_data["stat_modifiers"] = equipped_item.stat_modifiers
			if "status_effect_chance" in equipped_item:
				equip_data["status_effect_chance"] = equipped_item.status_effect_chance
			if "status_effect_type" in equipped_item:
				equip_data["status_effect_type"] = equipped_item.status_effect_type
			if "bonus_damage" in equipped_item:
				equip_data["bonus_damage"] = equipped_item.bonus_damage
			if "item_prefix" in equipped_item:
				equip_data["item_prefix"] = equipped_item.item_prefix
			if "item_suffix" in equipped_item:
				equip_data["item_suffix"] = equipped_item.item_suffix
			if "flavor_text" in equipped_item:
				equip_data["flavor_text"] = equipped_item.flavor_text
			save_data["equipment"][slot] = equip_data
			
	var file = FileAccess.open(get_save_file_path(player.name), FileAccess.WRITE)
	file.store_string(JSON.stringify(save_data))
	file.close()
	print("Character saved: ", player.name)

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
	player.xp = save_data.get("xp", 0)
	player.attribute_points = save_data.get("attribute_points", 0)
	player.is_player = true
	
	# Handle skills separately
	if "skills" in save_data and save_data["skills"] is Array:
		player.add_skills(save_data["skills"])
	else:
		print("Warning: Skills data not found or invalid for character: ", character_name)
	
	# ADD THIS: Restore skill levels BEFORE adding skills
	if "skill_levels" in save_data and typeof(save_data["skill_levels"]) == TYPE_DICTIONARY:
		player.skill_levels = save_data["skill_levels"]
		print("Loaded skill levels: ", player.skill_levels)
	
	# Handle skills separately - this will now use the loaded skill_levels
	if "skills" in save_data and save_data["skills"] is Array:
		player.add_skills(save_data["skills"])
	else:
		print("Warning: Skills data not found or invalid for character: ", character_name)

	# Load inventory
	if "inventory" in save_data:
		for item_key in save_data["inventory"]:
			var item_data = save_data["inventory"][item_key]
			
			if item_data.get("is_equipment", false):
				# Recreate equipment with saved stats
				var base_item = ItemManager.get_item(item_data["base_id"])
				if base_item and base_item is Equipment:
					# Apply the saved rarity and stats
					base_item.rarity = item_data.get("rarity", base_item.rarity)
					base_item.rarity_applied = item_data.get("rarity_applied", false)
					base_item.damage = item_data.get("damage", base_item.damage)
					base_item.armor_value = item_data.get("armor_value", base_item.armor_value)
					base_item.inventory_key = item_key  # Restore the unique key
					
					# Restore new rarity system properties
					if "stat_modifiers" in item_data:
						base_item.stat_modifiers = item_data["stat_modifiers"]
					if "status_effect_chance" in item_data:
						base_item.status_effect_chance = item_data["status_effect_chance"]
					if "status_effect_type" in item_data:
						base_item.status_effect_type = item_data["status_effect_type"]
					if "bonus_damage" in item_data:
						base_item.bonus_damage = item_data["bonus_damage"]
					if "item_prefix" in item_data:
						base_item.item_prefix = item_data["item_prefix"]
					if "item_suffix" in item_data:
						base_item.item_suffix = item_data["item_suffix"]
					if "flavor_text" in item_data:
						base_item.flavor_text = item_data["flavor_text"]
					
					# CRITICAL: Restore the actual name (not just prefix/suffix)
					if "name" in item_data:
						base_item.name = item_data["name"]
					
					# Add directly to inventory with the saved key
					player.inventory.items[item_key] = {
						"item": base_item,
						"quantity": item_data["quantity"]
					}
					print("Loaded equipment to inventory: ", base_item.name, " with key: ", item_key)
			else:
				# Regular item
				var item = ItemManager.get_item(item_key)
				if item:
					player.inventory.add_item(item, item_data["quantity"])
				else:
					print("Warning: Item not found in ItemManager: ", item_key)
	
	# Load stash
	if "stash" in save_data:
		for item_key in save_data["stash"]:
			var item_data = save_data["stash"][item_key]
			
			if item_data.get("is_equipment", false):
				# Recreate equipment with saved stats
				var base_item = ItemManager.get_item(item_data["base_id"])
				if base_item and base_item is Equipment:
					# Apply the saved rarity and stats
					base_item.rarity = item_data.get("rarity", base_item.rarity)
					base_item.rarity_applied = item_data.get("rarity_applied", false)
					base_item.damage = item_data.get("damage", base_item.damage)
					base_item.armor_value = item_data.get("armor_value", base_item.armor_value)
					base_item.inventory_key = item_key  # Restore the unique key
					
					# Restore new rarity system properties
					if "stat_modifiers" in item_data:
						base_item.stat_modifiers = item_data["stat_modifiers"]
					if "status_effect_chance" in item_data:
						base_item.status_effect_chance = item_data["status_effect_chance"]
					if "status_effect_type" in item_data:
						base_item.status_effect_type = item_data["status_effect_type"]
					if "bonus_damage" in item_data:
						base_item.bonus_damage = item_data["bonus_damage"]
					if "item_prefix" in item_data:
						base_item.item_prefix = item_data["item_prefix"]
					if "item_suffix" in item_data:
						base_item.item_suffix = item_data["item_suffix"]
					if "flavor_text" in item_data:
						base_item.flavor_text = item_data["flavor_text"]
					
					# CRITICAL: Restore the actual name (not just prefix/suffix)
					if "name" in item_data:
						base_item.name = item_data["name"]
					
					# Add directly to stash with the saved key
					player.stash.items[item_key] = {
						"item": base_item,
						"quantity": item_data["quantity"]
					}
					print("Loaded equipment to stash: ", base_item.name, " with key: ", item_key)
			else:
				# Regular item
				var item = ItemManager.get_item(item_key)
				if item:
					player.stash.add_item(item, item_data["quantity"])
				else:
					print("Warning: Stash item not found in ItemManager: ", item_key)
	
	# Load equipment
	if "equipment" in save_data:
		for slot in save_data["equipment"]:
			var equip_data = save_data["equipment"][slot]
			if typeof(equip_data) == TYPE_DICTIONARY:
				var item = ItemManager.get_item(equip_data["id"])
				if item and item is Equipment:
					item.rarity = equip_data.get("rarity", item.rarity)
					item.rarity_applied = equip_data.get("rarity_applied", false)
					item.damage = equip_data.get("damage", item.damage)
					item.armor_value = equip_data.get("armor_value", item.armor_value)
					
					# Restore new rarity system properties
					if  "stat_modifiers" in equip_data:
						item.stat_modifiers = equip_data["stat_modifiers"]
					if  "status_effect_chance" in equip_data:
						item.status_effect_chance = equip_data["status_effect_chance"]
					if  "status_effect_type" in equip_data:
						item.status_effect_type = equip_data["status_effect_type"]
					if  "bonus_damage" in equip_data:
						item.bonus_damage = equip_data["bonus_damage"]
					if  "item_prefix" in equip_data:
						item.item_prefix = equip_data["item_prefix"]
					if  "item_suffix" in equip_data:
						item.item_suffix = equip_data["item_suffix"]
					if  "flavor_text" in equip_data:
						item.flavor_text = equip_data["flavor_text"]
					
					# CRITICAL: Restore the actual name (not just prefix/suffix)
					if "name" in equip_data:
						item.name = equip_data["name"]
					
					player.equip_item(item)
					print("Loaded equipped item: ", item.name, " to slot: ", slot)
			else:
				print("Warning: Invalid equipment data for slot ", slot)
	
	print("Loaded inventory items: ", player.inventory.items.keys())
	print("Loaded stash items: ", player.stash.items.keys())
	
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
	var file_name = SAVE_DIR + character_name + ".json"
	if FileAccess.file_exists(file_name):
		var dir = DirAccess.open(SAVE_DIR)
		if dir:
			dir.remove(file_name)
			print("Character deleted: ", character_name)
	else:
		print("Character file not found: ", character_name)
