extends Control

signal level_up_complete

var character: CharacterData
var initial_attributes = {}
var attribute_labels = {}

@onready var level_value_label = $MainContainer/LevelContainer/LevelValueLabel
@onready var points_value_label = $MainContainer/PointsValueLabel
@onready var attribute_grid = $MainContainer/AttributeGrid
@onready var done_button = $MainContainer/DoneButton

func _ready():
	print("LevelUpScene: _ready called")
	done_button.connect("pressed", Callable(self, "_on_done_pressed"))

func setup(char1: CharacterData):
	character = char1
	initial_attributes = {
		"vitality": character.vitality,
		"strength": character.strength,
		"dexterity": character.dexterity,
		"intelligence": character.intelligence,
		"faith": character.faith,
		"mind": character.mind,
		"endurance": character.endurance,
		"arcane": character.arcane,
		"agility": character.agility,
		"fortitude": character.fortitude
	}
	setup_attribute_buttons()
	update_ui()

func update_ui():
	if level_value_label:
		level_value_label.text = str(character.level)
	if points_value_label:
		points_value_label.text = str(character.attribute_points)
	done_button.disabled = character.attribute_points > 0
	
	# Update attribute labels
	for attr in attribute_labels:
		attribute_labels[attr].text = "%s: %d" % [attr.capitalize(), character.get(attr)]

func setup_attribute_buttons():
	# Clear existing children
	for child in attribute_grid.get_children():
		child.queue_free()
	
	attribute_labels.clear()
	
	var attributes = ["vitality", "strength", "dexterity", "intelligence", "faith", "mind", "endurance", "arcane", "agility", "fortitude"]
	for attr in attributes:
		var hbox = HBoxContainer.new()
		
		var label = Label.new()
		label.text = "%s: %d" % [attr.capitalize(), character.get(attr)]
		hbox.add_child(label)
		attribute_labels[attr] = label
		
		var minus_button = Button.new()
		minus_button.text = "-"
		minus_button.connect("pressed", Callable(self, "_on_attribute_changed").bind(attr, -1))
		hbox.add_child(minus_button)
		
		var plus_button = Button.new()
		plus_button.text = "+"
		plus_button.connect("pressed", Callable(self, "_on_attribute_changed").bind(attr, 1))
		hbox.add_child(plus_button)
		
		attribute_grid.add_child(hbox)

func _on_attribute_changed(attr: String, change: int):
	if change > 0 and character.attribute_points > 0:
		character.set(attr, character.get(attr) + 1)
		character.attribute_points -= 1
	elif change < 0 and character.get(attr) > initial_attributes[attr]:
		character.set(attr, character.get(attr) - 1)
		character.attribute_points += 1
	update_ui()

func _on_done_pressed():
	print("Level up scene done")
	emit_signal("level_up_complete")
	queue_free()
