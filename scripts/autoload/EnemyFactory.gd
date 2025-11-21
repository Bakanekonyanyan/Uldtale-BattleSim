# res://scripts/autoload/EnemyFactory.gd
extends Node

var races = {}
var classes = {}
var skills = {}
var current_dungeon_race: String = ""
var dungeon_race: String = ""
var current_floor: int = 0

func _ready():
	load_data()

func load_data():
	var file = FileAccess.open("res://data/races.json", FileAccess.READ)
	races = JSON.parse_string(file.get_as_text())

	file = FileAccess.open("res://data/classes.json", FileAccess.READ)
	classes = JSON.parse_string(file.get_as_text())

	file = FileAccess.open("res://data/skills.json", FileAccess.READ)
	skills = JSON.parse_string(file.get_as_text())["skills"]

func get_dungeon_race():
	if current_dungeon_race == "":
		print("Warning: Dungeon race not set yet! Call set_dungeon_race(floor) first.")
	else:
		print("Current dungeon race:", current_dungeon_race)
	return current_dungeon_race

func set_dungeon_race(floor: int):
	if floor != current_floor:
		current_floor = floor
		var non_playable_races = races["non_playable"].keys()
		dungeon_race = non_playable_races[RandomManager.randi() % non_playable_races.size()]
		current_dungeon_race = dungeon_race
		print("Floor %d - Current dungeon race set to: %s" % [floor, current_dungeon_race])
	else:
		print("Floor %d - Keeping current dungeon race: %s" % [floor, current_dungeon_race])

func create_enemy(level: int = 1, floor: int = 1, wave: int = 1, momentum_level: int = 0) -> CharacterData:
	var enemy = CharacterData.new()
	level = floor
	#  FIX: Ensure dungeon race is set
	if current_dungeon_race == "" or current_dungeon_race == null:
		print("WARNING: Dungeon race not set, setting now for floor %d" % floor)
		set_dungeon_race(floor)
	
	get_dungeon_race()

	#  DEBUG: Check types at each step
	print("=== DEBUG create_enemy ===")
	print("1. races type: ", typeof(races))
	print("2. races.keys(): ", races.keys())
	print("3. races['non_playable'] type: ", typeof(races["non_playable"]))
	print("4. current_dungeon_race: ", current_dungeon_race, " (type: ", typeof(current_dungeon_race), ")")
	
	# Check if current_dungeon_race exists in races
	if not races["non_playable"].has(current_dungeon_race):
		push_error("ERROR: Race '%s' not found in races['non_playable']!" % current_dungeon_race)
		print("Available races: ", races["non_playable"].keys())
		return enemy
	
	print("5. races['non_playable'][current_dungeon_race] type: ", typeof(races["non_playable"][current_dungeon_race]))
	
	var enemy_classes = classes["non_playable"].keys()
	var chosen_class = enemy_classes[RandomManager.randi() % enemy_classes.size()]
	
	print("6. chosen_class: ", chosen_class)
	print("7. classes['non_playable'][chosen_class] type: ", typeof(classes["non_playable"][chosen_class]))

	#  FIX: Pass race name AND race data separately
	var race_data = races["non_playable"][current_dungeon_race]
	print("8. race_data: ", race_data)
	print("9. About to call setup_character...")
	
	setup_character(enemy, chosen_class, "non_playable", current_dungeon_race, race_data)
	enemy.name = "%s %s" % [current_dungeon_race, chosen_class]

	#  ADD THIS: Initialize elemental resistances for enemies
	if enemy.elemental_resistances == null:
		enemy.elemental_resistances = ElementalResistanceManager.new(enemy)
	enemy.initialize_racial_elementals(true)

	enemy.level = level + 1
	for _i in range(level - 1):
		enemy.level_up()
	
	apply_enemy_scaling(enemy, floor, wave, false, momentum_level)
	give_enemy_equipment(enemy, floor)
	give_enemy_items(enemy, floor, false, momentum_level)
	
	enemy.is_player = false
	enemy.calculate_secondary_attributes()
	enemy.current_hp = enemy.max_hp
	enemy.current_mp = enemy.max_mp
	enemy.current_sp = enemy.max_sp

	return enemy

