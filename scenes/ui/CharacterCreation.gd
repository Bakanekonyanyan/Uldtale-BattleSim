# CharacterCreation.gd
extends Control

var races = {}
var classes = {}

@onready var name_input = $NameInput
@onready var race_option = $RaceOption
@onready var class_option = $ClassOption
@onready var stats_label = $StatsLabel
@onready var create_button = $CreateButton
@onready var cancel_button = $QuitButton

func _ready():
	load_data()
	setup_ui()

func load_data():
	var file = FileAccess.open("res://data/races.json", FileAccess.READ)
	races = JSON.parse_string(file.get_as_text())
	file = FileAccess.open("res://data/classes.json", FileAccess.READ)
	classes = JSON.parse_string(file.get_as_text())

func setup_ui():
	for race in races["playable"].keys():
		race_option.add_item(race)
	for character_class in classes["playable"].keys():
		class_option.add_item(character_class)
	
	race_option.connect("item_selected", Callable(self, "_on_race_selected"))
	class_option.connect("item_selected", Callable(self, "_on_class_selected"))
	create_button.connect("pressed", Callable(self, "_on_create_pressed"))
	cancel_button.connect("pressed", Callable(self, "_on_cancel_pressed"))
	
	update_stats()

func _on_cancel_pressed():
	SceneManager.change_scene("res://scenes/ui/CharacterSelection.tscn")

func _on_race_selected(_index):
	update_stats()

func _on_class_selected(_index):
	update_stats()

func update_stats():
	var selected_race = races["playable"][race_option.get_item_text(race_option.selected)]
	var selected_class = classes["playable"][class_option.get_item_text(class_option.selected)]
	
	var vitality = selected_class.base_vit + selected_race.vit_mod
	var strength = selected_class.base_str + selected_race.str_mod
	var dexterity = selected_class.base_dex + selected_race.dex_mod
	var intelligence = selected_class.base_int + selected_race.int_mod
	var faith = selected_class.base_fai + selected_race.fai_mod
	var mind = selected_class.base_mnd + selected_race.mnd_mod
	var endurance = selected_class.base_end + selected_race.end_mod
	var arcane = selected_class.base_arc + selected_race.arc_mod
	var agility = selected_class.base_agi + selected_race.agi_mod
	var fortitude = selected_class.base_for + selected_race.for_mod
	
	stats_label.text = "VIT: %d\nSTR: %d\nDEX: %d\nINT: %d\nFAI: %d\nMND: %d\nEND: %d\nARC: %d\nAGI: %d\nFOR: %d" % [
		vitality, strength, dexterity, intelligence, faith, mind, endurance, arcane, agility, fortitude
	]

func _on_create_pressed():
	if name_input.text.strip_edges().is_empty():
		print("Please enter a character name")
		return
	
	var new_character = CharacterData.new()
	new_character.name = name_input.text
	new_character.race = race_option.get_item_text(race_option.selected)
	new_character.character_class = class_option.get_item_text(class_option.selected)
	new_character.max_floor_cleared = 1
	var selected_race = races["playable"][new_character.race]
	var selected_class = classes["playable"][new_character.character_class]
	
	# Set attributes
	new_character.vitality = selected_class.base_vit + selected_race.vit_mod
	new_character.strength = selected_class.base_str + selected_race.str_mod
	new_character.dexterity = selected_class.base_dex + selected_race.dex_mod
	new_character.intelligence = selected_class.base_int + selected_race.int_mod
	new_character.faith = selected_class.base_fai + selected_race.fai_mod
	new_character.mind = selected_class.base_mnd + selected_race.mnd_mod
	new_character.endurance = selected_class.base_end + selected_race.end_mod
	new_character.arcane = selected_class.base_arc + selected_race.arc_mod
	new_character.agility = selected_class.base_agi + selected_race.agi_mod
	new_character.fortitude = selected_class.base_for + selected_race.for_mod
	
	new_character.attack_power_type = selected_class.attack_power_type
	new_character.spell_power_type = selected_class.spell_power_type
	
	# Add skills
	for skill_name in selected_class.skills:
		new_character.add_skills(selected_class.skills)
	
	print("Skills added to new character: ", new_character.skills)
	
	new_character.calculate_secondary_attributes()
	
	# Initialize current values to max
	new_character.current_hp = new_character.max_hp
	new_character.current_mp = new_character.max_mp
	new_character.current_sp = new_character.max_sp
	
	
	# FIXED: Use SaveManager.save_game() instead of CharacterManager.save_character()
	SaveManager.save_game(new_character)
	print("Character created: ", new_character.name)
	print("Skills for new character: ", new_character.skills)
	
	# Transition to the next scene (e.g., main game or character selection)
	SceneManager.change_scene("res://scenes/ui/CharacterSelection.tscn")
