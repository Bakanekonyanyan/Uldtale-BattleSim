# res://scenes/battle/components/BattleContext.gd
# Centralized battle state and context data
# Replaces scattered flags and state in BattleOrchestrator

class_name BattleContext
extends RefCounted

# Core data
var player: CharacterData
var enemies: Array[CharacterData] = []

# Dungeon info
var is_boss_battle: bool = false
var current_wave: int = 1
var current_floor: int = 1
var max_floor: int = 1
var dungeon_description: String = ""

# Turn state flags
var item_action_used: bool = false
var main_action_taken: bool = false

# Battle flags
var battle_started: bool = false
var is_pvp_mode: bool = false

func setup(p_player: CharacterData, p_enemies: Array[CharacterData]):
	player = p_player
	enemies = p_enemies
	battle_started = false
	reset_turn_state()

func set_dungeon_info(boss: bool, wave: int, floor: int, max_fl: int, desc: String):
	is_boss_battle = boss
	current_wave = wave
	current_floor = floor
	max_floor = max_fl
	dungeon_description = desc if desc else "Dungeon Floor %d" % floor

func reset_turn_state():
	item_action_used = false
	main_action_taken = false

func get_living_enemies() -> Array[CharacterData]:
	var living: Array[CharacterData] = []
	for e in enemies:
		if e.is_alive():
			living.append(e)
	return living

func is_battle_ended() -> bool:
	return get_living_enemies().is_empty() or not player.is_alive()

func did_player_win() -> bool:
	return get_living_enemies().is_empty() and player.is_alive()