func create_boss(floor: int = 1, wave: int = 1, momentum_level: int = 0) -> CharacterData:
	#  FIX: Ensure dungeon race is set
	if current_dungeon_race == "" or current_dungeon_race == null:
		print("WARNING: Dungeon race not set for boss, setting now for floor %d" % floor)
		set_dungeon_race(floor)
	
	var boss = CharacterData.new()
	var king_data = classes["boss"]["King"]
	
	var minion_classes = ["Shaman", "Brute", "Minion"]
	var chosen_minion = minion_classes[RandomManager.randi() % minion_classes.size()]
	var minion_data = classes["non_playable"][chosen_minion]
	var race_data = races["non_playable"][current_dungeon_race]
	
	boss.name = "%s %s King" % [current_dungeon_race, chosen_minion]
	boss.race = current_dungeon_race
	boss.character_class = "King (%s)" % chosen_minion
	
	var minion_contribution = 0.5
	#  FIX: Use bracket notation for dictionary access
	boss.vitality = int((king_data["base_vit"] + race_data["vit_mod"]) + (minion_data["base_vit"] * minion_contribution))
	boss.strength = int((king_data["base_str"] + race_data["str_mod"]) + (minion_data["base_str"] * minion_contribution))
	boss.dexterity = int((king_data["base_dex"] + race_data["dex_mod"]) + (minion_data["base_dex"] * minion_contribution))
	boss.intelligence = int((king_data["base_int"] + race_data["int_mod"]) + (minion_data["base_int"] * minion_contribution))
	boss.faith = int((king_data["base_fai"] + race_data["fai_mod"]) + (minion_data["base_fai"] * minion_contribution))
	boss.mind = int((king_data["base_mnd"] + race_data["mnd_mod"]) + (minion_data["base_mnd"] * minion_contribution))
	boss.endurance = int((king_data["base_end"] + race_data["end_mod"]) + (minion_data["base_end"] * minion_contribution))
	boss.arcane = int((king_data["base_arc"] + race_data["arc_mod"]) + (minion_data["base_arc"] * minion_contribution))
	boss.agility = int((king_data["base_agi"] + race_data["agi_mod"]) + (minion_data["base_agi"] * minion_contribution))
	boss.fortitude = int((king_data["base_for"] + race_data["for_mod"]) + (minion_data["base_for"] * minion_contribution))
	
	boss.vitality = int(boss.vitality * 2)
	boss.strength = int(boss.strength * 1.5)
	boss.intelligence = int(boss.intelligence * 1.5)
	boss.faith = int(boss.faith * 1.5)
	boss.endurance = int(boss.endurance * 1.5)
	
	boss.attack_power_type = king_data["attack_power_type"]
	boss.spell_power_type = king_data["spell_power_type"]
	
	var combined_skills: Array = []
	for skill_name in king_data["skills"]:
		if skills.has(skill_name):
			combined_skills.append(skill_name)
	for skill_name in minion_data["skills"]:
		if skills.has(skill_name) and skill_name not in combined_skills:
			combined_skills.append(skill_name)
	
	if combined_skills.size() > 0:
		boss.add_skills(combined_skills)
	
	#  ADD THIS: Initialize elemental resistances for boss
	if boss.elemental_resistances == null:
		boss.elemental_resistances = ElementalResistanceManager.new(boss)
	boss.initialize_racial_elementals(true)
	
	apply_enemy_scaling(boss, floor, wave, true, momentum_level)
	give_enemy_equipment(boss, floor, true)
	give_enemy_items(boss, floor, true, momentum_level)
	
	boss.is_player = false
	boss.calculate_secondary_attributes()
	boss.current_hp = boss.max_hp
	boss.current_mp = boss.max_mp
	boss.current_sp = boss.max_sp
	
	return boss

