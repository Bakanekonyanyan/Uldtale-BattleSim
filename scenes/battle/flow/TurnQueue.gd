# res://scenes/battle/flow/TurnQueue.gd
# Answers ONE question: "whose turn is it next?"
#
# - Orders combatants by an agility roll (agility +/- 10%).
# - After every living combatant has acted once (a "round"), it re-rolls the order.
# - Dead combatants are dropped automatically.
#
# It does not run turns, emit gameplay signals or know about UI - the
# BattleOrchestrator's turn loop calls current_actor() / advance().

class_name TurnQueue
extends RefCounted

var player: CharacterData
var heroes: Array[CharacterData] = []   # player + party
var all_combatants: Array[CharacterData] = []
var queue: Array[CharacterData] = []
var turn_number: int = 0
var round_number: int = 1

# Who has acted in the current round. Kept here rather than as metadata on the
# CharacterData, because the player object is reused across battles and the old
# metadata leaked into the next fight.
var _acted_this_round: Dictionary = {}  # CharacterData -> true

func initialize(p_player: CharacterData, enemies: Array[CharacterData], allies: Array[CharacterData] = []) -> void:
	player = p_player
	heroes.clear()
	heroes.append(player)
	heroes.append_array(allies)
	all_combatants.clear()
	all_combatants.append_array(heroes)
	all_combatants.append_array(enemies)
	turn_number = 0
	round_number = 1
	_acted_this_round.clear()
	_roll_turn_order()

## The combatant whose turn it is (null when nobody is left).
func current_actor() -> CharacterData:
	remove_dead()
	return queue[0] if not queue.is_empty() else null

func is_player(character: CharacterData) -> bool:
	return character == player

## The player or one of their party members.
func is_hero(character: CharacterData) -> bool:
	return character in heroes

## Called once at the start of each turn; used for logging/turn counters.
func begin_turn() -> int:
	turn_number += 1
	return turn_number

## Move the current actor to the back. Re-rolls order when the round completes.
func advance() -> void:
	remove_dead()
	if queue.is_empty():
		return

	var actor: CharacterData = queue.pop_front()
	_acted_this_round[actor] = true
	queue.push_back(actor)

	if _everyone_has_acted() and queue.size() > 1:
		round_number += 1
		_acted_this_round.clear()
		print("TurnQueue: Round %d - re-rolling turn order" % round_number)
		_roll_turn_order()

## Someone joining mid-battle (encounter reinforcements) acts from next round.
func join(character: CharacterData, is_hero_side: bool) -> void:
	if character in all_combatants:
		return
	if is_hero_side and not character in heroes:
		heroes.append(character)
	all_combatants.append(character)
	queue.append(character)
	_acted_this_round[character] = true

## A revived hero rejoins at the back of the current round.
func rejoin(character: CharacterData) -> void:
	if character in all_combatants or not character.is_alive():
		return
	all_combatants.append(character)
	queue.append(character)
	_acted_this_round[character] = true

## Heroes that are alive again but out of the order (after a revive).
func rejoin_revived() -> Array[CharacterData]:
	var back: Array[CharacterData] = []
	for h in heroes:
		if h.is_alive() and not h in all_combatants:
			rejoin(h)
			back.append(h)
	return back

func remove(character: CharacterData) -> void:
	all_combatants.erase(character)
	queue.erase(character)
	_acted_this_round.erase(character)

func remove_dead() -> void:
	var before = queue.size()
	queue = queue.filter(func(c): return c.is_alive())
	if queue.size() != before:
		print("TurnQueue: Removed %d dead combatant(s)" % (before - queue.size()))

## Human-readable order, e.g. "Hero (AGI 12) → Goblin (AGI 8)"
func describe_order() -> String:
	var parts: PackedStringArray = []
	for c in queue:
		parts.append("%s (AGI: %d)" % [c.name, c.agility])
	return " → ".join(parts)

# === INTERNAL ===

func _everyone_has_acted() -> bool:
	for c in queue:
		if not _acted_this_round.has(c):
			return false
	return true

func _roll_turn_order() -> void:
	# Roll in a stable order (by name) and use RandomManager rather than the
	# global RNG, so two PvP clients sharing a match seed get the same turn
	# order even though each lists itself as "player" first.
	var ordered: Array[CharacterData] = all_combatants.duplicate()
	ordered.sort_custom(func(a, b): return a.name < b.name)

	var rolls: Array = []
	for c in ordered:
		if not c.is_alive():
			continue
		var agi = float(c.agility)
		rolls.append({"character": c, "roll": agi + RandomManager.randf_range(-agi * 0.1, agi * 0.1)})

	rolls.sort_custom(func(a, b): return a.roll > b.roll)

	queue.clear()
	for entry in rolls:
		queue.append(entry.character)

	print("TurnQueue: Turn order - %s" % describe_order())
