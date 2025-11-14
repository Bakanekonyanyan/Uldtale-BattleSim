# res://scenes/battle/systems/data/ActionResult.gd
# Data class that encapsulates the result of a battle action
# Makes it easier to pass results to UI without tight coupling

class_name ActionResult
extends RefCounted

enum ResultType { SUCCESS, FAILED, MISSED, DODGED, CRITICAL, STUNNED, DEATH }

var success: bool = true
var result_type: ResultType = ResultType.SUCCESS
var message: String = ""
var damage_dealt: int = 0
var healing_done: int = 0
var mp_cost: int = 0
var sp_cost: int = 0
var status_applied: Array[Skill.StatusEffect] = []
var actor: CharacterData
var targets: Array[CharacterData] = []
var level_up_message: String = ""

# Helper constructors
static func success_msg(msg: String) -> ActionResult:
	var result = ActionResult.new()
	result.success = true
	result.message = msg
	return result

static func failure_msg(msg: String) -> ActionResult:
	var result = ActionResult.new()
	result.success = false
	result.result_type = ResultType.FAILED
	result.message = msg
	return result

static func attack_result(attacker: CharacterData, target: CharacterData, damage: int, is_crit: bool = false) -> ActionResult:
	var result = ActionResult.new()
	result.success = true
	result.actor = attacker
	result.targets.append(target)
	result.damage_dealt = damage
	result.result_type = ResultType.CRITICAL if is_crit else ResultType.SUCCESS
	
	var momentum_mult = MomentumSystem.get_damage_multiplier()
	result.message = "%s attacks %s for %d damage" % [attacker.name, target.name, damage]
	
	if momentum_mult > 1.0:
		var bonus_pct = int((momentum_mult - 1.0) * 100)
		result.message += " (+%d%% momentum)" % bonus_pct
	
	if is_crit:
		result.message = "Critical hit! " + result.message
	
	return result

static func missed_attack(attacker: CharacterData, target: CharacterData) -> ActionResult:
	var result = ActionResult.new()
	result.success = false
	result.result_type = ResultType.MISSED
	result.actor = attacker
	result.targets.append(target)
	result.message = "%s's attack missed!" % attacker.name
	return result

static func dodged_attack(attacker: CharacterData, target: CharacterData) -> ActionResult:
	var result = ActionResult.new()
	result.success = false
	result.result_type = ResultType.DODGED
	result.actor = attacker
	result.targets.append(target)
	result.message = "%s dodged the attack!" % target.name
	return result

static func defend_result(defender: CharacterData) -> ActionResult:
	var result = ActionResult.new()
	result.success = true
	result.actor = defender
	result.message = "%s takes a defensive stance" % defender.name
	return result

static func skill_result(caster: CharacterData, skill: Skill, targets_arr: Array[CharacterData], msg: String) -> ActionResult:
	var result = ActionResult.new()
	result.success = true
	result.actor = caster
	result.targets = targets_arr
	result.message = msg
	result.mp_cost = skill.mp_cost
	result.sp_cost = skill.sp_cost
	return result

static func item_result(user: CharacterData, item: Item, targets_arr: Array, msg: String) -> ActionResult:
	var result = ActionResult.new()
	result.success = true
	result.actor = user
	result.targets = targets_arr
	result.message = msg
	return result

func get_log_color() -> String:
	"""Get color for combat log based on result type"""
	match result_type:
		ResultType.SUCCESS:
			return "white"
		ResultType.CRITICAL:
			return "orange"
		ResultType.MISSED, ResultType.FAILED:
			return "gray"
		ResultType.DODGED:
			return "cyan"
		ResultType.STUNNED:
			return "purple"
		ResultType.DEATH:
			return "red"
	return "white"

func has_level_up() -> bool:
	return level_up_message != ""
