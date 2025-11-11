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
		dungeon_race = non_playable_races[randi() % non_playable_races.size()]
		current_dungeon_race = dungeon_race
		print("Floor %d - Current dungeon race set to: %s" % [floor, current_dungeon_race])
	else:
		print("Floor %d - Keeping current dungeon race: %s" % [floor, current_dungeon_race])

# EnemyFactory.gd - Add momentum parameter to create functions
func create_enemy(level: int = 1, floor: int = 1, wave: int = 1, momentum_level: int = 0) -> CharacterData:
	var enemy = CharacterData.new()
	get_dungeon_race()

	var enemy_classes = classes["non_playable"].keys()
	var chosen_class = enemy_classes[randi() % enemy_classes.size()]

	setup_character(enemy, chosen_class, "non_playable", races["non_playable"][current_dungeon_race])
	enemy.name = "%s %s" % [current_dungeon_race, chosen_class]

	enemy.level = level
	for _i in range(level - 1):
		enemy.level_up()
	
	# Apply momentum scaling to enemies
	apply_enemy_scaling(enemy, floor, wave, false, momentum_level)
	give_enemy_equipment(enemy, floor)
	give_enemy_items(enemy, floor)
	
	enemy.is_player = false
	enemy.calculate_secondary_attributes()
	enemy.current_hp = enemy.max_hp
	enemy.current_mp = enemy.max_mp
	enemy.current_sp = enemy.max_sp

	return enemy

func create_boss(floor: int = 1, wave: int = 1, momentum_level: int = 0) -> CharacterData:
	var boss = CharacterData.new()
	var king_data = classes["boss"]["King"]
	
	var minion_classes = ["Shaman", "Brute", "Minion"]
	var chosen_minion = minion_classes[randi() % minion_classes.size()]
	var minion_data = classes["non_playable"][chosen_minion]
	var race_data = races["non_playable"][current_dungeon_race]
	
	boss.name = "%s %s King" % [current_dungeon_race, chosen_minion]
	boss.race = current_dungeon_race
	boss.character_class = "King (%s)" % chosen_minion
	
	var minion_contribution = 0.5
	boss.vitality = int((king_data.base_vit + race_data.vit_mod) + (minion_data.base_vit * minion_contribution))
	boss.strength = int((king_data.base_str + race_data.str_mod) + (minion_data.base_str * minion_contribution))
	boss.dexterity = int((king_data.base_dex + race_data.dex_mod) + (minion_data.base_dex * minion_contribution))
	boss.intelligence = int((king_data.base_int + race_data.int_mod) + (minion_data.base_int * minion_contribution))
	boss.faith = int((king_data.base_fai + race_data.fai_mod) + (minion_data.base_fai * minion_contribution))
	boss.mind = int((king_data.base_mnd + race_data.mnd_mod) + (minion_data.base_mnd * minion_contribution))
	boss.endurance = int((king_data.base_end + race_data.end_mod) + (minion_data.base_end * minion_contribution))
	boss.arcane = int((king_data.base_arc + race_data.arc_mod) + (minion_data.base_arc * minion_contribution))
	boss.agility = int((king_data.base_agi + race_data.agi_mod) + (minion_data.base_agi * minion_contribution))
	boss.fortitude = int((king_data.base_for + race_data.for_mod) + (minion_data.base_for * minion_contribution))
	
	boss.vitality = int(boss.vitality * 2)
	boss.strength = int(boss.strength * 1.5)
	boss.intelligence = int(boss.intelligence * 1.5)
	boss.faith = int(boss.faith * 1.5)
	boss.endurance = int(boss.endurance * 1.5)
	
	boss.attack_power_type = king_data.attack_power_type
	boss.spell_power_type = king_data.spell_power_type
	
	var combined_skills: Array = []
	for skill_name in king_data.skills:
		if skills.has(skill_name):
			combined_skills.append(skill_name)
	for skill_name in minion_data.skills:
		if skills.has(skill_name) and skill_name not in combined_skills:
			combined_skills.append(skill_name)
	
	if combined_skills.size() > 0:
		boss.add_skills(combined_skills)
	
	# Apply momentum scaling
	apply_enemy_scaling(boss, floor, wave, true, momentum_level)
	give_enemy_equipment(boss, floor, true)
	
	boss.is_player = false
	boss.calculate_secondary_attributes()
	boss.current_hp = boss.max_hp
	boss.current_mp = boss.max_mp
	boss.current_sp = boss.max_sp
	
	return boss

func apply_enemy_scaling(enemy: CharacterData, floor: int, wave: int, is_boss: bool = false, momentum_level: int = 0):
	var floor_bonus = floor - 1
	var wave_multiplier = 1.0 + (0.10 * wave)
	
	# Momentum scaling: enemies also get stronger with momentum
	var momentum_multiplier = 1.0
	if momentum_level > 0:
		momentum_multiplier = 1.0 + (momentum_level * 0.05)  # Same as player: 5% per level
	
	var total_multiplier = wave_multiplier * momentum_multiplier
	
	enemy.vitality = int((enemy.vitality + floor_bonus) * total_multiplier)
	enemy.strength = int((enemy.strength + floor_bonus) * total_multiplier)
	enemy.dexterity = int((enemy.dexterity + floor_bonus) * total_multiplier)
	enemy.intelligence = int((enemy.intelligence + floor_bonus) * total_multiplier)
	enemy.faith = int((enemy.faith + floor_bonus) * total_multiplier)
	enemy.mind = int((enemy.mind + floor_bonus) * total_multiplier)
	enemy.endurance = int((enemy.endurance + floor_bonus) * total_multiplier)
	enemy.arcane = int((enemy.arcane + floor_bonus) * total_multiplier)
	enemy.agility = int((enemy.agility + floor_bonus) * total_multiplier)
	enemy.fortitude = int((enemy.fortitude + floor_bonus) * total_multiplier)
	
	# Log momentum scaling
	if momentum_level > 0:
		print("Enemy scaled with momentum x%d: +%d%% stats" % [momentum_level, int((momentum_multiplier - 1.0) * 100)])

