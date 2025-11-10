# res://scripts/combat/TurnManager.gd
class_name TurnManager
extends RefCounted

signal turn_started(character: CharacterData)
signal turn_ended(character: CharacterData)
signal turn_skipped(character: CharacterData, reason: String)

enum TurnPhase { STATUS_EFFECTS, ACTION, END }

var current_turn: String = "player"
var turn_number: int = 0
var current_phase: TurnPhase = TurnPhase.STATUS_EFFECTS

# Store references to both characters
var player_character: CharacterData
var enemy_character: CharacterData

func initialize(player: CharacterData, enemy: CharacterData):
	player_character = player
	enemy_character = enemy

func start_turn(character: CharacterData):
	current_phase = TurnPhase.STATUS_EFFECTS
	turn_started.emit(character)

func advance_phase():
	match current_phase:
		TurnPhase.STATUS_EFFECTS:
			current_phase = TurnPhase.ACTION
		TurnPhase.ACTION:
			current_phase = TurnPhase.END
		TurnPhase.END:
			current_phase = TurnPhase.STATUS_EFFECTS

func end_turn(character: CharacterData):
	turn_ended.emit(character)
	turn_number += 1
	toggle_turn()
	
	# CRITICAL FIX: Start the next character's turn
	var next_character = get_current_character()
	if next_character:
		start_turn(next_character)

func toggle_turn():
	current_turn = "enemy" if current_turn == "player" else "player"

func skip_turn(character: CharacterData, reason: String):
	turn_skipped.emit(character, reason)

func is_player_turn() -> bool:
	return current_turn == "player"

func get_current_character() -> CharacterData:
	return player_character if is_player_turn() else enemy_character
