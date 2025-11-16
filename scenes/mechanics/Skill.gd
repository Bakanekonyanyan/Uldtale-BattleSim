# scenes/mechanics/Skill.gd
class_name Skill
extends Resource


enum SkillType { DAMAGE, HEAL, BUFF, DEBUFF, RESTORE, INFLICT_STATUS, DRAIN }
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
enum StatusEffect { 
	NONE, 
	POISON,       # Earth element
	BURN,         # Fire element
	FREEZE,       # Ice element
	BLEED,        # Wind element
	SHOCK,        # Lightning element
	CONFUSED,     # Holy element
	BLIND,        # Holy/Dark element
	SLEEP,        # Dark element
	REGENERATION, # Buff effect
	ENRAGED,      # Buff effect
	REFLECT       # Buff effect
}
enum AbilityType { PHYSICAL, MAGICAL }
enum DrainTarget {HP, MP, SP }
enum ElementType {
	NONE,
	EARTH,
	FIRE,
	ICE,
	WIND,
	LIGHTNING,
	HOLY,
	DARK,
	PHYSICAL  # Non-elemental physical damage
}

# Add this as an export variable
@export var element: ElementType = ElementType.NONE
@export var elements: Array = []

@export var ability_type: AbilityType
@export var name: String
@export var description: String
@export var type: SkillType
@export var target: TargetType

# CHANGED: Now arrays to support multiple targets
@export var attribute_targets: Array = []  # Array of AttributeTarget enums
@export var status_effects: Array = []  # Array of StatusEffect enums
@export var drain_target: DrainTarget = DrainTarget.HP
@export var drain_efficiency: float = 0.5  # 50% of damage becomes healing

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
	
	# ✅ PARSE ELEMENTS - supports both single string and array
	skill.elements = []
	if data.has("elements") and data.elements is Array:
		# New plural array format: "elements": ["FIRE", "HOLY"]
		for elem_str in data.elements:
			if elem_str != "" and elem_str != "NONE" and ElementType.has(elem_str.to_upper()):
				skill.elements.append(ElementType[elem_str.to_upper()])
	elif data.has("element"):
		# Handle single element for backward compatibility
		var elem_data = data.element
		if elem_data is String and elem_data != "" and elem_data != "NONE":
			if ElementType.has(elem_data.to_upper()):
				skill.elements.append(ElementType[elem_data.to_upper()])
	
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
	
	if data.has("drain_target"):
		skill.drain_target = DrainTarget[data.drain_target.to_upper()]
	if data.has("drain_efficiency"):
		skill.drain_efficiency = data.drain_efficiency
	
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
		SkillType.DRAIN:  # ✅ NEW
			return drain(user, targets)

