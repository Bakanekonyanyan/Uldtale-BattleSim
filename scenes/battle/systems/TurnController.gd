# res://scenes/battle/systems/TurnController.gd
# Manages turn order, phases, and timing
# Replaces old TurnManager with improved phase handling

class_name TurnController
extends Node

signal turn_started(character: CharacterData, is_player: bool)
signal phase_changed(phase: TurnPhase)
signal turn_ended(character: CharacterData)
signal turn_skipped(character: CharacterData, reason: String)

enum TurnPhase { STATUS_EFFECTS, ACTION, END_OF_TURN }

var player: CharacterData
var enemy: CharacterData
var turn_queue: Array[CharacterData] = []
var current_phase: TurnPhase = TurnPhase.STATUS_EFFECTS
var turn_number: int = 0
var is_pvp_mode: bool = false


func initialize(p_player: CharacterData, p_enemy: CharacterData):
	"""Initialize turn order based on agility"""
	player = p_player
	enemy = p_enemy
	turn_number = 0
	
	_determine_turn_order()
	print("TurnController: Initialized - Turn order: %s" % ", ".join(turn_queue.map(func(c): return c.name)))

func _determine_turn_order():
	"""Determine who goes first based on agility with randomness"""
	var player_agi = player.agility
	var enemy_agi = enemy.agility
	
	# Add slight random factor (±10% of agility)
	var player_roll = player_agi + randf_range(-player_agi * 0.1, player_agi * 0.1)
	var enemy_roll = enemy_agi + randf_range(-enemy_agi * 0.1, enemy_agi * 0.1)
	
	if enemy_roll > player_roll:
		turn_queue = [enemy, player]
		print("TurnController: Enemy goes first! (AGI: %.1f vs Player: %.1f)" % [enemy_roll, player_roll])
	else:
		turn_queue = [player, enemy]
		print("TurnController: Player goes first! (AGI: %.1f vs Enemy: %.1f)" % [player_roll, enemy_roll])

func start_first_turn():
	"""Start the first turn of battle"""
	_start_turn(turn_queue[0])

func _start_turn(character: CharacterData):
	"""Start a character's turn"""
	current_phase = TurnPhase.STATUS_EFFECTS
	turn_number += 1
	
	var is_player = character == player
	print("TurnController: Turn %d - %s's turn" % [turn_number, character.name])
	
	emit_signal("turn_started", character, is_player)

func advance_phase():
	"""Move to next phase of turn"""
	match current_phase:
		TurnPhase.STATUS_EFFECTS:
			current_phase = TurnPhase.ACTION
		TurnPhase.ACTION:
			current_phase = TurnPhase.END_OF_TURN
		TurnPhase.END_OF_TURN:
			current_phase = TurnPhase.STATUS_EFFECTS
	
	emit_signal("phase_changed", current_phase)

# Replace the end_current_turn() function starting at line 80:
func end_current_turn():
	"""End the current turn and start next"""
	if current_phase != TurnPhase.ACTION:
		push_warning("TurnController: Trying to end turn in wrong phase")
		return
	
	var current_actor = get_current_actor()
	print("TurnController: Ending turn - %s" % current_actor.name)
	
	emit_signal("turn_ended", current_actor)
	
	# ✅ REMOVE PvP check - always advance
	# Rotate turn queue and start next turn
	turn_queue.push_back(turn_queue.pop_front())
	_start_turn(turn_queue[0])

# Add this method at the end of the file (around line 150)
func set_pvp_mode(enabled: bool):
	is_pvp_mode = enabled

func skip_turn(character: CharacterData, reason: String):
	"""Skip character's turn (stunned, etc)"""
	print("TurnController: %s's turn skipped - %s" % [character.name, reason])
	emit_signal("turn_skipped", character, reason)
	
	# Still end turn normally
	end_current_turn()

func get_current_actor() -> CharacterData:
	"""Get character whose turn it is"""
	return turn_queue[0] if not turn_queue.is_empty() else null

func is_player_turn() -> bool:
	"""Check if it's player's turn"""
	return get_current_actor() == player

func get_current_phase() -> TurnPhase:
	return current_phase
