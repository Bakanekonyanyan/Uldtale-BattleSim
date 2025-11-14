# res://scenes/battle/systems/data/BattleAction.gd
class_name BattleAction
extends RefCounted

enum ActionType { ATTACK, SKILL, ITEM, DEFEND, VIEW_EQUIPMENT }

var type: ActionType
var actor: CharacterData
var target: CharacterData
var targets: Array[CharacterData] = []  # ✅ Typed array
var skill_data: Skill
var item_data: Item

# Factory methods for type-safe creation
static func attack(actor: CharacterData, target: CharacterData) -> BattleAction:
	var action = BattleAction.new()
	action.type = ActionType.ATTACK
	action.actor = actor
	action.target = target
	action.targets.append(target)  # ✅ Append instead of assign
	return action

static func defend(actor: CharacterData) -> BattleAction:
	var action = BattleAction.new()
	action.type = ActionType.DEFEND
	action.actor = actor
	return action

static func skill(actor: CharacterData, skill_inst: Skill, targets_array: Array) -> BattleAction:
	var action = BattleAction.new()
	action.type = ActionType.SKILL
	action.actor = actor
	action.skill_data = skill_inst
	
	# Append to existing typed array (don't reassign)
	for t in targets_array:
		if t is CharacterData:
			action.targets.append(t)
	
	if action.targets.size() > 0:
		action.target = action.targets[0]
	return action

static func item(actor: CharacterData, item_inst: Item, targets_array: Array) -> BattleAction:
	var action = BattleAction.new()
	action.type = ActionType.ITEM
	action.actor = actor
	action.item_data = item_inst
	
	# Append to existing typed array (don't reassign)
	for t in targets_array:
		if t is CharacterData:
			action.targets.append(t)
	
	if action.targets.size() > 0:
		action.target = action.targets[0]
	return action

static func view_equipment(actor: CharacterData, target: CharacterData) -> BattleAction:
	var action = BattleAction.new()
	action.type = ActionType.VIEW_EQUIPMENT
	action.actor = actor
	action.target = target
	return action

func is_valid() -> bool:
	"""Check if action has required data"""
	if not actor or not actor.is_alive():
		return false
	
	match type:
		ActionType.ATTACK, ActionType.VIEW_EQUIPMENT:
			return target != null
		ActionType.SKILL:
			return skill_data != null and not targets.is_empty()
		ActionType.ITEM:
			return item_data != null and not targets.is_empty()
		ActionType.DEFEND:
			return true
	
	return false

func get_description() -> String:
	"""Get human-readable description"""
	match type:
		ActionType.ATTACK:
			return "%s attacks %s" % [actor.name, target.name]
		ActionType.SKILL:
			return "%s uses %s" % [actor.name, skill_data.name]
		ActionType.ITEM:
			return "%s uses %s" % [actor.name, item_data.name]
		ActionType.DEFEND:
			return "%s defends" % actor.name
		ActionType.VIEW_EQUIPMENT:
			return "%s views %s's equipment" % [actor.name, target.name]
	return "Unknown action"
