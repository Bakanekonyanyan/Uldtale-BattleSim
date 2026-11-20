# res://scenes/battle/core/BattleContext.gd
# Shared, mutable state for ONE battle.
#
# Every flow component receives the same BattleContext instance, so this is the
# single place to look for "what is the current state of the fight?".
# It holds data only - no UI, no visuals, no turn logic.

class_name BattleContext
extends RefCounted

# --- Combatants ---
var player: CharacterData
## Recruited party members fighting beside the player (0-2, PartyManager)
var allies: Array[CharacterData] = []
var enemies: Array[CharacterData] = []
## Party Link gauge (BattleRules): fills from hits, combos and breaks
var link_gauge: int = 0
## Each enemy's planned next action (EnemyTurnPlanner). Kept here, not on the
## enemy: an action references its actor, so storing it on the enemy would be
## a reference cycle.
var intents: Dictionary = {}
var _rules_ref: WeakRef
## The battle's BattleRules (weak: the rules object holds this context).
var rules: BattleRules:
	get: return _rules_ref.get_ref() if _rules_ref else null
	set(value): _rules_ref = weakref(value) if value else null

# --- Dungeon info (PvE only) ---
var is_boss_battle: bool = false
var current_wave: int = 1
var current_floor: int = 1
var max_floor: int = 1
var dungeon_description: String = ""

# --- Per-turn flags (reset at the start of each player turn) ---
var item_action_used: bool = false
var main_action_taken: bool = false

# --- Battle lifecycle flags ---
var battle_started: bool = false
## Set exactly once when victory/defeat has been decided. Guards against the
## end-of-battle sequence (dialogs, rewards, signals) running twice.
var battle_over: bool = false
var is_pvp_mode: bool = false

func set_dungeon_info(boss: bool, wave: int, floor_num: int, max_fl: int, desc: String) -> void:
	is_boss_battle = boss
	current_wave = wave
	current_floor = floor_num
	max_floor = max_fl
	dungeon_description = desc if desc != "" else "Dungeon Floor %d" % floor_num

func reset_turn_state() -> void:
	item_action_used = false
	main_action_taken = false

## The player's side: the player first, then their party (1-3 heroes).
func get_heroes() -> Array[CharacterData]:
	var heroes: Array[CharacterData] = []
	if player:
		heroes.append(player)
	heroes.append_array(allies)
	return heroes

func is_hero(c: CharacterData) -> bool:
	return c == player or c in allies

func get_living_heroes() -> Array[CharacterData]:
	var living: Array[CharacterData] = []
	for h in get_heroes():
		if h.is_alive():
			living.append(h)
	return living

func get_living_enemies() -> Array[CharacterData]:
	var living: Array[CharacterData] = []
	for e in enemies:
		if e.is_alive():
			living.append(e)
	return living

func is_battle_decided() -> bool:
	return get_living_enemies().is_empty() or get_living_heroes().is_empty()

func did_player_win() -> bool:
	# Losing takes priority (e.g. both sides die from reflected damage)
	return not get_living_heroes().is_empty() and get_living_enemies().is_empty()
