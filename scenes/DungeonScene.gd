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

func continue_dungeon():
	print("DungeonScene: Continuing dungeon after rewards")
	
	# This method is no longer needed since SceneManager handles floor advancement
	# Just start next wave
	next_wave()
	
func start_battle():
	var momentum_level = MomentumSystem.get_momentum()
	var enemy = EnemyFactory.create_enemy(1, current_floor, current_wave, momentum_level)
	
	if momentum_level < 1:
		reset_player_stats()
	
	var battle_data = {
		"player_character": player_character,
		"enemy": enemy,
		"current_wave": current_wave,
		"current_floor": current_floor,
		"is_boss_fight": false,
		"max_floor": max_floor,
		"waves_per_floor": waves_per_floor,
		"description": get_dungeon_description(),
		"momentum_level": momentum_level
	}
	SceneManager.start_battle(battle_data)

func start_boss_battle():
	var momentum_level = MomentumSystem.get_momentum()
	var boss = EnemyFactory.create_boss(current_floor, current_wave, momentum_level)
	
	var battle_data = {
		"player_character": player_character,
		"enemy": boss,
		"current_wave": current_wave,
		"current_floor": current_floor,
		"is_boss_fight": true,
		"max_floor": max_floor,
		"waves_per_floor": waves_per_floor,
		"description": get_dungeon_description() + " BOSS BATTLE!",
		"momentum_level": momentum_level
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

func start_dungeon(info: Dictionary = {}):
	print("DungeonScene: start_dungeon called with info: ", info)
	
	if not info.is_empty():
		# Restore from saved state OR start from selected floor
		player_character = info.get("player_character", player_character)
		current_wave = info["current_wave"]
		current_floor = info["current_floor"]
		is_boss_fight = info["is_boss_fight"]
		max_floor = info["max_floor"]
		waves_per_floor = info.get("waves_per_floor", 5)
		
		print("DungeonScene: Restored state - Wave: %d, Floor: %d, Boss: %s, max_floor_cleared: %d" % [
			current_wave,
			current_floor,
			is_boss_fight,
			player_character.max_floor_cleared
		])
		
		# CRITICAL FIX: If boss was just defeated, advance to next floor
		if is_boss_fight and current_wave > waves_per_floor:
			print("DungeonScene: Boss defeated! Advancing to next floor...")
			
			# CRITICAL FIX: Update max_floor_cleared BEFORE advancing
			if current_floor > player_character.max_floor_cleared:
				player_character.update_max_floor_cleared(current_floor)
				SaveManager.save_game(player_character)
				print("DungeonScene: NEW RECORD! Updated max_floor_cleared to %d and saved" % player_character.max_floor_cleared)
			
			current_floor += 1
			current_wave = 0
			is_boss_fight = false
			
			# Check max floor
			if current_floor > max_floor:
				print("DungeonScene: Max floor reached! Dungeon complete!")
				SceneManager.change_to_town(player_character)
				return
			
			print("DungeonScene: Now on Floor %d (player max_floor_cleared: %d)" % [
				current_floor,
				player_character.max_floor_cleared
			])
		
		# CRITICAL FIX: Sync player_character.current_floor with DungeonScene.current_floor
		player_character.current_floor = current_floor
		print("DungeonScene: Player floor synced to: %d" % player_character.current_floor)
		
		# Set race for current floor
		EnemyFactory.set_dungeon_race(current_floor)
		update_labels()
		
		# Continue to next wave
		next_wave()
	else:
		# FALLBACK: If info is empty
		player_character = CharacterManager.get_current_character()
		if player_character == null:
			print("Error: No character selected")
			SceneManager.change_to_character_selection()
			return
		
		current_wave = 0
		current_floor = 1
		is_boss_fight = false
		
		# CRITICAL FIX: Sync player floor
		player_character.current_floor = current_floor
		
		reset_player_stats()
		print("DungeonScene: Starting new dungeon (fallback mode)")
		EnemyFactory.set_dungeon_race(current_floor)
		update_labels()
		next_wave()

func next_wave():
	print("DungeonScene: Starting next wave")
	current_wave += 1
	
	# CRITICAL FIX: Always keep player_character.current_floor in sync
	player_character.current_floor = current_floor
	print("DungeonScene: Floor synced - DungeonScene.current_floor=%d, player.current_floor=%d" % [
		current_floor, 
		player_character.current_floor
	])
	
	update_labels()
	
	if current_wave > waves_per_floor:
		is_boss_fight = true
		start_boss_battle()
	else:
		is_boss_fight = false
		start_battle()
