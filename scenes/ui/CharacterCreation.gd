# res://scenes/ui/CharacterCreation.gd - REFACTORED to use CharacterFactory
extends Control

var races = {}
var classes = {}

@onready var name_input = $NameInput
@onready var race_option = $RaceOption
@onready var class_option = $ClassOption
@onready var info_display = $InfoDisplay
@onready var create_button = $CreateButton
@onready var cancel_button = $QuitButton

const STARTING_GOLD = 100

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
	
	update_info_display()

func _on_cancel_pressed():
	SceneManager.change_scene("res://scenes/ui/CharacterSelection.tscn")

func _on_race_selected(_index):
	update_info_display()

func _on_class_selected(_index):
	update_info_display()

func update_info_display():
	"""Show comprehensive race + class combo information"""
	var race_name = race_option.get_item_text(race_option.selected)
	var u_class_name = class_option.get_item_text(class_option.selected)
	
	var selected_race = races["playable"][race_name]
	var selected_class = classes["playable"][u_class_name]
	
	# Calculate final attributes
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
	
	# Build comprehensive info text
	var info_text = ""
	
	# === HEADER ===
	info_text += "[center][b][color=gold]%s %s[/color][/b][/center]\n\n" % [race_name, u_class_name]
	
	# === PRIMARY ATTRIBUTES ===
	info_text += "[b][color=cyan]Primary Attributes:[/color][/b]\n"
	info_text += "Vitality: %d | Strength: %d | Dexterity: %d\n" % [vitality, strength, dexterity]
	info_text += "Intelligence: %d | Faith: %d | Mind: %d\n" % [intelligence, faith, mind]
	info_text += "Endurance: %d | Arcane: %d | Agility: %d | Fortitude: %d\n\n" % [endurance, arcane, agility, fortitude]
	
	# === SECONDARY ATTRIBUTES (calculated) ===
	info_text += "[b][color=cyan]Calculated Stats:[/color][/b]\n"
	var max_hp = vitality * 8 + strength * 3
	var max_mp = mind * 5 + intelligence * 3
	var max_sp = endurance * 5 + agility * 3
	info_text += "HP: %d | MP: %d | SP: %d\n\n" % [max_hp, max_mp, max_sp]
	
	# === ELEMENTAL AFFINITIES ===
	info_text += "[b][color=orange]Elemental Affinities:[/color][/b]\n\n"
	
	# Get elemental data from race
	var elemental_data = RaceElementalData.get_race_elemental_data(race_name, true)
	
	# DAMAGE DEALT LIST
	info_text += "[b][color=yellow]Damage Bonuses:[/color][/b]\n"
	var has_damage_bonus = false
	for element in ElementalDamage.Element.values():
		if element == ElementalDamage.Element.NONE:
			continue
		
		var element_name = ElementalDamage.get_element_name(element)
		var element_key = ElementalDamage.Element.keys()[element]
		var color = ElementalDamage.get_element_color(element)
		
		var bonus = 0.0
		if elemental_data.has("damage_bonuses") and elemental_data.damage_bonuses.has(element_key):
			bonus = float(elemental_data.damage_bonuses[element_key])
		
		if bonus > 0.0:
			info_text += "  [color=%s]%s:[/color] [color=lime]+%d%% damage[/color]\n" % [color, element_name, int(bonus * 100)]
			has_damage_bonus = true
	
	if not has_damage_bonus:
		info_text += "  [color=gray]No damage bonuses[/color]\n"
	
	info_text += "\n"
	
	# RESISTANCES AND WEAKNESSES LIST
	info_text += "[b][color=cyan]Resistances & Weaknesses:[/color][/b]\n"
	var has_resistance_data = false
	for element in ElementalDamage.Element.values():
		if element == ElementalDamage.Element.NONE:
			continue
		
		var element_name = ElementalDamage.get_element_name(element)
		var element_key = ElementalDamage.Element.keys()[element]
		var color = ElementalDamage.get_element_color(element)
		
		var resist = 0.0
		var weak = 0.0
		
		if elemental_data.has("resistances") and elemental_data.resistances.has(element_key):
			resist = float(elemental_data.resistances[element_key])
		if elemental_data.has("weaknesses") and elemental_data.weaknesses.has(element_key):
			weak = float(elemental_data.weaknesses[element_key])
		
		# Only show if there's a modifier
		if resist > 0.0 or weak > 0.0:
			var line = "  [color=%s]%s:[/color] " % [color, element_name]
			
			if resist > 0.0:
				line += "[color=cyan]-%d%% damage taken[/color]" % int(resist * 100)
			if weak > 0.0:
				line += "[color=orange]+%d%% damage taken[/color]" % int(weak * 100)
			
			info_text += line + "\n"
			has_resistance_data = true
	
	if not has_resistance_data:
		info_text += "  [color=gray]Normal resistance to all elements[/color]\n"
	
	info_text += "\n"
	
	# === STARTING SKILLS ===
	info_text += "[b][color=yellow]Starting Skills:[/color][/b]\n"
	if selected_class.has("skills"):
		for skill_name in selected_class.skills:
			info_text += "  • %s\n" % skill_name
	
	info_text += "\n[b][color=cyan]Combat Style:[/color][/b]\n"
	info_text += "Attack Power: [color=yellow]%s[/color]-based\n" % selected_class.attack_power_type.capitalize()
	info_text += "Spell Power: [color=yellow]%s[/color]-based\n" % selected_class.spell_power_type.capitalize()
	
	# Display the text
	if info_display and info_display is RichTextLabel:
		info_display.bbcode_enabled = true
		info_display.text = info_text
	elif info_display:
		info_display.text = info_text

func _on_create_pressed():
	if name_input.text.strip_edges().is_empty():
		print("Please enter a character name")
		return
	
	var char_name = name_input.text.strip_edges()
	var race_name = race_option.get_item_text(race_option.selected)
	var p_class_name = class_option.get_item_text(class_option.selected)
	
	# Use CharacterFactory for creation
	var new_character = CharacterFactory.create_character(char_name, race_name, p_class_name, true)
	new_character.max_floor_cleared = 1
	
	# Starting gold
	new_character.currency.copper = STARTING_GOLD
	print("New character starting with %d copper (%s)" % [STARTING_GOLD, new_character.currency.get_formatted()])
	
	# Save the character
	SaveManager.save_game(new_character)
	print("Character created: %s (Level %d %s %s)" % [
		new_character.name, new_character.level, race_name, p_class_name
	])
	
	# Transition to character selection
	SceneManager.change_scene("res://scenes/ui/CharacterSelection.tscn")