func apply_enemy_scaling(enemy: CharacterData, floor: int, wave: int, is_boss: bool = false, momentum_level: int = 0):
	# Progressive difficulty curve with breakpoints
	var difficulty_tier = get_difficulty_tier(floor)
	var base_multiplier = get_base_multiplier(floor)
	var wave_multiplier = 1.0 + (0.15 * wave)  # Reduced from 0.25
	
	var momentum_multiplier = 1.0
	if momentum_level > 0:
		momentum_multiplier = 1.0 + (momentum_level * 0.10)
	
	# Boss scaling
	var boss_multiplier = 1.5 if is_boss else 1.0
	
	var total_multiplier = base_multiplier * wave_multiplier * momentum_multiplier * boss_multiplier
	
	# Apply scaling
	enemy.vitality = int(enemy.vitality * total_multiplier)
	enemy.strength = int(enemy.strength * total_multiplier)
	enemy.dexterity = int(enemy.dexterity * total_multiplier)
	enemy.intelligence = int(enemy.intelligence * total_multiplier)
	enemy.faith = int(enemy.faith * total_multiplier)
	enemy.mind = int(enemy.mind * total_multiplier)
	enemy.endurance = int(enemy.endurance * total_multiplier)
	enemy.arcane = int(enemy.arcane * total_multiplier)
	enemy.agility = int(enemy.agility * total_multiplier)
	enemy.fortitude = int(enemy.fortitude * total_multiplier)
	
	if momentum_level > 0:
		print("Enemy scaled with momentum x%d: +%d%% stats" % [momentum_level, int((momentum_multiplier - 1.0) * 100)])
	
	print("Floor %d (Tier %d): Base multiplier %.2f, Total multiplier: %.2f" % [floor, difficulty_tier, base_multiplier, total_multiplier])

func get_difficulty_tier(floor: int) -> int:
	"""Returns difficulty tier 1-8 based on floor"""
	if floor <= 2:
		return 1  # Tutorial/Easy
	elif floor <= 5:
		return 2  # Normal
	elif floor <= 8:
		return 3  # Challenging
	elif floor <= 11:
		return 4  # Hard
	elif floor <= 14:
		return 5  # Very Hard
	elif floor <= 17:
		return 6  # Expert
	elif floor <= 20:
		return 7  # Master
	else:
		return 8  # Legendary

func get_base_multiplier(floor: int) -> float:
	"""Returns stat multiplier based on floor with smooth progression"""
	if floor <= 2:
		# Floors 1-2: Easy introduction (1.0x - 1.1x)
		return 1.0 + (floor - 1) * 0.05
	elif floor <= 5:
		# Floors 3-5: Gradual increase (1.15x - 1.45x)
		return 1.1 + (floor - 2) * 0.15
	elif floor <= 8:
		# Floors 6-8: Moderate scaling (1.6x - 2.05x)
		return 1.45 + (floor - 5) * 0.20
	elif floor <= 11:
		# Floors 9-11: Steeper curve (2.3x - 3.05x)
		return 2.05 + (floor - 8) * 0.35
	elif floor <= 14:
		# Floors 12-14: (3.4x - 4.5x)
		return 3.05 + (floor - 11) * 0.45
	elif floor <= 17:
		# Floors 15-17: (5.0x - 6.5x)
		return 4.5 + (floor - 14) * 0.60
	elif floor <= 20:
		# Floors 18-20: (7.2x - 9.0x)
		return 6.5 + (floor - 17) * 0.75
	else:
		# Floors 21-25: End game (9.9x - 13.5x)
		return 9.0 + (floor - 20) * 0.90

