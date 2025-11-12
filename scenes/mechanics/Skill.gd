# scenes/mechanics/Skill.gd
class_name Skill
extends Resource

enum SkillType { DAMAGE, HEAL, BUFF, DEBUFF, RESTORE, INFLICT_STATUS }
enum TargetType { SELF, ALLY, ENEMY, ALL_ALLIES, ALL_ENEMIES }
enum AttributeTarget { 
	NONE, 
	VITALITY, 
	STRENGTH, 
	DEXTERITY, 
	INTELLIGENCE, 
	FAITH, 
	MIND, 
	ENDURANCE, 
	ARCANE, 
	AGILITY, 
	FORTITUDE 
}
enum StatusEffect { NONE, POISON, BURN, FREEZE, SHOCK }
enum AbilityType { PHYSICAL, MAGICAL }

@export var ability_type: AbilityType
@export var name: String
@export var description: String
@export var type: SkillType
@export var target: TargetType

# CHANGED: Now arrays to support multiple targets
@export var attribute_targets: Array = []  # Array of AttributeTarget enums
@export var status_effects: Array = []  # Array of StatusEffect enums

@export var power: int
@export var duration: int
@export var mp_cost: int
@export var sp_cost: int
@export var cooldown: int

# Skill leveling
@export var level: int = 1
@export var uses: int = 0
@export var base_power: int
@export var base_mp_cost: int
@export var base_sp_cost: int
@export var base_cooldown: int
@export var base_duration: int

const LEVEL_THRESHOLDS = [5, 25, 125, 625, 1500]

static func create_from_dict(data: Dictionary) -> Skill:
	var skill = Skill.new()
	skill.name = data.name
	skill.description = data.description
	skill.ability_type = AbilityType[data.ability_type.to_upper()]
	skill.type = SkillType[data.type.to_upper()]
	skill.target = TargetType[data.target.to_upper()]
	
	# Parse attribute_targets - handles multiple formats
	skill.attribute_targets = []
	if data.has("attribute_targets") and data.attribute_targets is Array:
		# New plural array format: "attribute_targets": ["FORTITUDE", "ENDURANCE"]
		for attr_str in data.attribute_targets:
			if attr_str != "" and AttributeTarget.has(attr_str.to_upper()):
				skill.attribute_targets.append(AttributeTarget[attr_str.to_upper()])
	elif data.has("attribute_target"):
		# Handle both string and array for backward compatibility
		var attr_data = data.attribute_target
		if attr_data is Array:
			# Array format: "attribute_target": ["FORTITUDE"]
			for attr_str in attr_data:
				if attr_str != "" and attr_str != "NONE" and AttributeTarget.has(attr_str.to_upper()):
					skill.attribute_targets.append(AttributeTarget[attr_str.to_upper()])
		elif attr_data is String:
			# String format: "attribute_target": "FORTITUDE"
			if attr_data != "" and attr_data != "NONE" and AttributeTarget.has(attr_data.to_upper()):
				skill.attribute_targets.append(AttributeTarget[attr_data.to_upper()])
	
	# Parse status_effects - handles multiple formats
	skill.status_effects = []
	if data.has("status_effects") and data.status_effects is Array:
		# New plural array format: "status_effects": ["FREEZE", "SHOCK"]
		for effect_str in data.status_effects:
			if effect_str != "" and StatusEffect.has(effect_str.to_upper()):
				skill.status_effects.append(StatusEffect[effect_str.to_upper()])
	elif data.has("status_effect"):
		# Handle both string and array for backward compatibility
		var effect_data = data.status_effect
		if effect_data is Array:
			# Array format: "status_effect": ["BURN"]
			for effect_str in effect_data:
				if effect_str != "" and effect_str != "NONE" and StatusEffect.has(effect_str.to_upper()):
					skill.status_effects.append(StatusEffect[effect_str.to_upper()])
		elif effect_data is String:
			# String format: "status_effect": "BURN"
			if effect_data != "" and effect_data != "NONE" and StatusEffect.has(effect_data.to_upper()):
				skill.status_effects.append(StatusEffect[effect_data.to_upper()])
	
	skill.base_power = data.power
	skill.base_mp_cost = data.get("mp_cost", 0)
	skill.base_sp_cost = data.get("sp_cost", 0)
	skill.base_cooldown = data.cooldown
	skill.base_duration = data.duration
	
	skill.level = 1
	skill.uses = 0
	
	skill.power = skill.base_power
	skill.mp_cost = skill.base_mp_cost
	skill.sp_cost = skill.base_sp_cost
	skill.cooldown = skill.base_cooldown
	skill.duration = skill.base_duration
	
	return skill

