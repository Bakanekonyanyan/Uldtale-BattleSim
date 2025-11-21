# res://scenes/battle/systems/TurnController.gd
# REFACTORED: Dynamic N-character turn order system

class_name TurnController
extends Node

signal turn_started(character: CharacterData, is_player: bool)
signal phase_changed(phase: TurnPhase)
signal turn_ended(character: CharacterData)
signal turn_skipped(character: CharacterData, reason: String)

enum TurnPhase { STATUS_EFFECTS, ACTION, END_OF_TURN }

var player: CharacterData
var all_combatants: Array[CharacterData] = []  # Player + all enemies
var turn_queue: Array[CharacterData] = []
var current_phase: TurnPhase = TurnPhase.STATUS_EFFECTS
var turn_number: int = 0
var is_pvp_mode: bool = false

func initialize(p_player: CharacterData, enemies: Array[CharacterData]):
	"""Initialize turn order with player and multiple enemies"""
	player = p_player
	all_combatants.clear()
	all_combatants.append(player)
	all_combatants.append_array(enemies)
	
	turn_number = 0
	
	_determine_turn_order()
	print("TurnController: Initialized - Turn order: %s" % ", ".join(turn_queue.map(func(c): return c.name)))

func _determine_turn_order():
	"""Sort all combatants by agility (highest first)"""
	var combatants_with_roll = []
	
	for combatant in all_combatants:
		if not combatant.is_alive():
			continue
		
		var agi = combatant.agility
		var roll = agi + randf_range(-agi * 0.1, agi * 0.1)
		
		combatants_with_roll.append({
			"character": combatant,
			"roll": roll
		})
	
	# Sort by roll (highest first)
	combatants_with_roll.sort_custom(func(a, b): return a.roll > b.roll)
	
	# Build turn queue
	turn_queue.clear()
	for entry in combatants_with_roll:
		turn_queue.append(entry.character)
	
	# Log turn order
	var order_str = ""
	for i in range(turn_queue.size()):
		var c = turn_queue[i]
		order_str += "%s (AGI: %.1f)" % [c.name, c.agility]
		if i < turn_queue.size() - 1:
			order_str += " → "
	
	print("TurnController: Turn order - %s" % order_str)

func start_first_turn():
	"""Start the first turn of battle"""
	if turn_queue.is_empty():
		push_error("TurnController: Turn queue is empty!")
		return
	
	_start_turn(turn_queue[0])

func _start_turn(character: CharacterData):
	"""Start a character's turn"""
	# Remove dead characters FIRST
	_remove_dead_from_queue()
	
	if turn_queue.is_empty():
		print("TurnController: No combatants left in queue")
		return
	
	# CRITICAL: Validate this specific character is alive
	if not character.is_alive():
		print("TurnController: %s is dead, advancing to next combatant" % character.name)
		# Skip to next without emitting turn_started
		if not turn_queue.is_empty():
			turn_queue.push_back(turn_queue.pop_front())
			if not turn_queue.is_empty():
				_start_turn(turn_queue[0])
		return
	
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

func end_current_turn():
	"""End the current turn and start next"""
	if current_phase != TurnPhase.ACTION:
		print("TurnController: Ending turn from %s phase (skipped/stunned)" % TurnPhase.keys()[current_phase])
	
	var current_actor = get_current_actor()
	if current_actor:
		print("TurnController: Ending turn - %s" % current_actor.name)
		emit_signal("turn_ended", current_actor)
	
	# Remove dead from queue
	_remove_dead_from_queue()
	
	if turn_queue.is_empty():
		print("TurnController: No more combatants in queue!")
		return
	
	#  NEW APPROACH: Track turns per combatant instead of global turn count
	var living_count = turn_queue.size()
	
	# Rotate turn queue (move current actor to back)
	if not turn_queue.is_empty():
		var actor = turn_queue.pop_front()
		
		# Mark that this actor took a turn this round
		if not actor.has_meta("_turn_this_round"):
			actor.set_meta("_turn_this_round", true)
		
		turn_queue.push_back(actor)
	
	# Check if everyone has gone once this round
	var everyone_went = true
	for combatant in turn_queue:
		if not combatant.has_meta("_turn_this_round"):
			everyone_went = false
			break
	
	#  Re-sort only when everyone has acted
	if everyone_went and living_count > 1:
		print("TurnController: Round complete - re-sorting by agility")
		
		# Clear round markers
		for combatant in turn_queue:
			combatant.remove_meta("_turn_this_round")
		
		# Re-determine turn order for next round
		_determine_turn_order()
	
	# Start next turn
	if not turn_queue.is_empty():
		_start_turn(turn_queue[0])
	else:
		print("TurnController: No more combatants in queue!")

func _remove_dead_from_queue():
	"""Remove dead characters from turn queue"""
	var before_count = turn_queue.size()
	turn_queue = turn_queue.filter(func(c): return c.is_alive())
	
	var removed = before_count - turn_queue.size()
	if removed > 0:
		print("TurnController: Removed %d dead combatants from queue" % removed)

func add_combatant(character: CharacterData):
	"""Add a new combatant mid-battle (e.g., summoned ally)"""
	if character in all_combatants:
		return
	
	all_combatants.append(character)
	
	# Insert into turn queue based on agility
	var agi = character.agility
	var inserted = false
	for i in range(turn_queue.size()):
		if agi > turn_queue[i].agility:
			turn_queue.insert(i, character)
			inserted = true
			break
	
	if not inserted:
		turn_queue.append(character)
	
	print("TurnController: Added %s to battle" % character.name)

func remove_combatant(character: CharacterData):
	"""Remove a combatant (e.g., fled, defeated)"""
	all_combatants.erase(character)
	turn_queue.erase(character)
	print("TurnController: Removed %s from battle" % character.name)

func set_pvp_mode(enabled: bool):
	is_pvp_mode = enabled

func skip_turn(character: CharacterData, reason: String):
	"""Skip character's turn (stunned, etc)"""
	print("TurnController: %s's turn skipped - %s" % [character.name, reason])
	emit_signal("turn_skipped", character, reason)
	end_current_turn()

func get_current_actor() -> CharacterData:
	"""Get character whose turn it is"""
	return turn_queue[0] if not turn_queue.is_empty() else null

func is_player_turn() -> bool:
	"""Check if it's player's turn"""
	return get_current_actor() == player

func get_current_phase() -> TurnPhase:
	return current_phase

func get_all_enemies() -> Array[CharacterData]:
	"""Get all living enemy combatants"""
	var enemies: Array[CharacterData] = []
	for c in all_combatants:
		if c != player and c.is_alive():
			enemies.append(c)
	return enemies

func get_all_allies() -> Array[CharacterData]:
	"""Get player and any allies (for future party system)"""
	var allies: Array[CharacterData] = []
	if player.is_alive():
		allies.append(player)
	return allies
