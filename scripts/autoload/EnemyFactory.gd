# EnemyFactory.gd
extends Node

var races = {}
var classes = {}
var skills = {}
var current_dungeon_race: String = ""
var dungeon_race: String = ""

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


var current_floor: int = 0  # Add this at the top with other variables

func set_dungeon_race(floor: int):
	# Only set a new race if we're on a different floor
	if floor != current_floor:
		current_floor = floor
		var non_playable_races = races["non_playable"].keys()
		dungeon_race = non_playable_races[randi() % non_playable_races.size()]
		current_dungeon_race = dungeon_race
		print("Floor %d - Current dungeon race set to: %s" % [floor, current_dungeon_race])
	else:
		print("Floor %d - Keeping current dungeon race: %s" % [floor, current_dungeon_race])

func create_enemy(level: int = 1, floor: int = 1, wave: int = 1) -> CharacterData:
	var enemy = CharacterData.new()
	get_dungeon_race()

	var enemy_classes = classes["non_playable"].keys()
	var chosen_class = enemy_classes[randi() % enemy_classes.size()]

	setup_character(enemy, chosen_class, "non_playable", races["non_playable"][current_dungeon_race])
	enemy.name = "%s %s" % [current_dungeon_race, chosen_class]

	enemy.level = level
	for _i in range(level - 1):
		enemy.level_up()
	
	# Apply enemy scaling based on floor and wave
	apply_enemy_scaling(enemy, floor, wave)
	
	# Chance for equipment on floor 2+
	if floor >= 2:
		give_enemy_equipment(enemy, floor)
	
	# Give consumable items to enemies
	give_enemy_items(enemy, floor)
	
	enemy.is_player = false
	enemy.calculate_secondary_attributes()
	enemy.current_hp = enemy.max_hp
	enemy.current_mp = enemy.max_mp
	enemy.current_sp = enemy.max_sp  # Initialize SP

	return enemy


func create_boss(floor: int = 1, wave: int = 1) -> CharacterData:
	var boss = CharacterData.new()
	
	# Get King class data
	var king_data = classes["boss"]["King"]
	
	# Randomly select a minion class to hybridize with
	var minion_classes = ["Shaman", "Brute", "Minion"]
	var chosen_minion = minion_classes[randi() % minion_classes.size()]
	var minion_data = classes["non_playable"][chosen_minion]
	
	# Setup with hybrid stats (King base + minion modifiers)
	var race_data = races["non_playable"][current_dungeon_race]
	
	boss.name = "%s %s King" % [current_dungeon_race, chosen_minion]
	boss.race = current_dungeon_race
	boss.character_class = "King (%s)" % chosen_minion
	
	# Combine stats: King base + percentage of minion stats
	var minion_contribution = 0.5  # Minion adds 50% of their base stats
	
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
	
	# Increase boss base stats (after hybrid calculation)
	boss.vitality = int(boss.vitality * 2)
	boss.strength = int(boss.strength * 1.5)
	boss.intelligence = int(boss.intelligence * 1.5)
	boss.faith = int(boss.faith * 1.5)
	boss.endurance = int(boss.endurance * 1.5)
	
	# Use King's power types (or could blend these too)
	boss.attack_power_type = king_data.attack_power_type
	boss.spell_power_type = king_data.spell_power_type
	
	# Combine skills from both King and minion class
	var combined_skills: Array = []
	
	# Add King skills
	for skill_name in king_data.skills:
		if skills.has(skill_name):
			combined_skills.append(skill_name)
		else:
			print("Ã¢Å¡Â Ã¯Â¸Â Warning: King skill not found:", skill_name)
	
	# Add minion skills
	for skill_name in minion_data.skills:
		if skills.has(skill_name) and skill_name not in combined_skills:
			combined_skills.append(skill_name)
		elif not skills.has(skill_name):
			print("Ã¢Å¡Â Ã¯Â¸Â Warning: Minion skill not found:", skill_name)
	
	if combined_skills.size() > 0:
		boss.add_skills(combined_skills)
		print("Boss %s has skills: %s" % [boss.name, combined_skills])
	else:
		print("Warning: Boss has no valid skills!")
	
	# Apply enemy scaling based on floor and wave
	apply_enemy_scaling(boss, floor, wave, true)  # true = is_boss
	
	# Bosses always have equipment
	give_enemy_equipment(boss, floor, true)  # true = is_boss
	
	boss.is_player = false
	boss.calculate_secondary_attributes()
	boss.current_hp = boss.max_hp
	boss.current_mp = boss.max_mp
	boss.current_sp = boss.max_sp  # Initialize SP
	
	return boss


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

	# Add valid skills
	var valid_skills: Array = []
	for skill_name in class_data.skills:
		if skills.has(skill_name):
			valid_skills.append(skill_name)
		else:
			print("Ã¢Å¡Â Ã¯Â¸Â Warning: Skill not found in skills.json:", skill_name)

	if valid_skills.size() > 0:
		character.add_skills(valid_skills)
	else:
		print("Enemy", character.name, "has no valid skills assigned.")

