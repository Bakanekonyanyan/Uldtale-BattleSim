# res://scenes/battle/systems/data/BattleAction.gd
# REFACTORED: Single source of truth - targets array only
class_name BattleAction
extends RefCounted

enum ActionType { ATTACK, SKILL, ITEM, DEFEND, VIEW_EQUIPMENT }

var type: ActionType
var actor: CharacterData
var targets: Array[CharacterData] = []  # PRIMARY - always use this
var skill_data: Skill
var item_data: Item

# COMPUTED PROPERTY: Convenience accessor for single-target actions
var primary_target: CharacterData:
	get:
		return targets[0] if targets.size() > 0 else null
	set(value):
		if value:
			targets.clear()
			targets.append(value)

# DEPRECATED: For backwards compatibility only - remove after migration
var target: CharacterData:
	get:
		push_warning("BattleAction.target is deprecated - use primary_target or targets array")
		return primary_target
	set(value):
		push_warning("BattleAction.target is deprecated - use primary_target or targets array")
		primary_target = value

# ===== FACTORY METHODS =====

static func attack(actor: CharacterData, target: CharacterData) -> BattleAction:
	var action = BattleAction.new()
	action.type = ActionType.ATTACK
	action.actor = actor
	action.targets.append(target)
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
	
	# Add all valid targets
	for t in targets_array:
		if t is CharacterData:
			action.targets.append(t)
	
	return action

static func item(actor: CharacterData, item_inst: Item, targets_array: Array) -> BattleAction:
	var action = BattleAction.new()
	action.type = ActionType.ITEM
	action.actor = actor
	action.item_data = item_inst
	
	# Add all valid targets
	for t in targets_array:
		if t is CharacterData:
			action.targets.append(t)
	
	return action

static func view_equipment(actor: CharacterData, target: CharacterData) -> BattleAction:
	var action = BattleAction.new()
	action.type = ActionType.VIEW_EQUIPMENT
	action.actor = actor
	action.targets.append(target)
	return action

# ===== VALIDATION =====

func is_valid() -> bool:
	"""Check if action has required data"""
	if not actor or not actor.is_alive():
		return false
	
	match type:
		ActionType.ATTACK, ActionType.VIEW_EQUIPMENT:
			# Single-target actions need exactly one target
			return targets.size() == 1 and targets[0] != null
		
		ActionType.SKILL:
			# ALL_ALLIES skills are valid with empty targets (resolved in CombatEngine)
			if skill_data and skill_data.target == Skill.TargetType.ALL_ALLIES:
				return true
			
			# All other skills need non-empty targets
			return skill_data != null and not targets.is_empty()
		
		ActionType.ITEM:
			# Items need targets
			return item_data != null and not targets.is_empty()
		
		ActionType.DEFEND:
			# Defend needs no targets
			return true
	
	return false

# ===== UTILITY =====

func get_description() -> String:
	"""Get human-readable description"""
	match type:
		ActionType.ATTACK:
			return "%s attacks %s" % [actor.name, primary_target.name if primary_target else "???"]
		ActionType.SKILL:
			var target_desc = "ALL" if targets.size() > 1 else (primary_target.name if primary_target else "self")
			return "%s uses %s on %s" % [actor.name, skill_data.name, target_desc]
		ActionType.ITEM:
			var target_desc = "ALL" if targets.size() > 1 else (primary_target.name if primary_target else "???")
			return "%s uses %s on %s" % [actor.name, item_data.display_name, target_desc]
		ActionType.DEFEND:
			return "%s defends" % actor.name
		ActionType.VIEW_EQUIPMENT:
			return "%s views %s's equipment" % [actor.name, primary_target.name if primary_target else "???"]
	return "Unknown action"

func has_multiple_targets() -> bool:
	"""Check if this action targets multiple entities"""
	return targets.size() > 1

func get_target_count() -> int:
	"""Get number of targets"""
	return targets.size()
