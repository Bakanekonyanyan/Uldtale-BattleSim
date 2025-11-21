# res://scripts/battle/ActionResult.gd
# Represents the result of a battle action
class_name ActionResult
extends RefCounted

var success: bool = false
var message: String = ""
var level_up_message: String = ""

# Damage/healing values
var damage: int = 0
var healing: int = 0
var sp_cost: int = 0
var mp_cost: int = 0
var sp_gain: int = 0
var mp_gain: int = 0

# Effects
var status_effects: Array = []  # [{name: String, duration: int}] - effects APPLIED
var status_effects_removed: Array = []  # [{name: String}] - effects REMOVED (for cure items)
var buffs: Array = []  # [{stat: String, amount: int, duration: int}]
var debuffs: Array = []  # [{stat: String, amount: int, duration: int}]

# Metadata
var is_critical: bool = false
var was_dodged: bool = false
var was_missed: bool = false

# === FACTORY METHODS ===

static func success_msg(msg: String) -> ActionResult:
	var result = ActionResult.new()
	result.success = true
	result.message = msg
	return result

static func failure_msg(msg: String) -> ActionResult:
	var result = ActionResult.new()
	result.success = false
	result.message = msg
	return result

static func attack_result(attacker: CharacterData, target: CharacterData, dmg: int, is_crit: bool = false) -> ActionResult:
	var result = ActionResult.new()
	result.success = true
	result.damage = dmg
	result.is_critical = is_crit
	
	var crit_text = " CRITICAL HIT!" if is_crit else ""
	result.message = "%s attacks %s for %d damage%s" % [
		attacker.name,
		target.name,
		dmg,
		crit_text
	]
	
	return result

static func defend_result(defender: CharacterData) -> ActionResult:
	var result = ActionResult.new()
	result.success = true
	result.message = "%s defends, increasing defense temporarily" % defender.name
	return result

static func skill_result(caster: CharacterData, skill: Skill, targets: Array, skill_msg: String) -> ActionResult:
	var result = ActionResult.new()
	result.success = true
	result.message = skill_msg
	result.sp_cost = skill.sp_cost
	result.mp_cost = skill.mp_cost
	
	# Extract skill effects from skill data (NOT from message)
	_extract_skill_effects(result, skill, skill_msg)
	
	return result

static func item_result(user: CharacterData, item, targets: Array, item_msg: String) -> ActionResult:
	var result = ActionResult.new()
	result.success = true
	result.message = item_msg
	
	# Parse item effects from message
	_extract_item_effects(result, item, item_msg, targets)
	
	return result

static func missed_attack(attacker: CharacterData, target: CharacterData) -> ActionResult:
	var result = ActionResult.new()
	result.success = false
	result.was_missed = true
	result.message = "%s's attack missed %s!" % [attacker.name, target.name]
	return result

static func dodged_attack(attacker: CharacterData, target: CharacterData) -> ActionResult:
	var result = ActionResult.new()
	result.success = false
	result.was_dodged = true
	result.message = "%s dodged %s's attack!" % [target.name, attacker.name]
	return result

static func status_effect_result(character: CharacterData, dmg: int, heal: int, msg: String) -> ActionResult:
	"""Create result for status effect damage/healing"""
	var result = ActionResult.new()
	result.success = true
	result.message = msg
	result.damage = dmg
	result.healing = heal
	return result

# === HELPER METHODS ===

