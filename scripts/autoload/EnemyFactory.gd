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
	print(dungeon_race)
	current_dungeon_race = dungeon_race
	if current_dungeon_race == "":
		set_dungeon_race()

func set_dungeon_race():
	var non_playable_races = races["non_playable"].keys()
	dungeon_race = non_playable_races[randi() % non_playable_races.size()]
	print("Current dungeon race set to: ", current_dungeon_race)


func create_enemy(level: int = 1) -> CharacterData:
	var enemy = CharacterData.new()
	get_dungeon_race()
	
	var enemy_classes = classes["non_playable"].keys()
	var chosen_class = enemy_classes[randi() % enemy_classes.size()]
	
	setup_character(enemy, chosen_class, "non_playable", races["non_playable"][current_dungeon_race])
	
	enemy.name = "%s %s" % [current_dungeon_race, chosen_class]
	
	enemy.level = level
	for _i in range(level - 1):
		enemy.level_up()
	
	enemy.is_player = false
	
	return enemy

func create_boss() -> CharacterData:
	var boss = CharacterData.new()
	
	setup_character(boss, "King", "boss", races["non_playable"][current_dungeon_race])
	boss.name = "%s King" % current_dungeon_race
	
	# Increase boss stats
	boss.vitality *= 2
	boss.strength *= 1.5
	boss.calculate_secondary_attributes()
	
	return boss
	

func setup_character(character: CharacterData, character_class: String, class_type: String, race_data: Dictionary):
	var class_data = classes[class_type][character_class]
	
	character.name = "Goblin " + character_class
	character.race = "Goblin"
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
	
	# Add skills
	for skill_name in class_data.skills:
		if skills.has(skill_name):
			var new_skills = []
			character.add_skills(new_skills)
		else:
			print("Warning: Skill not found: ", skill_name)
