# TownScene.gd
extends Node2D

var current_character: CharacterData

@onready var name_label = $NameLabel
@onready var shop_button = $ShopButton
@onready var dungeon_button = $DungeonButton
@onready var equipment_button = $EquipmentButton
@onready var status_button = $StatusButton

func _ready():
	if shop_button:
		shop_button.connect("pressed", Callable(self, "_on_shop_pressed"))
	if dungeon_button:
		dungeon_button.connect("pressed", Callable(self, "_on_dungeon_pressed"))
	if equipment_button:
		equipment_button.connect("pressed", Callable(self, "_on_equipment_pressed"))
	if status_button:
		status_button.connect("pressed", Callable(self, "_on_status_pressed"))
		
	update_ui()

func set_player(character: CharacterData):
	current_character = character
	print("TownScene: Character set - ", character.name)
	print("TownScene: Inventory items - ", character.inventory.items)
	update_ui()

func update_ui():
	if name_label:
		if current_character:
			name_label.text = "Character: " + current_character.name
		else:
			name_label.text = "No character loaded"
	else:
		print(current_character.name)
		print("Warning: CharacterNameLabel not found in TownScene")

func _on_shop_pressed():
	SceneManager.change_to_shop(current_character)

func _on_dungeon_pressed():
	SceneManager.change_to_dungeon(current_character)

func _on_equipment_pressed():
	SceneManager.change_to_equipment(current_character)

func _on_status_pressed():
	SceneManager.change_to_status(current_character)
