# StatusScene.gd
extends Control

var current_character: CharacterData

@onready var name_label = $NameLabel if has_node("NameLabel") else null
@onready var class_label = $ClassLabel if has_node("ClassLabel") else null
@onready var level_label = $LevelLabel if has_node("LevelLabel") else null
@onready var primary_attributes = $PrimaryAttributes if has_node("PrimaryAttributes") else null
@onready var secondary_attributes = $SecondaryAttributes if has_node("SecondaryAttributes") else null
@onready var equipment_info = $EquipmentInfo if has_node("EquipmentInfo") else null
@onready var exit_button = $ExitButton if has_node("ExitButton") else null

func _ready():
	print("StatusScene: _ready called")
	current_character = CharacterManager.get_current_character()
	if not current_character:
		print("Error: No character loaded")
		return
	update_status()
	
	if exit_button:
		exit_button.connect("pressed", Callable(self, "_on_exit_pressed"))

func set_player(character: CharacterData):
	current_character = character
	update_status()

func update_status():
	print("StatusScene: update_status called")
	if not current_character:
		print("Error: No character data available")
		return
	
	set_label_text(name_label, "Name: " + str(current_character.name))
	set_label_text(class_label, "Class: " + str(current_character.character_class))
	set_label_text(level_label, "Level: " + str(current_character.level))
	
	if primary_attributes:
		set_label_text(primary_attributes, """
		Vitality: %d
		Strength: %d
		Dexterity: %d
		Intelligence: %d
		Faith: %d
		Mind: %d
		Endurance: %d
		Arcane: %d
		Agility: %d
		Fortitude: %d
		""" % [
			current_character.vitality,
			current_character.strength,
			current_character.dexterity,
			current_character.intelligence,
			current_character.faith,
			current_character.mind,
			current_character.endurance,
			current_character.arcane,
			current_character.agility,
			current_character.fortitude
		])
	else:
		print("Error: PrimaryAttributes node not found")
	
	if secondary_attributes:
		set_label_text(secondary_attributes, """
		HP: %d / %d
		MP: %d / %d
		Attack Power: %d
		Spell Power: %d
		Defense: %d
		Toughness: %.2f
		Dodge: %.2f%%
		Spell Ward: %.2f
		Accuracy: %.2f%%
		Crit Rate: %.2f%%
		""" % [
			current_character.current_hp,
			current_character.max_hp,
			current_character.current_mp,
			current_character.max_mp,
			current_character.get_attack_power(),
			current_character.spell_power,
			current_character.get_defense(),
			current_character.toughness,
			current_character.dodge * 100,
			current_character.spell_ward,
			current_character.accuracy * 100,
			current_character.critical_hit_rate * 100
		])
	
	if equipment_info:
		var equipment_text = "Equipment:\n"
		for slot in current_character.equipment:
			var item = current_character.equipment[slot]
			var slot_name = slot.capitalize().replace("_", " ")
			if item:
				equipment_text += "%s: %s\n" % [slot_name, item.name]
			else:
				equipment_text += "%s: Empty\n" % slot_name
		set_label_text(equipment_info, equipment_text)
	
	print("StatusScene: update_status completed")

func set_label_text(label: Label, text: String):
	if label:
		label.text = text
	else:
		print("Warning: Attempted to set text on a null label")

func _on_exit_pressed():
	# Return to the previous scene (likely the town scene)
	SceneManager.change_to_town(current_character)