func get_available_equipment_slots(floor: int, is_boss: bool) -> Array:
	"""Equipment slots scale better with floor progression"""
	var slots = ["main_hand", "chest"]  # Always have weapon + chest
	
	# Floor 1-2: Main hand + chest only
	
	# Floor 3+: Add head
	if floor >= 3:
		slots.append("head")
	
	# Floor 5+: Add legs
	if floor >= 5:
		slots.append("legs")
	
	# Floor 7+: Add hands
	if floor >= 7:
		slots.append("hands")
	
	# Floor 9+: Add feet (full armor)
	if floor >= 9:
		slots.append("feet")
	
	# Bosses always have full equipment
	if is_boss:
		slots = ["main_hand", "chest", "head", "legs", "hands", "feet"]
	
	return slots

func give_enemy_equipment(enemy: CharacterData, floor: int, is_boss: bool = false):
	var available_slots = get_available_equipment_slots(floor, is_boss)
	var difficulty_tier = get_difficulty_tier(floor)
	
	# Equipment chance scales with floor - guarantee most slots filled on higher floors
	var base_equipment_chance = min(0.70 + (difficulty_tier * 0.05), 1.0)
	var equipment_chance = base_equipment_chance if not is_boss else 1.0
	
	# Guarantee at least 3 armor pieces on floor 5+
	var guaranteed_armor_pieces = 0
	if floor >= 5:
		guaranteed_armor_pieces = 3
	if floor >= 10:
		guaranteed_armor_pieces = 4
	if floor >= 15:
		guaranteed_armor_pieces = 5
	
	# Rarity improves every 3 floors
	var min_rarity_tier = int(floor / 3)
	
	if not enemy.has_meta("equipped_items"):
		enemy.set_meta("equipped_items", [])
	
	var armor_equipped_count = 0
	
	for slot in available_slots:
		var should_equip = is_boss or RandomManager.randf() < equipment_chance
		
		# Force equip armor if we haven't met minimum yet
		if slot != "main_hand" and armor_equipped_count < guaranteed_armor_pieces:
			should_equip = true
		
		if should_equip:
			var item = null
			
			if slot == "main_hand":
				var weapon_id = ItemManager.get_random_weapon()
				if weapon_id:
					item = ItemManager.create_equipment_for_floor(weapon_id, floor, min_rarity_tier)
			else:
				var armor_id = ItemManager.get_random_armor("", slot)
				if armor_id:
					item = ItemManager.create_equipment_for_floor(armor_id, floor, min_rarity_tier)
					if item:
						armor_equipped_count += 1
			
			if item and item is Equipment:
				enemy.equip_item(item)
				
				var rarity_tier = get_rarity_tier(item.rarity)
				if rarity_tier >= 1:
					var equipped_items = enemy.get_meta("equipped_items")
					equipped_items.append(item)
					enemy.set_meta("equipped_items", equipped_items)
				
				print("%s equipped ilvl %d %s: %s (%s)" % [
					enemy.name, 
					item.item_level, 
					slot, 
					item.display_name,
					item.rarity
				])
	
	print("Enemy %s equipped %d armor pieces (minimum: %d)" % [
		enemy.name, armor_equipped_count, guaranteed_armor_pieces
	])

