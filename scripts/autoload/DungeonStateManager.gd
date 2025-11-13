# DungeonStateManager.gd
# Autoload: Add to project.godot as DungeonStateManager
# Handles ALL dungeon state - removes this responsibility from SceneManager

extends Node

signal floor_changed(new_floor: int)
signal wave_changed(new_wave: int)
signal boss_spawned()

# Dungeon state
var current_floor: int = 1
var current_wave: int = 0
var waves_per_floor: int = 5
var max_floor: int = 25
var is_boss_fight: bool = false

# Battle context
var active_player: CharacterData
var active_enemy: CharacterData

# Persistent state
var dungeon_active: bool = false

func start_dungeon(player: CharacterData, start_floor: int = 1):
	"""Initialize a new dungeon run"""
	active_player = player
	current_floor = start_floor
	current_wave = 0
	is_boss_fight = false
	dungeon_active = true
	
	# Sync player's floor
	player.current_floor = start_floor
	
	print("DungeonState: Started dungeon at floor %d" % current_floor)
	emit_signal("floor_changed", current_floor)

func advance_wave() -> Dictionary:
	"""Move to next wave and return battle data"""
	current_wave += 1
	
	# Check if boss wave
	if current_wave > waves_per_floor:
		is_boss_fight = true
		emit_signal("boss_spawned")
		print("DungeonState: Boss wave!")
	else:
		is_boss_fight = false
		emit_signal("wave_changed", current_wave)
	
	# Generate enemy
	var momentum = MomentumSystem.get_momentum()
	if is_boss_fight:
		active_enemy = EnemyFactory.create_boss(current_floor, current_wave, momentum)
	else:
		active_enemy = EnemyFactory.create_enemy(1, current_floor, current_wave, momentum)
	
	return get_battle_data()

func advance_floor() -> bool:
	"""Move to next floor. Returns false if max floor reached."""
	if current_floor >= max_floor:
		print("DungeonState: Max floor reached!")
		return false
	
	current_floor += 1
	current_wave = 0
	is_boss_fight = false
	
	# Sync player's floor
	if active_player:
		active_player.current_floor = current_floor
	
	# Update max cleared if needed
	if active_player and current_floor - 1 > active_player.max_floor_cleared:
		active_player.update_max_floor_cleared(current_floor - 1)
	
	EnemyFactory.set_dungeon_race(current_floor)
	
	print("DungeonState: Advanced to floor %d" % current_floor)
	emit_signal("floor_changed", current_floor)
	return true

func get_battle_data() -> Dictionary:
	"""Get current battle context"""
	return {
		"player_character": active_player,
		"enemy": active_enemy,
		"current_wave": current_wave,
		"current_floor": current_floor,
		"is_boss_fight": is_boss_fight,
		"max_floor": max_floor,
		"waves_per_floor": waves_per_floor,
		"momentum_level": MomentumSystem.get_momentum(),
		"description": get_dungeon_description()
	}

func get_dungeon_description() -> String:
	"""Get flavor text for current dungeon"""
	var base = ""
	match EnemyFactory.current_dungeon_race:
		"Goblin": base = "You're in a dark, dank cave. The air is thick with the stench of goblins."
		"Troll": base = "The ground trembles beneath your feet. You've stumbled into troll territory."
		"Fairy": base = "Glowing lights dance in the air. You've wandered into an enchanted fairy glade."
		_: base = "You're in a mysterious dungeon."
	
	if is_boss_fight:
		base += " [color=red][b]BOSS BATTLE![/b][/color]"
	
	return base

func end_dungeon():
	"""Clean up dungeon state"""
	dungeon_active = false
	current_wave = 0
	current_floor = 1
	is_boss_fight = false
	active_enemy = null
	print("DungeonState: Dungeon ended")

func get_state_summary() -> String:
	"""Debug: Print current state"""
	return "Floor %d, Wave %d/%d, Boss: %s, Active: %s" % [
		current_floor,
		current_wave,
		waves_per_floor,
		is_boss_fight,
		dungeon_active
	]