# Apply floor and wave scaling to enemy stats
func apply_enemy_scaling(enemy: CharacterData, floor: int, wave: int, is_boss: bool = false):
	# Floor scaling: (floor_number - 1) bonus to all stats
	var floor_bonus = floor - 1
	
	# Wave multiplier: 0.10 * wave_number
	var wave_multiplier = 1.0 + (0.10 * wave)
	
	print("Applying scaling - Floor: %d (bonus: +%d), Wave: %d (multiplier: %.2fx)" % [floor, floor_bonus, wave, wave_multiplier])
	
	# Apply flat floor bonus to all primary stats
	enemy.vitality += floor_bonus
	enemy.strength += floor_bonus
	enemy.dexterity += floor_bonus
	enemy.intelligence += floor_bonus
	enemy.faith += floor_bonus
	enemy.mind += floor_bonus
	enemy.endurance += floor_bonus
	enemy.arcane += floor_bonus
	enemy.agility += floor_bonus
	enemy.fortitude += floor_bonus
	
	# Apply wave multiplier to all primary stats
	enemy.vitality = int(enemy.vitality * wave_multiplier)
	enemy.strength = int(enemy.strength * wave_multiplier)
	enemy.dexterity = int(enemy.dexterity * wave_multiplier)
	enemy.intelligence = int(enemy.intelligence * wave_multiplier)
	enemy.faith = int(enemy.faith * wave_multiplier)
	enemy.mind = int(enemy.mind * wave_multiplier)
	enemy.endurance = int(enemy.endurance * wave_multiplier)
	enemy.arcane = int(enemy.arcane * wave_multiplier)
	enemy.agility = int(enemy.agility * wave_multiplier)
	enemy.fortitude = int(enemy.fortitude * wave_multiplier)
	
	print("%s scaled stats - VIT: %d STR: %d DEX: %d" % [enemy.name, enemy.vitality, enemy.strength, enemy.dexterity])

# Give enemy equipment based on floor and chance
func give_enemy_equipment(enemy: CharacterData, floor: int, is_boss: bool = false):
	# Normal enemies: 30% chance, Bosses: 0% (they're already strong)
	var equipment_chance = 0.7 if not is_boss else 1.0
	
	if randf() < equipment_chance:
		# Give weapon
		var weapon = ItemManager.get_random_weapon()
		if weapon:
			var weapon_item = ItemManager.get_item(weapon)
			if weapon_item and weapon_item is Equipment:
				# Rarity is automatically applied in Equipment._init()
				enemy.equip_item(weapon_item)
				print("%s equipped weapon: %s (rarity: %s)" % [enemy.name, weapon_item.name, weapon_item.rarity])
	
	if randf() < equipment_chance:
		# Give armor (random slot)
		var armor = ItemManager.get_random_armor()
		if armor:
			var armor_item = ItemManager.get_item(armor)
			if armor_item and armor_item is Equipment:
				# Rarity is automatically applied in Equipment._init()
				enemy.equip_item(armor_item)
				print("%s equipped armor: %s (rarity: %s)" % [enemy.name, armor_item.name, armor_item.rarity])
				print("%s equipped armor: %s" % [enemy.name, armor_item.name])

# Give enemy consumable items
func give_enemy_items(enemy: CharacterData, floor: int, is_boss: bool = false):
	# Don't give items to bosses
	if is_boss:
		return
	
	# 40% chance for enemies to have items
	if randf() < 0.4:
		# List of combat consumables enemies can use
		var combat_items = [
			"flame_flask", "frost_crystal", "thunder_orb", 
			"venom_vial", "stone_shard", "rotten_dung",
			"health_potion", "smoke_bomb"
		]
		
		# Give 1-3 random items
		var num_items = randi_range(1, 3)
		for i in num_items:
			var item_id = combat_items[randi() % combat_items.size()]
			var item = ItemManager.get_item(item_id)
			if item:
				# Give 1-3 of each item
				var quantity = randi_range(1, 3)
				enemy.inventory.add_item(item, quantity)
				print("%s received %d x %s" % [enemy.name, quantity, item.name])