func give_enemy_items(enemy: CharacterData, floor: int, is_boss: bool = false, momentum_level: int = 0):
	var difficulty_tier = get_difficulty_tier(floor)
	var base_item_chance = 0.3 + (difficulty_tier * 0.08)
	var momentum_bonus = momentum_level * 0.1
	var boss_multiplier = 3.0 if is_boss else 1.5
	var total_chance = (base_item_chance + momentum_bonus) * boss_multiplier
	
	var item_count = 0
	if RandomManager.randf() < total_chance:
		item_count = 1
	if RandomManager.randf() < total_chance * 0.5:
		item_count += 1
	if RandomManager.randf() < total_chance * 0.25:
		item_count += 1
	
	# Item pool expands with difficulty tiers
	var available_items = []
	available_items.append_array(["health_potion", "stone_shard"])
	
	if difficulty_tier >= 2:  # Floor 3+
		available_items.append_array(["mana_potion", "stamina_potion"])
	
	if difficulty_tier >= 3:  # Floor 6+
		available_items.append_array(["flame_flask", "venom_vial", "rotten_dung"])
	
	if difficulty_tier >= 5:  # Floor 12+
		available_items.append_array(["frost_crystal", "thunder_orb", "smoke_bomb"])
	
	if difficulty_tier >= 6:  # Floor 15+
		available_items.append_array(["berserker_brew"])
	
	if difficulty_tier >= 7:  # Floor 18+
		available_items.append_array(["holy_water"])
	
	for i in range(item_count):
		if available_items.size() > 0:
			var item_id = available_items[RandomManager.randi() % available_items.size()]
			var item = ItemManager.get_item(item_id)
			if item:
				var quantity = 1 + int(difficulty_tier / 2)
				if is_boss:
					quantity += 1
				enemy.inventory.add_item(item, quantity)
				print("Enemy received %dx %s" % [quantity, item.display_name])

func setup_character(character: CharacterData, character_class: String, class_type: String, race_name: String, race_data: Dictionary):
	"""
	Setup character with race and class data
	race_name: String key like "Goblin", "Elf", etc.
	race_data: Dictionary with stat modifiers like {"vit_mod": -1, "str_mod": 0, ...}
	"""
	print("=== DEBUG setup_character ===")
	print("1. character_class: ", character_class, " (type: ", typeof(character_class), ")")
	print("2. class_type: ", class_type, " (type: ", typeof(class_type), ")")
	print("3. race_name: ", race_name, " (type: ", typeof(race_name), ")")
	print("4. race_data: ", race_data, " (type: ", typeof(race_data), ")")
	
	print("5. classes keys: ", classes.keys())
	print("6. classes[class_type] type: ", typeof(classes[class_type]))
	print("7. classes[class_type] keys: ", classes[class_type].keys())
	
	if not classes[class_type].has(character_class):
		push_error("ERROR: Class '%s' not found in classes['%s']!" % [character_class, class_type])
		return
	
	print("8. classes[class_type][character_class] type: ", typeof(classes[class_type][character_class]))
	
	var class_data = classes[class_type][character_class]
	
	print("9. class_data: ", class_data)

	character.name = "%s %s" % [race_name, character_class]
	character.race = race_name
	character.character_class = character_class

	#  FIX: Use bracket notation for all dictionary access
	print("10. Accessing class_data['base_vit']...")
	character.vitality = class_data["base_vit"] + race_data["vit_mod"]
	character.strength = class_data["base_str"] + race_data["str_mod"]
	character.dexterity = class_data["base_dex"] + race_data["dex_mod"]
	character.intelligence = class_data["base_int"] + race_data["int_mod"]
	character.faith = class_data["base_fai"] + race_data["fai_mod"]
	character.mind = class_data["base_mnd"] + race_data["mnd_mod"]
	character.endurance = class_data["base_end"] + race_data["end_mod"]
	character.arcane = class_data["base_arc"] + race_data["arc_mod"]
	character.agility = class_data["base_agi"] + race_data["agi_mod"]
	character.fortitude = class_data["base_for"] + race_data["for_mod"]

	character.attack_power_type = class_data["attack_power_type"]
	character.spell_power_type = class_data["spell_power_type"]
	character.calculate_secondary_attributes()

	var valid_skills: Array = []
	for skill_name in class_data["skills"]:
		if skills.has(skill_name):
			valid_skills.append(skill_name)

	if valid_skills.size() > 0:
		character.add_skills(valid_skills)

func get_rarity_tier(rarity: String) -> int:
	match rarity:
		"common": return 0
		"uncommon": return 1
		"magic": return 2
		"rare": return 3
		"epic": return 4
		"legendary": return 5
		_: return 0