func get_level_string() -> String:
	return "Max" if level >= 6 else str(level)

func get_uses_for_next_level() -> int:
	return LEVEL_THRESHOLDS[level - 1] if level <= 5 else -1

func check_level_up() -> bool:
	if level >= 6:
		return false
	
	var threshold_index = level - 1
	if uses >= LEVEL_THRESHOLDS[threshold_index]:
		level_up()
		return true
	return false

func level_up():
	level += 1
	calculate_level_bonuses()
	
func calculate_level_bonuses():
	var power_multipliers = [1.0, 1.1, 1.25, 1.45, 1.7, 2.0]
	var cost_multipliers = [1.0, 0.95, 0.9, 0.85, 0.75, 0.6]
	var cooldown_reductions = [0, 0, 1, 1, 2, 3]
	var duration_bonuses = [0, 1, 1, 2, 2, 3]
	
	var level_index = min(level - 1, 5)
	
	if type in [SkillType.DAMAGE, SkillType.HEAL, SkillType.RESTORE]:
		power = int(base_power * power_multipliers[level_index])
	elif type in [SkillType.BUFF, SkillType.DEBUFF]:
		power = int(base_power * power_multipliers[level_index])
		duration = base_duration + duration_bonuses[level_index]
	elif type == SkillType.INFLICT_STATUS:
		duration = base_duration + duration_bonuses[level_index]
	
	mp_cost = max(1, int(base_mp_cost * cost_multipliers[level_index]))
	sp_cost = max(1, int(base_sp_cost * cost_multipliers[level_index]))
	cooldown = max(0, base_cooldown - cooldown_reductions[level_index])

func on_skill_used():
	uses += 1
	if check_level_up():
		return "Skill leveled up to " + get_level_string() + "!"
	return ""

func use(user: CharacterData, targets: Array):
	match type:
		SkillType.DAMAGE:
			return deal_damage(user, targets)
		SkillType.HEAL:
			return heal(user, targets)
		SkillType.BUFF:
			return apply_buff(user, targets)
		SkillType.DEBUFF:
			return apply_debuff(user, targets)
		SkillType.RESTORE:
			return restore(user, targets)
		SkillType.INFLICT_STATUS:
			return inflict_status(user, targets)

func deal_damage(user: CharacterData, targets: Array):
	var total_damage = 0
	var was_crit = false
	
	var momentum_multiplier = MomentumSystem.get_damage_multiplier()
	
	for t in targets:
		var base_damage = power + (user.attack_power if ability_type == AbilityType.PHYSICAL else user.spell_power)
		base_damage *= momentum_multiplier
		
		var resistance = (t.toughness if ability_type == AbilityType.PHYSICAL else t.spell_ward)
		var accuracy_check = randf() < user.accuracy
		var dodge_check = randf() < t.dodge
		var crit_check = randf() < user.critical_hit_rate
		
		if not accuracy_check:
			return "%s's attack missed!" % user.name
		
		if dodge_check:
			return "%s dodged the attack!" % t.name
		
		var damage = max(1, base_damage - resistance)
		
		if crit_check:
			damage *= 1.5 + randf() * 0.5
			was_crit = true
		
		t.take_damage(damage)
		total_damage += damage
		
		# NEW: Apply all status effects
		for effect in status_effects:
			if effect != StatusEffect.NONE:
				t.apply_status_effect(effect, duration)
	
	var result = "%s dealt %.1f damage to %d target(s)" % [name, total_damage, targets.size()]
	
	if momentum_multiplier > 1.0:
		var bonus_pct = int((momentum_multiplier - 1.0) * 100)
		result += " (+%d%% momentum)" % bonus_pct
	
	if was_crit:
		result = "Critical hit! " + result
	
	# NEW: List all status effects applied
	if not status_effects.is_empty():
		var effect_names = []
		for effect in status_effects:
			if effect != StatusEffect.NONE:
				effect_names.append(StatusEffect.keys()[effect])
		if not effect_names.is_empty():
			result += " and applied " + ", ".join(effect_names)
	
	return result