func deal_damage(user: CharacterData, targets: Array):
	var total_damage = 0
	var was_crit = false
	
	var momentum_multiplier = MomentumSystem.get_damage_multiplier()
	
	# ✅ Convert skill elements to ElementalDamage.Element array
	var elemental_types = []
	for elem in elements:
		if elem != ElementType.NONE and elem != ElementType.PHYSICAL:
			match elem:
				ElementType.EARTH: elemental_types.append(ElementalDamage.Element.EARTH)
				ElementType.FIRE: elemental_types.append(ElementalDamage.Element.FIRE)
				ElementType.ICE: elemental_types.append(ElementalDamage.Element.ICE)
				ElementType.WIND: elemental_types.append(ElementalDamage.Element.WIND)
				ElementType.LIGHTNING: elemental_types.append(ElementalDamage.Element.LIGHTNING)
				ElementType.HOLY: elemental_types.append(ElementalDamage.Element.HOLY)
				ElementType.DARK: elemental_types.append(ElementalDamage.Element.DARK)
	
	var elemental_results = []  # Store results for each element
	
	for t in targets:
		var base_damage = power + (user.attack_power if ability_type == AbilityType.PHYSICAL else user.spell_power)
		base_damage *= momentum_multiplier
		
		var resistance = (t.toughness if ability_type == AbilityType.PHYSICAL else t.spell_ward)
		var accuracy_check = RandomManager.randf() < user.accuracy
		var dodge_check = RandomManager.randf() < t.dodge
		var crit_check = RandomManager.randf() < user.critical_hit_rate
		
		if not accuracy_check:
			return "%s's attack missed!" % user.name
		
		if dodge_check:
			return "%s dodged the attack!" % t.name
		
		var damage = max(1, base_damage - resistance)
		
		# ✅ APPLY ELEMENTAL DAMAGE FOR EACH ELEMENT
		if not elemental_types.is_empty() and t.elemental_resistances:
			var total_multiplier = 1.0
			var is_weak = false
			var is_resistant = false
			
			# Apply each element's modifiers
			for elemental_type in elemental_types:
				var attacker_bonus = user.get_elemental_damage_bonus(elemental_type)
				var target_resistance = t.get_elemental_resistance(elemental_type)
				var target_weakness = t.get_elemental_weakness(elemental_type)
				
				var elem_result = ElementalDamage.calculate_elemental_damage(
					1.0,  # Use 1.0 to get just the multiplier
					elemental_type,
					attacker_bonus,
					target_resistance,
					target_weakness
				)
				
				# Combine multipliers (multiplicative)
				total_multiplier *= elem_result.multiplier
				
				if elem_result.is_weak:
					is_weak = true
				if elem_result.is_resistant:
					is_resistant = true
			
			damage *= total_multiplier
			
			# Store combined result
			elemental_results.append({
				"damage": damage,
				"is_weak": is_weak,
				"is_resistant": is_resistant,
				"elements": elemental_types
			})
		
		if crit_check:
			damage *= 1.5 + RandomManager.randf() * 0.5
			was_crit = true
		
		t.take_damage(damage, user)
		total_damage += damage
		
		# Apply status effects
		for effect in status_effects:
			if effect != StatusEffect.NONE:
				t.apply_status_effect(effect, duration)
	
	# Build result message
	var result = ""
	
	if was_crit:
		result = "Critical hit! "
	
	# ✅ BUILD ELEMENTAL MESSAGE WITH DAMAGE BREAKDOWN
	if not elemental_results.is_empty():
		var elem_result = elemental_results[0]
		
		# Build element names string
		var element_names = []
		for elem in elem_result.elements:
			element_names.append(ElementalDamage.get_element_name(elem))
		
		var element_str = " + ".join(element_names) if element_names.size() > 1 else element_names[0]
		
		# Get color from first element
		var color = ElementalDamage.get_element_color(elem_result.elements[0])
		
		# Calculate base damage (before elemental modifiers)
		var base_only = power + (user.attack_power if ability_type == AbilityType.PHYSICAL else user.spell_power)
		base_only *= momentum_multiplier
		base_only = max(1, base_only - (targets[0].toughness if ability_type == AbilityType.PHYSICAL else targets[0].spell_ward))
		
		var elemental_bonus = int(total_damage - base_only)
		
		# Show damage breakdown
		if elemental_bonus > 0:
			result += "%s dealt [color=%s]%d (%+d) %s damage[/color] to %s" % [
				user.name,
				color,
				int(total_damage),
				elemental_bonus,
				element_str,
				targets[0].name if targets.size() == 1 else "%d enemies" % targets.size()
			]
		elif elemental_bonus < 0:
			result += "%s dealt [color=%s]%d (%d) %s damage[/color] to %s" % [
				user.name,
				color,
				int(total_damage),
				elemental_bonus,
				element_str,
				targets[0].name if targets.size() == 1 else "%d enemies" % targets.size()
			]
		else:
			result += "%s dealt [color=%s]%d %s damage[/color] to %s" % [
				user.name,
				color,
				int(total_damage),
				element_str,
				targets[0].name if targets.size() == 1 else "%d enemies" % targets.size()
			]
		
		if elem_result.is_weak:
			result += " [color=orange](WEAK!)[/color]"
		elif elem_result.is_resistant:
			result += " [color=cyan](RESIST)[/color]"
	else:
		result += "%s dealt %d damage to %d target(s)" % [name, int(total_damage), targets.size()]
	
	if momentum_multiplier > 1.0:
		var bonus_pct = int((momentum_multiplier - 1.0) * 100)
		result += " (+%d%% momentum)" % bonus_pct
	
	# List status effects applied
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

# =============================================
# DRAIN SKILL IMPLEMENTATION
# =============================================

func drain(user: CharacterData, targets: Array) -> String:
	"""Drain resource from target and restore user"""
	var total_drained = 0
	var total_restored = 0
	
	for t in targets:
		var drain_amount = 0
		
		match drain_target:
			DrainTarget.HP:
				# Drain HP (like damage)
				var base_damage = power + user.spell_power
				var resistance = t.toughness
				drain_amount = max(1, base_damage - resistance)
				
				# Apply damage
				t.take_damage(drain_amount)
				
				# Heal user
				var heal_amount = int(drain_amount * drain_efficiency)
				user.heal(heal_amount)
				total_restored = heal_amount
				
			DrainTarget.MP:
				# Drain MP
				drain_amount = min(power, t.current_mp)
				t.current_mp -= drain_amount
				
				# Restore user MP
				var restore_amount = int(drain_amount * drain_efficiency)
				user.restore_mp(restore_amount)
				total_restored = restore_amount
				
			DrainTarget.SP:
				# Drain SP
				drain_amount = min(power, t.current_sp)
				t.current_sp -= drain_amount
				
				# Restore user SP
				var restore_amount = int(drain_amount * drain_efficiency)
				user.restore_sp(restore_amount)
				total_restored = restore_amount
		
		total_drained += drain_amount
	
	var resource_name = DrainTarget.keys()[drain_target]
	return "%s drained %d %s from %d target(s) and restored %d %s" % [
		name, total_drained, resource_name, targets.size(), total_restored, resource_name
	]

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