func setup_character(character: CharacterData, character_class: String, class_type: String, race_data: Dictionary):
	var class_data = classes[class_type][character_class]

	character.name = "%s %s" % [race_data.name if race_data.has("name") else "Unknown", character_class]
	character.race = race_data.name if race_data.has("name") else "Unknown"
	character.character_class = character_class

	character.vitality = class_data.base_vit + race_data.vit_mod
	character.strength = class_data.base_str + race_data.str_mod
	character.dexterity = class_data.base_dex + race_data.dex_mod
	character.intelligence = class_data.base_int + race_data.int_mod
	character.faith = class_data.base_fai + race_data.fai_mod
	character.mind = class_data.base_mnd + race_data.mnd_mod
	character.endurance = class_data.base_end + race_data.end_mod
	character.arcane = class_data.base_arc + race_data.arc_mod
	character.agility = class_data.base_agi + race_data.agi_mod
	character.fortitude = class_data.base_for + race_data.for_mod

	character.attack_power_type = class_data.attack_power_type
	character.spell_power_type = class_data.spell_power_type
	character.calculate_secondary_attributes()

	var valid_skills: Array = []
	for skill_name in class_data.skills:
		if skills.has(skill_name):
			valid_skills.append(skill_name)

	if valid_skills.size() > 0:
		character.add_skills(valid_skills)


# NEW: Determine which slots enemy can equip based on floor
func get_available_equipment_slots(floor: int, is_boss: bool) -> Array:
	# Normal enemies unlock slots as floors increase
	var slots = ["main_hand"]  # Always have weapon
	
	if floor >= 2:
		slots.append("chest")  # Floor 2+: chest armor
	if floor >= 3:
		slots.append("head")   # Floor 3+: helmet
	if floor >= 4:
		slots.append("legs")   # Floor 4+: leg armor
	if floor >= 5:
		slots.append("hands")  # Floor 5+: gloves
	if floor >= 6:
		slots.append("feet")   # Floor 6+: boots
	
	# Bosses get one additional slot beyond regular enemies
	if is_boss and slots.size() < 6:
		var all_slots = ["main_hand", "chest", "head", "legs", "hands", "feet"]
		for slot in all_slots:
			if slot not in slots:
				slots.append(slot)
				break  # Only add ONE extra slot
	
	return slots

# ENHANCED: Equipment system with floor-based slots
func give_enemy_equipment(enemy: CharacterData, floor: int, is_boss: bool = false):
	var available_slots = get_available_equipment_slots(floor, is_boss)
	var equipment_chance = 0.7 if not is_boss else 1.0
	
	# Store equipped items for potential drops
	if not enemy.has_meta("equipped_items"):
		enemy.set_meta("equipped_items", [])
	
	for slot in available_slots:
		# Bosses always get equipment, normal enemies have chance
		if is_boss or randf() < equipment_chance:
			var item = null
			
			if slot == "main_hand":
				var weapon_id = ItemManager.get_random_weapon()
				if weapon_id:
					item = ItemManager.get_item(weapon_id)
			else:
				# Get armor for specific slot
				var armor_id = ItemManager.get_random_armor("", slot)
				if armor_id:
					item = ItemManager.get_item(armor_id)
			
			if item and item is Equipment:
				enemy.equip_item(item)
				
				# Track for drops if uncommon or better
				var rarity_tier = get_rarity_tier(item.rarity)
				if rarity_tier >= 1:  # Uncommon or better
					var equipped_items = enemy.get_meta("equipped_items")
					equipped_items.append(item)
					enemy.set_meta("equipped_items", equipped_items)
				
				print("%s equipped %s: %s (rarity: %s)" % [enemy.name, slot, item.name, item.rarity])

func get_rarity_tier(rarity: String) -> int:
	match rarity:
		"common": return 0
		"uncommon": return 1
		"magic": return 2
		"rare": return 3
		"epic": return 4
		"legendary": return 5
		_: return 0

func give_enemy_items(enemy: CharacterData, floor: int, is_boss: bool = false):
	if is_boss:
		return
	
	if randf() < 0.4:
		var combat_items = [
			"flame_flask", "frost_crystal", "thunder_orb", 
			"venom_vial", "stone_shard", "rotten_dung",
			"health_potion", "smoke_bomb"
		]
		
		var num_items = randi_range(1, 3)
		for i in num_items:
			var item_id = combat_items[randi() % combat_items.size()]
			var item = ItemManager.get_item(item_id)
			if item:
				var quantity = randi_range(1, 3)
				enemy.inventory.add_item(item, quantity)
