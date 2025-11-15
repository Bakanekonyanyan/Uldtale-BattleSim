# res://scenes/DungeonScene.gd
# REFACTORED: Now just a transition scene that passes through to Battle
# All dungeon state is managed by DungeonStateManager

extends Control

var player_character: CharacterData

@onready var wave_label = $WaveLabel
@onready var floor_label = $FloorLabel
@onready var dungeon_description_label = $DungeonDescriptionLabel

func _ready():
	print("DungeonScene: _ready called, waiting for start_dungeon")

func set_player(character: CharacterData):
	print("DungeonScene: set_player - ", character.name if character else "NULL")
	player_character = character

func set_player_character(character: CharacterData):
	print("DungeonScene: set_player_character - ", character.name if character else "NULL")
	player_character = character

func start_dungeon(battle_data: Dictionary):
	"""
	Called by SceneManager with complete battle data from DungeonStateManager
	This scene just displays the floor info briefly, then transitions to battle
	"""
	print("DungeonScene: start_dungeon called")
	print("  - Floor: %d, Wave: %d" % [battle_data["current_floor"], battle_data["current_wave"]])
	print("  - Player: ", battle_data["player_character"].name if battle_data["player_character"] else "NULL")
	print("  - Enemy: ", battle_data["enemy"].name if battle_data["enemy"] else "NULL")
	print("  - Boss: ", battle_data["is_boss_fight"])
	
	# Validate
	if not battle_data.has("player_character") or not battle_data["player_character"]:
		push_error("DungeonScene: Missing player_character!")
		SceneManager.change_to_character_selection()
		return
	
	if not battle_data.has("enemy") or not battle_data["enemy"]:
		push_error("DungeonScene: Missing enemy!")
		SceneManager.change_to_character_selection()
		return
	
	player_character = battle_data["player_character"]
	
	# Update UI labels
	update_labels(battle_data)
	
	# Brief display, then transition to battle
	await get_tree().create_timer(0.5).timeout
	
	print("DungeonScene: Transitioning to battle...")
	SceneManager.start_battle(battle_data)

func update_labels(battle_data: Dictionary):
	"""Display current dungeon status"""
	var current_wave = battle_data["current_wave"]
	var current_floor = battle_data["current_floor"]
	var is_boss_fight = battle_data["is_boss_fight"]
	var waves_per_floor = battle_data.get("waves_per_floor", 5)
	
	if wave_label:
		if is_boss_fight:
			wave_label.text = "Boss Battle!"
		else:
			wave_label.text = "Wave: %d / %d" % [current_wave, waves_per_floor]
	
	if floor_label:
		floor_label.text = "Floor: %d" % current_floor
	
	
	print("DungeonScene: Labels updated - Floor %d, Wave %d" % [current_floor, current_wave])