func heal(user: CharacterData, targets: Array):
	var total_heal = 0
	for t in targets:
		var heal_amount = power + user.spell_power
		t.heal(heal_amount)
		total_heal += heal_amount
	return "%s healed %d HP to %d target(s)" % [name, total_heal, targets.size()]

func apply_buff(_user: CharacterData, targets: Array):
	# NEW: Apply buffs to ALL attribute_targets
	if attribute_targets.is_empty():
		return "%s had no effect!" % name
	
	for t in targets:
		for attribute in attribute_targets:
			if attribute != AttributeTarget.NONE:
				t.apply_buff(attribute, power, duration)
	
	var attr_names = []
	for attr in attribute_targets:
		if attr != AttributeTarget.NONE:
			attr_names.append(AttributeTarget.keys()[attr])
	
	return "%s buffed %s of %d target(s) by %d for %d turns" % [
		name, 
		", ".join(attr_names), 
		targets.size(), 
		power, 
		duration
	]

func apply_debuff(_user: CharacterData, targets: Array):
	for t in targets:
		# NEW: Apply all status effects
		for effect in status_effects:
			if effect != StatusEffect.NONE:
				t.apply_status_effect(effect, duration)
		
		# NEW: Apply debuffs to all attribute_targets
		for attribute in attribute_targets:
			if attribute != AttributeTarget.NONE:
				t.apply_debuff(attribute, power, duration)
	
	var result_parts = []
	
	# Build status effect part
	if not status_effects.is_empty():
		var effect_names = []
		for effect in status_effects:
			if effect != StatusEffect.NONE:
				effect_names.append(StatusEffect.keys()[effect])
		if not effect_names.is_empty():
			result_parts.append("inflicted " + ", ".join(effect_names))
	
	# Build attribute debuff part
	if not attribute_targets.is_empty():
		var attr_names = []
		for attr in attribute_targets:
			if attr != AttributeTarget.NONE:
				attr_names.append(AttributeTarget.keys()[attr])
		if not attr_names.is_empty():
			result_parts.append("debuffed " + ", ".join(attr_names) + " by " + str(power))
	
	if result_parts.is_empty():
		return "%s had no effect!" % name
	
	return "%s %s on %d target(s) for %d turns" % [
		name,
		" and ".join(result_parts),
		targets.size(),
		duration
	]

func restore(user: CharacterData, targets: Array):
	var total_heal = 0
	for t in targets:
		var heal_amount = power + user.spell_power
		t.restore_mp(heal_amount)
		total_heal += heal_amount
	return "%s healed %d MP to %d target(s)" % [name, total_heal, targets.size()]

func inflict_status(_user: CharacterData, targets: Array):
	# NEW: Apply all status effects to each target
	for t in targets:
		for effect in status_effects:
			if effect != StatusEffect.NONE:
				t.apply_status_effect(effect, duration)
	
	var effect_names = []
	for effect in status_effects:
		if effect != StatusEffect.NONE:
			effect_names.append(StatusEffect.keys()[effect])
	
	if effect_names.is_empty():
		return "%s had no effect!" % name
	
	return "%s inflicted %s on %d target(s) for %d turns" % [
		name, 
		", ".join(effect_names), 
		targets.size(),
		duration
	]
