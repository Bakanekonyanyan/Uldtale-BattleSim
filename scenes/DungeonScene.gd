# res://scenes/DungeonScene.gd
extends Control

var player_character: CharacterData
var current_wave: int = 0
var current_floor: int = 1
var waves_per_floor: int = 5
var is_boss_fight: bool = false
var max_floor: int = 25

@onready var wave_label = $WaveLabel
@onready var floor_label = $FloorLabel
@onready var dungeon_description_label = $DungeonDescriptionLabel

func _ready():
	# CRITICAL FIX: Don't initialize anything here - wait for start_dungeon to be called
	# The SceneManager will call start_dungeon() after the scene is ready
	print("DungeonScene: _ready called, waiting for start_dungeon")

func reset_player_stats():
	player_character.current_hp = player_character.max_hp
	player_character.current_mp = player_character.max_mp
	player_character.current_sp = player_character.max_sp

func set_player(character: CharacterData):
	player_character = character
	update_labels()

func start_dungeon(info: Dictionary = {}):
	print("DungeonScene: start_dungeon called with info: ", info)
	
	if not info.is_empty():
		# Restore from saved state OR start from selected floor
		player_character = info.get("player_character", player_character)
		current_wave = info["current_wave"]
		current_floor = player_character.current_floor
		is_boss_fight = info["is_boss_fight"]
		max_floor = info["max_floor"]
		waves_per_floor = info.get("waves_per_floor", 5)
		print("DungeonScene: Restored state - Wave: ", current_wave, ", Floor: ", current_floor, ", Boss: ", is_boss_fight)
		
		# If we just beat a boss and clicked Continue (not Next Floor)
		# Stay on same floor and reset for next run or show completion
		if is_boss_fight:
			print("DungeonScene: Boss was defeated, checking if player wants to continue")
			if current_floor >= max_floor:
				print("DungeonScene: Max floor reached! Dungeon complete!")
				SceneManager.change_to_town(player_character)
				return
			# Boss beaten but player clicked Continue instead of Next Floor
			# This shouldn't happen as Continue should only show for non-boss
			# But if it does, treat same as Next Floor
			current_floor += 1
			current_wave = 0
			is_boss_fight = false
		
		# Set race for current floor
		EnemyFactory.set_dungeon_race(current_floor)
		update_labels()
		
		# Continue to next wave
		next_wave()
	else:
		# FALLBACK: If info is empty (shouldn't happen from town anymore)
		# Initialize with character from CharacterManager
		player_character = CharacterManager.get_current_character()
		if player_character == null:
			print("Error: No character selected")
			SceneManager.change_to_character_selection()
			return
		
		current_wave = 0
		current_floor = 1
		is_boss_fight = false
		reset_player_stats()
		print("DungeonScene: Starting new dungeon (fallback mode)")
		EnemyFactory.set_dungeon_race(current_floor)
		update_labels()
		next_wave()

func continue_dungeon():
	print("DungeonScene: Continuing dungeon after rewards")
	
	# This method is no longer needed since SceneManager handles floor advancement
	# Just start next wave
	next_wave()
	
func next_wave():
	print("DungeonScene: Starting next wave")
	current_wave += 1
	update_labels()
	
	if current_wave > waves_per_floor:
		is_boss_fight = true
		start_boss_battle()
	else:
		is_boss_fight = false
		start_battle()

func start_battle():
	var enemy = EnemyFactory.create_enemy(1, current_floor, current_wave)
	var battle_data = {
		"player_character": player_character,
		"enemy": enemy,
		"current_wave": current_wave,
		"current_floor": current_floor,
		"is_boss_fight": false,
		"max_floor": max_floor,
		"waves_per_floor": waves_per_floor,
		"description": get_dungeon_description()
	}
	SceneManager.start_battle(battle_data)

func start_boss_battle():
	var boss = EnemyFactory.create_boss(current_floor, current_wave)
	var battle_data = {
		"player_character": player_character,
		"enemy": boss,
		"current_wave": current_wave,
		"current_floor": current_floor,
		"is_boss_fight": true,
		"max_floor": max_floor,
		"waves_per_floor": waves_per_floor,
		"description": get_dungeon_description() + " BOSS BATTLE!"
	}
	SceneManager.start_battle(battle_data)

func get_dungeon_description() -> String:
	match EnemyFactory.current_dungeon_race:
		"Goblin": return "You're in a dark, dank cave. The air is thick with the stench of goblins."
		"Troll": return "The ground trembles beneath your feet. You've stumbled into troll territory."
		"Fairy": return "Glowing lights dance in the air. You've wandered into an enchanted fairy glade."
	return "You're in a mysterious dungeon."

func update_labels():
	if wave_label:
		wave_label.text = "Boss Battle" if is_boss_fight else "Wave: %d / %d" % [current_wave, waves_per_floor]
	if floor_label:
		floor_label.text = "Floor: %d" % current_floor
	if dungeon_description_label:
		dungeon_description_label.text = get_dungeon_description()
