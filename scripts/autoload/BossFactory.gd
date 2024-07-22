# res://scripts/autoload/BossFactory.gd
extends Node

var races = {}
var classes = {}
var boss_stat_multiplier = 1.5  # Bosses will have 50% more stats

func _ready():
	load_data()

func load_data():
	var file = FileAccess.open("res://data/races.json", FileAccess.READ)
	races = JSON.parse_string(file.get_as_text())
	file = FileAccess.open("res://data/classes.json", FileAccess.READ)
	classes = JSON.parse_string(file.get_as_text())

func create_boss() -> CharacterData:
	var boss = CharacterData.new()
	
	# Randomly select a race from all available races (playable and non-playable)
	var all_races = races["playable"].keys() + races["non_playable"].keys()
	var race_name = all_races[randi() % all_races.size()]
	var race_data = races["playable"].get(race_name, races["non_playable"].get(race_name))
	
	# Randomly select a class from all available classes
	var all_classes = classes["playable"].keys() + classes["non_playable"].keys()
	var chosen_class_name = all_classes[randi() % all_classes.size()]
	var class_data = classes["playable"].get(chosen_class_name, classes["non_playable"].get(chosen_class_name))
	
	# Set boss name
	boss.name = "Boss " + race_name + " " + chosen_class_name
	boss.race = race_name
	boss.character_class = chosen_class_name
	
	# Set and increase stats
	boss.vitality = int((class_data.base_vit + race_data.vit_mod) * boss_stat_multiplier)
	boss.strength = int((class_data.base_str + race_data.str_mod) * boss_stat_multiplier)
	boss.dexterity = int((class_data.base_dex + race_data.dex_mod) * boss_stat_multiplier)
	boss.intelligence = int((class_data.base_int + race_data.int_mod) * boss_stat_multiplier)
	boss.faith = int((class_data.base_fai + race_data.fai_mod) * boss_stat_multiplier)
	boss.mind = int((class_data.base_mnd + race_data.mnd_mod) * boss_stat_multiplier)
	boss.endurance = int((class_data.base_end + race_data.end_mod) * boss_stat_multiplier)
	boss.arcane = int((class_data.base_arc + race_data.arc_mod) * boss_stat_multiplier)
	boss.agility = int((class_data.base_agi + race_data.agi_mod) * boss_stat_multiplier)
	boss.fortitude = int((class_data.base_for + race_data.for_mod) * boss_stat_multiplier)
	
	# Set attack and spell power types
	boss.attack_power_type = class_data.attack_power_type
	boss.spell_power_type = class_data.spell_power_type
	
	# Calculate secondary attributes
	boss.calculate_secondary_attributes()
	
	# Add skills
	for skill in class_data.skills:
		boss.add_skill(skill)
	
	return boss
