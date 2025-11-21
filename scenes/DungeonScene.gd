# res://scenes/DungeonScene.gd
# REFACTORED: Now just a transition scene that passes through to Battle
# All dungeon state is managed by DungeonStateManager
#  FIXED: Multi-enemy support

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
	 FIXED: Now handles both single enemy (legacy) and multi-enemy arrays
	"""
	print("DungeonScene: start_dungeon called")
	print("  - Floor: %d, Wave: %d" % [battle_data["current_floor"], battle_data["current_wave"]])
	print("  - Player: ", battle_data["player_character"].name if battle_data["player_character"] else "NULL")
	
	#  FIX: Handle both multi-enemy and legacy single enemy
	if battle_data.has("enemies"):
		print("  - Enemies: %d" % battle_data["enemies"].size())
		for enemy in battle_data["enemies"]:
			print("    - %s" % enemy.name)
	elif battle_data.has("enemy"):
		print("  - Enemy: ", battle_data["enemy"].name if battle_data["enemy"] else "NULL")
	
	print("  - Boss: ", battle_data["is_boss_fight"])
	
	# Validate player
	if not battle_data.has("player_character") or not battle_data["player_character"]:
		push_error("DungeonScene: Missing player_character!")
		SceneManager.change_to_character_selection()
		return
	
	#  FIX: Validate enemies (check both formats)
	var has_valid_enemies = false
	
	if battle_data.has("enemies") and not battle_data["enemies"].is_empty():
		has_valid_enemies = true
	elif battle_data.has("enemy") and battle_data["enemy"]:
		has_valid_enemies = true
	
	if not has_valid_enemies:
		push_error("DungeonScene: Missing enemies!")
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