static func _extract_skill_effects(result: ActionResult, skill: Skill, message: String):
	"""Extract damage, healing, and status effects from skill"""
	
	#  FIX 1: Extract damage from message (handles both "X damage" and "X fire damage" etc)
	var damage_regex = RegEx.new()
	damage_regex.compile("dealt.*?(\\d+).*?damage")  # More flexible pattern
	var damage_match = damage_regex.search(message)
	if damage_match:
		result.damage = int(damage_match.get_string(1))
		print("[ACTIONRESULT] Extracted damage: %d from message: %s" % [result.damage, message])
	else:
		# Fallback: Try simpler pattern
		damage_regex.compile("(\\d+) damage")
		damage_match = damage_regex.search(message)
		if damage_match:
			result.damage = int(damage_match.get_string(1))
			print("[ACTIONRESULT] Extracted damage (fallback): %d" % result.damage)
	
	# Extract healing from message
	var heal_regex = RegEx.new()
	heal_regex.compile("(?:heals?|restored?) (\\d+)")
	var heal_match = heal_regex.search(message)
	if heal_match:
		result.healing = int(heal_match.get_string(1))
	
	# Check for drain skills
	if skill.type == Skill.SkillType.DRAIN:
		# For drain skills, healing goes to caster
		if "drained" in message.to_lower() and result.damage > 0:
			result.healing = int(result.damage * skill.drain_efficiency)
	
	#  FIX 2: Extract status effects from skill.status_effects array (plural)
	if not skill.status_effects.is_empty():
		for effect_enum in skill.status_effects:
			if effect_enum != Skill.StatusEffect.NONE:
				result.status_effects.append({
					"name": Skill.StatusEffect.keys()[effect_enum],
					"duration": skill.duration
				})
				print("[ACTIONRESULT] Added status effect: %s for %d turns" % [
					Skill.StatusEffect.keys()[effect_enum], skill.duration
				])
	
	#  FIX 3: Extract buffs/debuffs from skill.attribute_targets array (plural)
	if not skill.attribute_targets.is_empty():
		for attr_enum in skill.attribute_targets:
			if attr_enum != Skill.AttributeTarget.NONE:
				var effect_data = {
					"stat": Skill.AttributeTarget.keys()[attr_enum],
					"amount": skill.power,
					"duration": skill.duration
				}
				
				if skill.type == Skill.SkillType.BUFF:
					result.buffs.append(effect_data)
				elif skill.type == Skill.SkillType.DEBUFF:
					effect_data["is_debuff"] = true
					result.debuffs.append(effect_data)

static func _extract_item_effects(result: ActionResult, item, message: String, targets: Array):
	""" FIXED: Extract damage, healing, status effects AND removals from item"""
	
	# Extract damage from message
	var damage_regex = RegEx.new()
	damage_regex.compile("(\\d+) damage")
	var damage_match = damage_regex.search(message)
	if damage_match:
		result.damage = int(damage_match.get_string(1))
	
	# Extract healing from message
	var heal_regex = RegEx.new()
	heal_regex.compile("(?:heals?|restored?) (\\d+)")
	var heal_match = heal_regex.search(message)
	if heal_match:
		result.healing = int(heal_match.get_string(1))
	
	#  CRITICAL FIX: For damage items, check if status was ACTUALLY applied to target
	# (accounts for RNG chance like poison_chance on Flame Flask)
	if item.consumable_type == Item.ConsumableType.DAMAGE:
		if "status_effect" in item and item.status_effect != Skill.StatusEffect.NONE:
			# Check if the effect appears in the message (means it was applied)
			var effect_name = Skill.StatusEffect.keys()[item.status_effect]
			if effect_name.to_lower() in message.to_lower():
				result.status_effects.append({
					"name": effect_name,
					"duration": item.effect_duration
				})
	
	#  NEW: Track status effects REMOVED (cure items like antidote)
	elif item.consumable_type == Item.ConsumableType.CURE:
		if "status_effect" in item and item.status_effect != Skill.StatusEffect.NONE:
			# Specific cure (antidote, coolroot, etc)
			result.status_effects_removed.append({
				"name": Skill.StatusEffect.keys()[item.status_effect]
			})
		else:
			# Cure all (holy water) - mark with special flag
			result.status_effects_removed.append({
				"name": "ALL"
			})
	
	#  NEW: Track buffs from buff items (berserker brew, smoke bomb)
	elif item.consumable_type == Item.ConsumableType.BUFF:
		if "buff_type" in item and item.buff_type != "":
			var buff_value = 0
			if item.is_percentage_based:
				buff_value = int(item.effect_percent * 100)
			else:
				buff_value = item.effect_power
			
			# Map buff_type string to AttributeTarget
			var stat_name = ""
			if item.buff_type == "ATTACK":
				stat_name = "STRENGTH"
			elif item.buff_type == "DODGE":
				stat_name = "AGILITY"
			else:
				stat_name = item.buff_type
			
			result.buffs.append({
				"stat": stat_name,
				"amount": buff_value,
				"duration": item.effect_duration
			})

# === QUERY METHODS ===

func has_level_up() -> bool:
	return level_up_message != ""

func get_description() -> String:
	return message

func was_successful() -> bool:
	return success

func get_log_color() -> String:
	"""Get appropriate combat log color for this result"""
	if was_missed or was_dodged:
		return "gray"
	elif is_critical:
		return "orange"
	elif damage > 0:
		return "red"
	elif healing > 0:
		return "green"
	elif not status_effects.is_empty() or not buffs.is_empty() or not debuffs.is_empty():
		return "purple"
	else:
		return "white"
